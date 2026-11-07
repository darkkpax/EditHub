use crate::projects::{self, Result};
use futures_util::StreamExt;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha1::{Digest, Sha1};
use std::{
    collections::{HashMap, VecDeque},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tauri::Emitter;
use tokio::{fs, io::AsyncWriteExt};
use tokio_util::sync::CancellationToken;
use url::Url;

pub fn normalize(raw: &str) -> Result<Url> {
    let mut u = Url::parse(raw.trim()).map_err(|_| "Invalid URL")?;
    if !["http", "https"].contains(&u.scheme())
        || u.host_str().is_none()
        || !u.username().is_empty()
        || u.password().is_some()
    {
        return Err("Use an HTTP or HTTPS URL without credentials".into());
    }
    let host = u.host_str().unwrap().to_lowercase();
    if [
        "dropbox.com",
        "www.dropbox.com",
        "dl.dropboxusercontent.com",
    ]
    .contains(&host.as_str())
    {
        // The www host supports both file and folder shares, including /scl/fo/.
        u.set_host(Some("www.dropbox.com"))
            .map_err(|e| e.to_string())?;
        let pairs: Vec<_> = u
            .query_pairs()
            .filter(|(k, _)| k != "dl" && k != "raw")
            .map(|(k, v)| (k.into_owned(), v.into_owned()))
            .collect();
        u.set_query(None);
        u.query_pairs_mut()
            .extend_pairs(pairs)
            .append_pair("dl", "1");
    } else if host == "drive.google.com" {
        if let Some(id) = drive_id(&u) {
            if !u.path().contains("/folders/") {
                let key = u
                    .query_pairs()
                    .find(|(k, _)| k == "resourcekey")
                    .map(|(_, v)| v.into_owned());
                u = Url::parse("https://drive.usercontent.google.com/download").unwrap();
                u.query_pairs_mut()
                    .append_pair("export", "download")
                    .append_pair("id", &id);
                if let Some(key) = key {
                    u.query_pairs_mut().append_pair("resourcekey", &key);
                }
            }
        } else {
            return Err("Google Drive file ID missing".into());
        }
    }
    u.set_fragment(None);
    Ok(u)
}
fn drive_id(u: &Url) -> Option<String> {
    let parts: Vec<_> = u.path_segments()?.collect();
    let id = parts
        .windows(2)
        .find(|p| p[0] == "d" || p[0] == "folders")
        .map(|p| p[1].to_string())
        .or_else(|| {
            u.query_pairs()
                .find(|(k, _)| k == "id")
                .map(|(_, v)| v.into_owned())
        })?;
    if id.is_empty()
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return None;
    }
    Some(id)
}
pub fn safe_name(raw: &str) -> Result<String> {
    if raw.contains('/') || raw.contains('\\') || raw == "." || raw == ".." {
        return Err("Invalid filename".into());
    }
    let name: String = raw
        .chars()
        .map(|c| {
            if c.is_control() || "<>:\"|?*".contains(c) {
                '_'
            } else {
                c
            }
        })
        .collect();
    let name = name.trim().trim_end_matches(['.', ' ']);
    let stem = name.split('.').next().unwrap_or("").to_uppercase();
    if name.is_empty()
        || [
            "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7",
            "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        ]
        .contains(&stem.as_str())
    {
        return Err("Invalid filename".into());
    }
    Ok(name.to_string())
}
pub fn confirmation(html: &str) -> Result<Url> {
    let doc = Html::parse_document(html);
    let form = doc
        .select(&Selector::parse("form#download-form").unwrap())
        .next()
        .ok_or("Google Drive denied download. Check file access and quota")?;
    let mut u = Url::parse(
        form.value()
            .attr("action")
            .ok_or("Google Drive confirmation URL missing")?,
    )
    .map_err(|e| e.to_string())?;
    if u.scheme() != "https"
        || !["drive.google.com", "drive.usercontent.google.com"]
            .contains(&u.host_str().unwrap_or(""))
    {
        return Err("Unsafe Google Drive confirmation URL".into());
    }
    for input in form.select(&Selector::parse("input[name]").unwrap()) {
        let name = input.value().attr("name").unwrap();
        let value = input.value().attr("value").unwrap_or("");
        u.query_pairs_mut().append_pair(name, value);
    }
    Ok(u)
}
#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub project_id: String,
    pub file_url: String,
    pub file_name: String,
    pub bytes_downloaded: u64,
    pub total_bytes: u64,
    pub percent: u8,
    pub state: String,
    pub error: Option<String>,
}
#[derive(Default)]
pub struct Downloads {
    pub work: Mutex<Work>,
}
#[derive(Default)]
pub struct Work {
    pub active: HashMap<String, CancellationToken>,
    pub pending: VecDeque<QueuedDownload>,
    pub running: Option<String>,
}
pub struct QueuedDownload {
    pub id: String,
    pub project: Value,
    pub cancel: CancellationToken,
}
impl Work {
    pub fn next(&mut self) -> Option<QueuedDownload> {
        if self.running.is_some() {
            return None;
        }
        let next = self.pending.pop_front()?;
        self.running = Some(next.id.clone());
        Some(next)
    }

    pub fn prioritize(&mut self, id: &str) -> Result<()> {
        let index = self
            .pending
            .iter()
            .position(|job| job.id == id)
            .ok_or("Project is no longer queued")?;
        let next = self.pending.remove(index).unwrap();
        self.pending.push_front(next);
        if let Some(cancel) = self.running.as_ref().and_then(|id| self.active.get(id)) {
            cancel.cancel();
        }
        Ok(())
    }
}
#[derive(Clone)]
struct Job {
    url: Url,
    source: String,
    relative: PathBuf,
    name: Option<String>,
    token: Option<String>,
    key: Option<String>,
}
impl Job {
    fn key(&self) -> String {
        format!(
            "{:x}",
            Sha1::digest(
                format!(
                    "{:?}",
                    (&self.url, &self.source, &self.relative, &self.name)
                )
                .as_bytes()
            )
        )
    }
}
fn client() -> Result<reqwest::Client> {
    reqwest::Client::builder()
        .cookie_store(true)
        .user_agent("Mozilla/5.0 EditHub/2.0")
        .connect_timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::limited(12))
        .build()
        .map_err(|e| e.to_string())
}
async fn drive_get(
    c: &reqwest::Client,
    path: &str,
    params: Vec<(&str, String)>,
    token: &Option<String>,
    key: &Option<String>,
) -> Result<Value> {
    let mut request = c
        .get(format!("https://www.googleapis.com/drive/v3/{path}"))
        .query(&params)
        .query(&[("supportsAllDrives", "true")])
        .timeout(Duration::from_secs(30));
    if let Some(t) = token {
        request = request.bearer_auth(t);
    }
    if let Some(k) = key {
        request = request.query(&[("key", k)]);
    }
    let r = request.send().await.map_err(http_error)?;
    if !r.status().is_success() {
        return Err(format!(
            "Google Drive HTTP {}: check folder permissions and account connection",
            r.status().as_u16()
        ));
    }
    r.json().await.map_err(http_error)
}
fn http_error(error: reqwest::Error) -> String {
    error.without_url().to_string()
}
#[derive(Debug)]
struct PublicEntry {
    name: String,
    url: Url,
    folder: bool,
}
fn public_folder_entries(html: &str) -> Result<Vec<PublicEntry>> {
    let doc = Html::parse_document(html);
    if doc
        .select(&Selector::parse("#flip-contents").unwrap())
        .next()
        .is_none()
    {
        return Err(
            "Google Drive folder requires sign-in. Connect your account in Settings".into(),
        );
    }
    let mut result = vec![];
    for entry in doc.select(&Selector::parse(".flip-entry").unwrap()) {
        let link = entry
            .select(&Selector::parse("a[href]").unwrap())
            .next()
            .ok_or("Could not read Google Drive folder link")?;
        let url = Url::parse(link.value().attr("href").unwrap()).map_err(|e| e.to_string())?;
        if url.scheme() != "https"
            || url.host_str() != Some("drive.google.com")
            || drive_id(&url).is_none()
        {
            return Err("Unsupported link in public folder. Connect your account or export Google Docs first".into());
        }
        let title = entry
            .select(&Selector::parse(".flip-entry-title").unwrap())
            .next()
            .ok_or("Google Drive filename missing")?
            .text()
            .collect::<String>();
        result.push(PublicEntry {
            name: safe_name(&title)?,
            folder: url.path().contains("/folders/"),
            url,
        });
    }
    Ok(result)
}
async fn public_folder_jobs(c: &reqwest::Client, source: &str) -> Result<Vec<Job>> {
    let root = Url::parse(source).map_err(|e| e.to_string())?;
    let mut queue = vec![(root, PathBuf::new())];
    let mut seen = std::collections::HashSet::new();
    let mut result = vec![];
    while let Some((folder, prefix)) = queue.pop() {
        let id = drive_id(&folder).ok_or("Folder ID missing")?;
        if !seen.insert(id.clone()) {
            continue;
        }
        let mut url = Url::parse("https://drive.google.com/embeddedfolderview").unwrap();
        url.query_pairs_mut().append_pair("id", &id);
        if let Some((_, key)) = folder.query_pairs().find(|(k, _)| k == "resourcekey") {
            url.query_pairs_mut().append_pair("resourcekey", &key);
        }
        let mut entries = None;
        let mut last = String::new();
        for attempt in 0..3 {
            let response = c
                .get(url.clone())
                .timeout(Duration::from_secs(45))
                .send()
                .await;
            let parsed = match response {
                Ok(r) if r.status().is_success() => match html_body(r).await {
                    Ok(html) => public_folder_entries(&html),
                    Err(e) => Err(e),
                },
                Ok(r) => Err(format!(
                    "Google Drive HTTP {}: could not read public folder",
                    r.status().as_u16()
                )),
                Err(e) => Err(http_error(e)),
            };
            match parsed {
                Ok(value) => {
                    entries = Some(value);
                    break;
                }
                Err(e) => last = e,
            }
            if attempt < 2 {
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
        }
        for entry in entries.ok_or(last)? {
            if entry.folder {
                queue.push((entry.url, prefix.join(entry.name)));
            } else {
                result.push(Job {
                    url: normalize(entry.url.as_str())?,
                    source: source.into(),
                    relative: prefix.clone(),
                    name: Some(entry.name),
                    token: None,
                    key: None,
                });
            }
        }
    }
    Ok(result)
}
async fn jobs(c: &reqwest::Client, urls: &[String]) -> Result<Vec<Job>> {
    let mut out = vec![];
    let mut auth = None;
    for source in urls {
        let original = Url::parse(source).map_err(|e| e.to_string())?;
        let normalized = normalize(source)?;
        if original.host_str() == Some("drive.google.com") {
            let public_error = if original.path().contains("/folders/") {
                match public_folder_jobs(c, source).await {
                    Ok(public) => {
                        out.extend(public);
                        continue;
                    }
                    Err(error) => Some(error),
                }
            } else {
                None
            };
            if auth.is_none() {
                auth = Some(match crate::auth::access(c).await {
                    Ok(auth) => auth,

                    // An expired optional login must not block public file links.
                    Err(_) => (None, None),
                });
            }
            let (token, key) = auth.as_ref().unwrap();
            if original.path().contains("/folders/") {
                if token.is_none() && key.is_none() {
                    return Err(public_error.unwrap());
                }
                let root = drive_id(&original).ok_or("Folder ID missing")?;
                let mut queue = vec![(root, PathBuf::new())];
                let mut seen = std::collections::HashSet::new();
                while let Some((id, prefix)) = queue.pop() {
                    if !seen.insert(id.clone()) {
                        continue;
                    }
                    let mut page = String::new();
                    loop {
                        let mut query = vec![
                            ("q", format!("'{id}' in parents and trashed = false")),
                            ("fields", "nextPageToken,files(id,name,mimeType)".into()),
                            ("pageSize", "1000".into()),
                            ("includeItemsFromAllDrives", "true".into()),
                        ];
                        if !page.is_empty() {
                            query.push(("pageToken", page));
                        }
                        let data = drive_get(c, "files", query, token, key).await?;
                        for item in data["files"].as_array().ok_or("Google file list missing")? {
                            let name = safe_name(
                                item["name"]
                                    .as_str()
                                    .ok_or("Google Drive filename missing")?,
                            )?;
                            let child_id = item["id"].as_str().ok_or("File ID missing")?;
                            let mime = item["mimeType"].as_str().unwrap_or("");
                            if mime == "application/vnd.google-apps.folder" {
                                queue.push((child_id.to_string(), prefix.join(name)));
                            } else if !mime.starts_with("application/vnd.google-apps.") {
                                out.push(Job{url:Url::parse(&format!("https://www.googleapis.com/drive/v3/files/{child_id}?alt=media&supportsAllDrives=true")).unwrap(),source:source.clone(),relative:prefix.clone(),name:Some(name),token:token.clone(),key:key.clone()});
                            } else {
                                return Err("Folder contains Google Docs or shortcuts. Export them to regular files first".into());
                            }
                        }
                        page = data["nextPageToken"].as_str().unwrap_or("").into();
                        if page.is_empty() {
                            break;
                        }
                    }
                }
                continue;
            }
            if let Some(token) = token {
                let id = drive_id(&original).ok_or("Google Drive ID missing")?;
                let data = drive_get(
                    c,
                    &format!("files/{id}"),
                    vec![("fields", "name,mimeType".into())],
                    &Some(token.clone()),
                    key,
                )
                .await?;
                out.push(Job{url:Url::parse(&format!("https://www.googleapis.com/drive/v3/files/{id}?alt=media&supportsAllDrives=true")).unwrap(),source:source.clone(),relative:PathBuf::new(),name:Some(safe_name(data["name"].as_str().ok_or("Filename missing")?)?),token:Some(token.clone()),key:key.clone()});
                continue;
            }
        }
        out.push(Job {
            url: normalized,
            source: source.clone(),
            relative: PathBuf::new(),
            name: None,
            token: None,
            key: None,
        });
    }
    if out.is_empty() {
        return Err("No downloadable files".into());
    }
    Ok(out)
}
fn response_name(r: &reqwest::Response, job: &Job) -> Result<String> {
    if let Some(name) = &job.name {
        return safe_name(name);
    }
    if let Some(h) = r
        .headers()
        .get("content-disposition")
        .and_then(|h| h.to_str().ok())
    {
        for part in h.split(';').map(str::trim) {
            if let Some(v) = part
                .strip_prefix("filename*=UTF-8''")
                .or_else(|| part.strip_prefix("filename*=utf-8''"))
            {
                return safe_name(
                    &percent_encoding::percent_decode_str(v.trim_matches('"')).decode_utf8_lossy(),
                );
            }
        }
        for part in h.split(';').map(str::trim) {
            if let Some(v) = part.strip_prefix("filename=") {
                return safe_name(v.trim_matches('"'));
            }
        }
    }
    let name = job
        .url
        .path_segments()
        .and_then(|mut p| p.next_back())
        .unwrap_or("");
    if name.contains('.') {
        safe_name(&percent_encoding::percent_decode_str(name).decode_utf8_lossy())
    } else {
        Ok(format!(
            "download_{}",
            &format!("{:x}", Sha1::digest(job.source.as_bytes()))[..10]
        ))
    }
}
async fn html_body(r: reqwest::Response) -> Result<String> {
    let mut stream = r.bytes_stream();
    let mut bytes = vec![];
    while let Some(next) = tokio::time::timeout(Duration::from_secs(30), stream.next())
        .await
        .map_err(|_| "Server did not respond")?
    {
        let chunk = next.map_err(http_error)?;
        if bytes.len() + chunk.len() > 2 * 1024 * 1024 {
            return Err("Server returned a page instead of a file".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}
fn retry_status(status: u16) -> bool {
    status == 408 || status == 429 || status >= 500
}
fn resume_headers(existing: u64, validator: Option<&str>) -> Option<(String, String)> {
    let validator = validator.filter(|v| !v.is_empty() && !v.starts_with("W/"))?;
    (existing > 0).then(|| (format!("bytes={existing}-"), validator.into()))
}
async fn publish_file(partial: &Path, target: &Path) -> Result<()> {
    if fs::hard_link(partial, target).await.is_err() {
        // exFAT has no hard links. create_new still protects existing files.
        let mut output = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(target)
            .await
            .map_err(|e| e.to_string())?;
        let copied = async {
            let mut input = fs::File::open(partial).await?;
            tokio::io::copy(&mut input, &mut output).await?;
            output.sync_all().await
        }
        .await;
        drop(output);
        if let Err(e) = copied {
            let _ = fs::remove_file(target).await;
            return Err(e.to_string());
        }
    }
    fs::remove_file(partial).await.map_err(|e| e.to_string())
}
async fn one(
    c: &reqwest::Client,
    job: &Job,
    destination: &Path,
    cancel: &CancellationToken,
    on_progress: Arc<dyn Fn(Progress) + Send + Sync>,
    id: &str,
) -> Result<PathBuf> {
    fs::create_dir_all(destination)
        .await
        .map_err(|e| e.to_string())?;
    let mut dest = destination.to_path_buf();
    for part in job.relative.components() {
        let std::path::Component::Normal(name) = part else {
            return Err("Invalid download path".into());
        };
        dest.push(name);
        if let Ok(meta) = fs::symlink_metadata(&dest).await {
            if meta.file_type().is_symlink() {
                return Err("Download folder contains a symlink".into());
            }
        }
        fs::create_dir_all(&dest).await.map_err(|e| e.to_string())?;
    }
    let hash = if job.name.is_none() {
        // Reuse partial files from older versions for direct links.
        format!(
            "{:x}",
            Sha1::digest(format!("{}{:?}{:?}", job.source, job.relative, job.name).as_bytes())
        )
    } else {
        job.key()
    };
    let partial = dest.join(format!(".edithub-{hash}.part"));
    let metadata = partial.with_extension("validator");
    let archive_record = partial.with_extension("archive");
    if let Ok(name) = fs::read_to_string(&archive_record).await {
        if safe_name(&name).is_ok_and(|safe| safe == name) {
            let archive = dest.join(&name);
            if fs::symlink_metadata(&archive)
                .await
                .is_ok_and(|meta| meta.is_file())
            {
                return finish_zip(archive, &archive_record, cancel, &on_progress, id).await;
            }
        }
    }
    let mut last = String::new();
    // Allow large transfers to recover from temporary network outages.
    for attempt in 0..40 {
        let size = fs::metadata(&partial).await.map(|m| m.len()).unwrap_or(0);
        let validator = fs::read_to_string(&metadata).await.ok();
        let resume = resume_headers(size, validator.as_deref());
        let existing = if resume.is_some() { size } else { 0 };
        let mut current = job.url.clone();
        let mut confirmed = false;
        let response = loop {
            let mut request = c
                .get(current.clone())
                .timeout(Duration::from_secs(60 * 60 * 24));
            if let Some((range, validator)) = &resume {
                request = request.header("Range", range).header("If-Range", validator);
            }
            if let Some(token) = &job.token {
                request = request.bearer_auth(token);
            }
            if let Some(key) = &job.key {
                request = request.query(&[("key", key)]);
            }
            let result = tokio::select! {_=cancel.cancelled()=>return Err("Download cancelled".into()),r=tokio::time::timeout(Duration::from_secs(30),request.send())=>r};
            let response = match result {
                Ok(Ok(r)) => r,
                Ok(Err(e)) => {
                    last = http_error(e);
                    break None;
                }
                Err(_) => {
                    last = "Request timed out".into();
                    break None;
                }
            };
            let status = response.status().as_u16();
            if status == 416 {
                fs::remove_file(&partial).await.map_err(|e| e.to_string())?;
                last = "Server rejected resume; restarting download".into();
                break None;
            }
            if !response.status().is_success() {
                let message = format!("HTTP {status}: check link permissions and download limits");
                if retry_status(status) {
                    last = message;
                    break None;
                }
                return Err(message);
            }
            let html = response
                .headers()
                .get("content-type")
                .and_then(|v| v.to_str().ok())
                .is_some_and(|v| v.contains("text/html"));
            if html {
                if job.url.host_str() == Some("drive.usercontent.google.com") && !confirmed {
                    current = confirmation(&html_body(response).await?)?;
                    confirmed = true;
                    continue;
                }
                return Err("Service returned a page instead of a file. Check download permissions and password protection".into());
            }
            break Some(response);
        };
        if let Some(response) = response {
            let name = response_name(&response, job)?;
            let append = response.status() == reqwest::StatusCode::PARTIAL_CONTENT && existing > 0;
            let range_total = if response.status() == reqwest::StatusCode::PARTIAL_CONTENT {
                let range = response
                    .headers()
                    .get("content-range")
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| v.strip_prefix("bytes "))
                    .and_then(|v| v.split_once('/'))
                    .and_then(|(span, total)| {
                        let (start, end) = span.split_once('-')?;
                        Some((
                            start.parse::<u64>().ok()?,
                            end.parse::<u64>().ok()?,
                            total.parse::<u64>().ok()?,
                        ))
                    });
                let expected_start = if append { existing } else { 0 };
                match range {
                    Some((start, end, total))
                        if start == expected_start && end >= start && end < total =>
                    {
                        Some(total)
                    }
                    _ => return Err("Server returned an invalid file range".into()),
                }
            } else {
                None
            };
            let zip_content_type = response
                .headers()
                .get("content-type")
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.split(';').next())
                .is_some_and(|v| {
                    matches!(v.trim(), "application/zip" | "application/x-zip-compressed")
                });
            let next_validator = response
                .headers()
                .get("etag")
                .or_else(|| response.headers().get("last-modified"))
                .and_then(|v| v.to_str().ok())
                .filter(|v| !v.starts_with("W/"))
                .map(str::to_owned);
            if let Some(value) = next_validator {
                fs::write(&metadata, value)
                    .await
                    .map_err(|e| e.to_string())?;
            } else if !append {
                let _ = fs::remove_file(&metadata).await;
            }
            let mut count = if append { existing } else { 0 };
            let total = range_total
                .or_else(|| response.content_length())
                .unwrap_or(0);
            let mut stream = response.bytes_stream();
            let mut file = fs::OpenOptions::new()
                .create(true)
                .write(true)
                .append(append)
                .truncate(!append)
                .open(&partial)
                .await
                .map_err(|e| e.to_string())?;
            let mut tick = Instant::now() - Duration::from_secs(1);
            let mut failed = false;
            loop {
                let chunk = tokio::select! {_=cancel.cancelled()=>return Err("Download cancelled".into()),chunk=tokio::time::timeout(Duration::from_secs(90),stream.next())=>chunk};
                match chunk {
                    Ok(Some(Ok(bytes))) => {
                        if count == 0
                            && (bytes.starts_with(b"<!DOCTYPE html") || bytes.starts_with(b"<html"))
                        {
                            return Err("Server returned HTML instead of a file".into());
                        }
                        file.write_all(&bytes).await.map_err(|e| e.to_string())?;
                        count += bytes.len() as u64;
                        if tick.elapsed() > Duration::from_millis(100) {
                            on_progress(Progress {
                                project_id: id.into(),
                                file_url: job.source.clone(),
                                file_name: name.clone(),
                                bytes_downloaded: count,
                                total_bytes: total,
                                percent: if total > 0 {
                                    ((count * 100 / total).min(99)) as u8
                                } else {
                                    0
                                },
                                state: "downloading".into(),
                                error: None,
                            });
                            tick = Instant::now();
                        }
                    }
                    Ok(None) => break,
                    Ok(Some(Err(e))) => {
                        last = http_error(e);
                        failed = true;
                        break;
                    }
                    Err(_) => {
                        last = "Download stalled; resuming".into();
                        failed = true;
                        break;
                    }
                }
            }
            file.flush().await.map_err(|e| e.to_string())?;
            drop(file);
            if !failed && (total == 0 || count == total) {
                let zip = zip_content_type
                    || Path::new(&name)
                        .extension()
                        .is_some_and(|v| v.eq_ignore_ascii_case("zip"))
                    || (Path::new(&name).extension().is_none() && has_zip_header(&partial).await?);
                let name = if zip
                    && !Path::new(&name)
                        .extension()
                        .is_some_and(|v| v.eq_ignore_ascii_case("zip"))
                {
                    format!("{name}.zip")
                } else {
                    name
                };
                let target = unused_path(&dest.join(&name))?;
                publish_file(&partial, &target).await?;
                let _ = fs::remove_file(&metadata).await;
                if zip {
                    fs::write(
                        &archive_record,
                        target.file_name().unwrap().to_string_lossy().as_bytes(),
                    )
                    .await
                    .map_err(|e| e.to_string())?;
                    return finish_zip(target, &archive_record, cancel, &on_progress, id).await;
                }
                return Ok(target);
            }
            if !failed {
                last = "Incomplete download".into();
            }
        }
        if attempt < 39 {
            let delay = Duration::from_secs((5 * (attempt + 1)).min(60));
            tokio::select! {_=cancel.cancelled()=>return Err("Download cancelled".into()),_=tokio::time::sleep(delay)=>{}}
        }
    }
    Err(format!("Download failed after 40 attempts: {last}"))
}
async fn has_zip_header(path: &Path) -> Result<bool> {
    use tokio::io::AsyncReadExt;
    let mut file = fs::File::open(path).await.map_err(|e| e.to_string())?;
    let mut header = [0; 4];
    match file.read_exact(&mut header).await {
        Ok(_) => Ok(matches!(
            &header,
            b"PK\x03\x04" | b"PK\x05\x06" | b"PK\x07\x08"
        )),
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => Ok(false),
        Err(e) => Err(e.to_string()),
    }
}

fn unused_path(path: &Path) -> Result<PathBuf> {
    let mut candidate = path.to_owned();
    for suffix in 1.. {
        match std::fs::symlink_metadata(&candidate) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(candidate),
            Err(e) => return Err(e.to_string()),
            Ok(_) => {}
        }
        let stem = path.file_stem().unwrap_or_default().to_string_lossy();
        let extension = path
            .extension()
            .map(|e| format!(".{}", e.to_string_lossy()))
            .unwrap_or_default();
        candidate = path.with_file_name(format!("{stem} ({suffix}){extension}"));
    }
    unreachable!()
}

async fn finish_zip(
    path: PathBuf,
    record: &Path,
    cancel: &CancellationToken,
    on_progress: &Arc<dyn Fn(Progress) + Send + Sync>,
    id: &str,
) -> Result<PathBuf> {
    on_progress(project_progress(
        id,
        "downloading",
        "Extracting and verifying ZIP…",
        None,
    ));
    let token = cancel.clone();
    let result = tokio::task::spawn_blocking(move || extract_zip(&path, &token))
        .await
        .map_err(|e| e.to_string())?;
    if result.is_ok() || !cancel.is_cancelled() {
        let _ = fs::remove_file(record).await;
    }
    result.map_err(|e| format!("ZIP extraction failed: {e}"))
}

fn extract_zip(path: &Path, cancel: &CancellationToken) -> Result<PathBuf> {
    use std::io::{Read, Write};

    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    let staging = tempfile::Builder::new()
        .prefix(".edithub-extract-")
        .tempdir_in(path.parent().ok_or("Archive has no parent folder")?)
        .map_err(|e| e.to_string())?;
    let contents = staging.path().join("files");
    std::fs::create_dir(&contents).map_err(|e| e.to_string())?;
    let mut buffer = vec![0; 256 * 1024];
    let mut original_paths = HashMap::new();
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index).map_err(|e| e.to_string())?;
        // ZIP paths use slashes. Normalize legacy Windows separators before validating.
        let name = entry.name().replace('\\', "/");
        // Dropbox folder downloads may include an empty root directory entry.
        if name == "/" && entry.is_dir() && !entry.is_symlink() && entry.size() == 0 {
            continue;
        }
        let mut target = contents.clone();
        let mut original = String::new();
        for part in name.trim_end_matches('/').split('/') {
            if !original.is_empty() {
                original.push('/');
            }
            original.push_str(part);
            target.push(safe_name(part)?);
            let previous = original_paths
                .entry(target.to_string_lossy().to_lowercase())
                .or_insert_with(|| original.clone());
            if previous != &original {
                return Err("ZIP contains filenames that map to the same path".into());
            }
        }
        if entry.is_symlink() || (!entry.is_dir() && !entry.is_file()) {
            return Err("ZIP contains an unsupported entry".into());
        }
        if entry.is_dir() {
            std::fs::create_dir_all(&target).map_err(|e| e.to_string())?;
            continue;
        }
        std::fs::create_dir_all(target.parent().unwrap()).map_err(|e| e.to_string())?;
        let mut output = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&target)
            .map_err(|e| e.to_string())?;
        loop {
            if cancel.is_cancelled() {
                return Err("Download paused".into());
            }
            // Reading through EOF also validates the entry's CRC in ZipArchive.
            let count = entry.read(&mut buffer).map_err(|e| e.to_string())?;
            if count == 0 {
                break;
            }
            output
                .write_all(&buffer[..count])
                .map_err(|e| e.to_string())?;
        }
        output.sync_all().map_err(|e| e.to_string())?;
        if output.metadata().map_err(|e| e.to_string())?.len() != entry.size() {
            return Err("ZIP entry size does not match the extracted file".into());
        }
    }
    drop(archive);
    if cancel.is_cancelled() {
        return Err("Download paused".into());
    }
    let folder = unused_path(&path.with_extension(""))?;
    std::fs::rename(contents, &folder).map_err(|e| e.to_string())?;
    std::fs::remove_file(path)
        .map_err(|e| format!("Files verified, but ZIP could not be removed: {e}"))?;
    Ok(folder)
}

pub fn project_progress(id: &str, state: &str, label: &str, error: Option<String>) -> Progress {
    Progress {
        project_id: id.into(),
        file_url: String::new(),
        file_name: label.into(),
        bytes_downloaded: 0,
        total_bytes: 0,
        percent: if state == "complete" { 100 } else { 0 },
        state: state.into(),
        error,
    }
}

async fn transfer(app: &tauri::AppHandle, job: &mut QueuedDownload) -> Result<()> {
    if job.cancel.is_cancelled() {
        return Err("Download paused".into());
    }
    job.project["status"] = json!("downloading");
    projects::save(&job.project)?;
    let root = projects::path_of(&job.project)?
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let dest = root.join("FOOTAGE");
    fs::create_dir_all(&dest).await.map_err(|e| e.to_string())?;
    if !dest
        .canonicalize()
        .map_err(|e| e.to_string())?
        .starts_with(&root)
    {
        return Err("FOOTAGE points outside the project".into());
    }
    let urls: Vec<String> =
        serde_json::from_value(job.project["footageUrls"].clone()).map_err(|e| e.to_string())?;
    let c = client()?;
    let files = tokio::select! {
        _ = job.cancel.cancelled() => return Err("Download paused".into()),
        result = jobs(&c, &urls) => result?,
    };
    let callback_app = app.clone();
    let progress: Arc<dyn Fn(Progress) + Send + Sync> = Arc::new(move |p| {
        let _ = callback_app.emit("download-progress", p);
    });
    let mut completed: Vec<String> =
        serde_json::from_value(job.project["downloadCompletedJobs"].clone()).unwrap_or_default();
    for file in files {
        let key = file.key();
        if completed.contains(&key) {
            continue;
        }
        one(&c, &file, &dest, &job.cancel, progress.clone(), &job.id).await?;
        completed.push(key);
        job.project["downloadCompletedJobs"] = json!(completed);
        projects::save(&job.project)?;
    }
    Ok(())
}

pub async fn run(app: tauri::AppHandle, state: Arc<Downloads>) {
    loop {
        let Some(mut job) = state.work.lock().unwrap().next() else {
            return;
        };
        let _ = app.emit(
            "download-progress",
            project_progress(&job.id, "downloading", "Preparing files…", None),
        );
        let mut result = transfer(&app, &mut job).await;
        let mut paused = result.is_err() && job.cancel.is_cancelled();
        job.project["status"] = json!(if paused { "paused" } else { "ready" });
        job.project["downloadError"] = json!(if paused { None } else { result.as_ref().err() }
            .cloned()
            .unwrap_or_default());
        job.project["downloadProgress"] = json!({});
        if result.is_ok() {
            job.project
                .as_object_mut()
                .unwrap()
                .remove("downloadCompletedJobs");
        }
        if let Err(error) = projects::save(&job.project) {
            paused = false;
            result = Err(error);
        }
        let event = match (paused, &result) {
            (true, _) => "cancelled",
            (_, Ok(())) => "complete",
            _ => "error",
        };
        let mut work = state.work.lock().unwrap();
        let _ = app.emit(
            "download-progress",
            project_progress(&job.id, event, "", if paused { None } else { result.err() }),
        );
        work.active.remove(&job.id);
        work.running = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn network_errors_never_include_api_keys() {
        let error = reqwest::Client::new()
            .get("http://127.0.0.1:0/?key=test-only-secret")
            .send()
            .await
            .unwrap_err();
        assert!(!http_error(error).contains("test-only-secret"));
    }
    #[test]
    fn zip_extraction_deletes_verified_archive_and_rejects_traversal() {
        use std::io::Write;
        for name in ["nested/take.mov", "../outside.mov"] {
            let tmp = tempfile::tempdir().unwrap();
            let path = tmp.path().join("assets.zip");
            let file = std::fs::File::create(&path).unwrap();
            let mut writer = zip::ZipWriter::new(file);
            writer
                .start_file(name, zip::write::SimpleFileOptions::default())
                .unwrap();
            writer.write_all(b"video").unwrap();
            writer.finish().unwrap();
            let result = extract_zip(&path, &CancellationToken::new());
            if name.starts_with("..") {
                assert!(path.exists());
                assert!(!tmp.path().join("assets").exists());
                assert!(result.is_err());
                assert!(!tmp.path().join("outside.mov").exists());
            } else {
                result.unwrap();
                assert!(!path.exists());
                assert_eq!(
                    std::fs::read(tmp.path().join("assets/nested/take.mov")).unwrap(),
                    b"video"
                );
            }
        }
    }
    fn sample_zip() -> Vec<u8> {
        use std::io::{Cursor, Write};
        let mut writer = zip::ZipWriter::new(Cursor::new(Vec::new()));
        let options = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Stored);
        writer.add_directory("/", options).unwrap();
        writer.add_directory("empty/", options).unwrap();
        writer.start_file("nested/take.mov", options).unwrap();
        writer.write_all(b"test video payload").unwrap();
        writer.start_file("nested/take:2.mov", options).unwrap();
        writer.write_all(b"second file").unwrap();
        writer.finish().unwrap().into_inner()
    }

    #[test]
    fn rejects_a_bad_checksum_without_publishing_or_deleting_the_zip() {
        let tmp = tempfile::tempdir().unwrap();
        let zip = tmp.path().join("assets.zip");
        let mut bytes = sample_zip();
        let offset = bytes
            .windows(b"second file".len())
            .position(|window| window == b"second file")
            .unwrap();
        bytes[offset] ^= 1;
        std::fs::write(&zip, bytes).unwrap();
        assert!(extract_zip(&zip, &CancellationToken::new())
            .unwrap_err()
            .contains("checksum"));
        assert_eq!(std::fs::read_dir(tmp.path()).unwrap().count(), 1);
        assert!(zip.exists());
    }

    #[test]
    fn preserves_the_archive_if_portable_filenames_would_merge_folders() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("conflict.zip");
        let mut archive = zip::ZipWriter::new(std::fs::File::create(&path).unwrap());
        let options = zip::write::SimpleFileOptions::default();
        archive.start_file("media:/first.mov", options).unwrap();
        archive.start_file("media?/second.mov", options).unwrap();
        archive.finish().unwrap();
        let error = extract_zip(&path, &CancellationToken::new()).unwrap_err();
        assert!(error.contains("same path"));
        assert!(path.exists());
        assert!(!tmp.path().join("conflict").exists());
    }

    #[tokio::test]
    async fn extracts_dropbox_style_zip_without_overwriting_an_existing_folder() {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let archive = sample_zip();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/file", listener.local_addr().unwrap());
        let server = tokio::spawn(async move {
            let (mut stream, _) = listener.accept().await.unwrap();
            let mut request = [0; 4096];
            stream.read(&mut request).await.unwrap();
            stream.write_all(format!("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nContent-Disposition: attachment; filename=assets\r\nConnection: close\r\n\r\n", archive.len()).as_bytes()).await.unwrap();
            stream.write_all(&archive).await.unwrap();
        });
        let tmp = tempfile::tempdir().unwrap();
        fs::create_dir(tmp.path().join("assets")).await.unwrap();
        let output = one(
            &client().unwrap(),
            &test_job(&url),
            tmp.path(),
            &CancellationToken::new(),
            Arc::new(|_| {}),
            "test",
        )
        .await
        .unwrap();
        server.await.unwrap();
        assert_eq!(output, tmp.path().join("assets (1)"));
        assert!(output.join("empty").is_dir());
        assert_eq!(
            fs::read(output.join("nested/take.mov")).await.unwrap(),
            b"test video payload"
        );
        assert_eq!(
            fs::read(output.join("nested/take_2.mov")).await.unwrap(),
            b"second file"
        );
        assert!(!tmp.path().join("assets.zip").exists());
    }

    #[test]
    fn queue_runs_one_project_and_prioritizes_the_selected_project() {
        let mut work = Work::default();
        for id in ["first", "second", "third"] {
            let cancel = CancellationToken::new();
            work.active.insert(id.into(), cancel.clone());
            work.pending.push_back(QueuedDownload {
                id: id.into(),
                project: json!({}),
                cancel,
            });
        }
        let first = work.next().unwrap();
        assert_eq!(first.id, "first");
        assert!(work.next().is_none());
        work.prioritize("third").unwrap();
        assert!(first.cancel.is_cancelled());
        work.running = None;
        assert_eq!(work.next().unwrap().id, "third");
        work.running = None;
        assert_eq!(work.next().unwrap().id, "second");
    }

    #[test]
    fn public_folder_parses_all_entries_and_preserves_nested_names() {
        let mut html=String::from("<html><head><title>public folder</title></head><body><div id='flip-contents'><div class='flip-entries'>");
        for i in 0..57 {
            html.push_str(&format!("<div class='flip-entry'><a href='https://drive.google.com/file/d/file_{i}/view'><div class='flip-entry-title'>take &amp; {i}.jpg</div></a></div>"));
        }
        html.push_str("<div class='flip-entry'><a href='https://drive.google.com/drive/folders/child'><div class='flip-entry-title'>вложенная папка</div></a></div></div></div></body></html>");
        let entries = public_folder_entries(&html).unwrap();
        assert_eq!(entries.len(), 58);
        assert_eq!(entries[0].name, "take & 0.jpg");
        assert!(entries[57].folder);
        assert_eq!(entries[57].name, "вложенная папка");
    }
    #[test]
    fn public_folder_rejects_login_and_unsafe_names() {
        assert!(public_folder_entries("<html><title>Sign in</title></html>").is_err());
        assert!(public_folder_entries("<div id='flip-contents'><div class='flip-entry'><a href='https://drive.google.com/file/d/abc/view'><div class='flip-entry-title'>../outside.jpg</div></a></div></div>").is_err());
    }
    #[tokio::test]
    #[ignore = "requires EDITHUB_LIVE_DRIVE_URL and network access"]
    async fn live_public_folder_download_sample() {
        let source = std::env::var("EDITHUB_LIVE_DRIVE_URL").expect("set EDITHUB_LIVE_DRIVE_URL");
        let c = client().unwrap();
        let jobs = tokio::time::timeout(Duration::from_secs(180), jobs(&c, &[source]))
            .await
            .unwrap()
            .unwrap();
        assert!(!jobs.is_empty());
        let prefixes: std::collections::BTreeSet<_> = jobs
            .iter()
            .filter_map(|j| j.relative.components().next())
            .map(|p| p.as_os_str().to_string_lossy().to_string())
            .collect();
        println!(
            "public files: {}; top-level folders: {:?}",
            jobs.len(),
            prefixes
        );
        let job = jobs
            .iter()
            .find(|j| {
                j.name
                    .as_ref()
                    .is_some_and(|n| n.to_lowercase().ends_with("-1.jpg"))
            })
            .or_else(|| {
                jobs.iter().find(|j| {
                    j.name
                        .as_ref()
                        .is_some_and(|n| n.to_lowercase().ends_with(".jpg"))
                })
            })
            .expect("no JPEG sample in this folder");
        let dest = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join(".qa/live-drive");
        let path = tokio::time::timeout(
            Duration::from_secs(180),
            one(
                &c,
                job,
                &dest,
                &CancellationToken::new(),
                Arc::new(|_| {}),
                "live-drive-test",
            ),
        )
        .await
        .unwrap()
        .unwrap();
        let data = fs::read(&path).await.unwrap();
        assert!(data.len() > 1024);
        assert!(
            data.starts_with(&[0xff, 0xd8, 0xff]),
            "download is not a JPEG"
        );
        println!(
            "downloaded JPEG: {} bytes; saved in {}",
            data.len(),
            path.display()
        );
        if let Some(video) = jobs.iter().find(|j| {
            j.name.as_ref().is_some_and(|n| {
                n.to_lowercase().ends_with(".mp4") || n.to_lowercase().ends_with(".mov")
            })
        }) {
            let dest = dest.join("video-probe");
            let cancel = CancellationToken::new();
            let trigger = cancel.clone();
            let result = tokio::time::timeout(
                Duration::from_secs(90),
                one(
                    &c,
                    video,
                    &dest,
                    &cancel,
                    Arc::new(move |_| trigger.cancel()),
                    "live-video-probe",
                ),
            )
            .await
            .unwrap();
            assert!(
                result.is_ok() || cancel.is_cancelled(),
                "video failed before receiving bytes: {result:?}"
            );
            let folder = dest.join(&video.relative);
            let partial = std::fs::read_dir(&folder)
                .unwrap()
                .filter_map(|e| e.ok())
                .find(|e| e.path().extension().is_some_and(|e| e == "part"))
                .map(|e| e.path())
                .or(result.ok())
                .expect("no video bytes saved");
            let bytes = fs::read(partial).await.unwrap();
            assert!(!bytes.is_empty());
            assert!(
                bytes
                    .windows(4)
                    .take(64)
                    .any(|b| b == b"ftyp" || b == b"moov" || b == b"mdat"),
                "not an MP4/MOV header"
            );
            println!(
                "video stream verified: {} bytes received, then cancelled deliberately",
                bytes.len()
            );
        }
    }
    async fn fixture(responses: Vec<String>) -> (String, tokio::task::JoinHandle<Vec<String>>) {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/file.mov", listener.local_addr().unwrap());
        let task = tokio::spawn(async move {
            let mut requests = vec![];
            for response in responses {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut data = vec![0; 16384];
                let n = socket.read(&mut data).await.unwrap();
                requests.push(String::from_utf8_lossy(&data[..n]).to_string());
                socket.write_all(response.as_bytes()).await.unwrap();
            }
            requests
        });
        (url, task)
    }
    fn test_job(url: &str) -> Job {
        Job {
            url: Url::parse(url).unwrap(),
            source: url.into(),
            relative: PathBuf::new(),
            name: None,
            token: None,
            key: None,
        }
    }
    #[tokio::test]
    async fn downloads_real_stream_and_uses_response_filename() {
        let (url,server)=fixture(vec!["HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Disposition: attachment; filename=\"take.mov\"\r\nConnection: close\r\n\r\nvideo".into()]).await;
        let tmp = tempfile::tempdir().unwrap();
        let file = one(
            &client().unwrap(),
            &test_job(&url),
            tmp.path(),
            &CancellationToken::new(),
            Arc::new(|_| {}),
            "p",
        )
        .await
        .unwrap();
        assert_eq!(file.file_name().unwrap(), "take.mov");
        assert_eq!(fs::read(file).await.unwrap(), b"video");
        assert_eq!(server.await.unwrap().len(), 1);
    }
    #[tokio::test]
    async fn resumes_interrupted_stream_with_if_range() {
        let (url,server)=fixture(vec!["HTTP/1.1 200 OK\r\nContent-Length: 10\r\nETag: \"v1\"\r\nConnection: close\r\n\r\nfirst".into(),"HTTP/1.1 206 Partial Content\r\nContent-Length: 5\r\nContent-Range: bytes 5-9/10\r\nETag: \"v1\"\r\nConnection: close\r\n\r\n-last".into()]).await;
        let tmp = tempfile::tempdir().unwrap();
        let file = one(
            &client().unwrap(),
            &test_job(&url),
            tmp.path(),
            &CancellationToken::new(),
            Arc::new(|_| {}),
            "p",
        )
        .await
        .unwrap();
        assert_eq!(fs::read(file).await.unwrap(), b"first-last");
        let req = server.await.unwrap();
        assert!(req[1].to_lowercase().contains("range: bytes=5-"));
        assert!(req[1].to_lowercase().contains("if-range: \"v1\""));
    }
    #[tokio::test]
    async fn rejects_html_and_permanent_http_errors() {
        for response in ["HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\nConnection: close\r\n\r\n<html></html>","HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"] {
            let (url,server)=fixture(vec![response.into()]).await;let tmp=tempfile::tempdir().unwrap();
            assert!(one(&client().unwrap(),&test_job(&url),tmp.path(),&CancellationToken::new(),Arc::new(|_|{}),"p").await.is_err());
            assert_eq!(server.await.unwrap().len(),1);assert_eq!(std::fs::read_dir(tmp.path()).unwrap().count(),0);
        }
    }
    #[tokio::test]
    async fn cancellation_does_not_wait_for_headers() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}/file.mov", listener.local_addr().unwrap());
        let cancel = CancellationToken::new();
        let trigger = cancel.clone();
        let server = tokio::spawn(async move {
            let (_socket, _) = listener.accept().await.unwrap();
            trigger.cancel();
        });
        let tmp = tempfile::tempdir().unwrap();
        let start = Instant::now();
        assert!(one(
            &client().unwrap(),
            &test_job(&url),
            tmp.path(),
            &cancel,
            Arc::new(|_| {}),
            "p"
        )
        .await
        .is_err());
        assert!(start.elapsed() < Duration::from_secs(2));
        server.await.unwrap();
    }
    #[test]
    fn resume_requires_validator() {
        assert_eq!(resume_headers(123, None), None);
        assert_eq!(
            resume_headers(123, Some("\"version1\"")),
            Some(("bytes=123-".into(), "\"version1\"".into()))
        );
    }
    #[tokio::test]
    async fn publishes_without_hard_links_and_preserves_existing_file() {
        let tmp = tempfile::tempdir().unwrap();
        let partial = tmp.path().join("file.part");
        let target = tmp.path().join("file.mov");
        fs::write(&partial, b"new").await.unwrap();
        fs::write(&target, b"original").await.unwrap();
        assert!(publish_file(&partial, &target).await.is_err());
        assert_eq!(fs::read(&target).await.unwrap(), b"original");
        assert!(partial.exists());
        fs::remove_file(&target).await.unwrap();
        publish_file(&partial, &target).await.unwrap();
        assert_eq!(fs::read(&target).await.unwrap(), b"new");
        assert!(!partial.exists());
    }
    #[test]
    fn dropbox_keeps_folder_host_and_key() {
        let u =
            normalize("https://www.dropbox.com/scl/fo/abc/folder?rlkey=secret&dl=0&raw=1").unwrap();
        assert_eq!(u.host_str(), Some("www.dropbox.com"));
        assert!(u.query_pairs().any(|(k, v)| k == "rlkey" && v == "secret"));
        assert!(u.query_pairs().any(|(k, v)| k == "dl" && v == "1"));
        assert!(!u.query_pairs().any(|(k, _)| k == "raw"));
    }
    #[test]
    fn drive_preserves_resource_key() {
        let u = normalize("https://drive.google.com/file/d/abc/view?resourcekey=key").unwrap();
        assert_eq!(u.host_str(), Some("drive.usercontent.google.com"));
        assert!(u
            .query_pairs()
            .any(|(k, v)| k == "resourcekey" && v == "key"));
        assert!(u.query_pairs().any(|(k, v)| k == "id" && v == "abc"));
    }
    #[test]
    fn confirmation_form_keeps_uuid() {
        let u=confirmation(r#"<form id="download-form" action="https://drive.usercontent.google.com/download"><input type="hidden" name="id" value="abc"><input type="hidden" name="confirm" value="t"><input type="hidden" name="uuid" value="unique&amp;value"></form>"#).unwrap();
        assert!(u
            .query_pairs()
            .any(|(k, v)| k == "uuid" && v == "unique&value"));
    }
    #[test]
    fn confirmation_rejects_untrusted_action() {
        assert!(confirmation(r#"<form id="download-form" action="https://evil.example/download"><input name="id" value="a"></form>"#).is_err());
    }
    #[test]
    fn disallow_non_http_links() {
        assert!(normalize("file:///C:/secret").is_err());
    }
    #[test]
    fn filenames_cannot_escape_destination() {
        assert!(safe_name("../../outside.mov").is_err());
        assert!(safe_name("CON").is_err());
        assert_eq!(safe_name("take:01.mov").unwrap(), "take_01.mov");
    }
}
