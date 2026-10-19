use crate::projects::{self, Result};
use futures_util::StreamExt;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha1::{Digest, Sha1};
use std::{
    collections::HashMap,
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
    let name = name.trim().trim_end_matches('.');
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
    pub active: Mutex<HashMap<String, CancellationToken>>,
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
    let hash = format!(
        "{:x}",
        Sha1::digest(format!("{}{:?}{:?}", job.source, job.relative, job.name).as_bytes())
    );
    let partial = dest.join(format!(".edithub-{hash}.part"));
    let metadata = partial.with_extension("validator");
    let mut last = String::new();
    for attempt in 0..4 {
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
            if response.status() == reqwest::StatusCode::PARTIAL_CONTENT {
                let start = response
                    .headers()
                    .get("content-range")
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| v.strip_prefix("bytes "))
                    .and_then(|v| v.split('-').next())
                    .and_then(|v| v.parse::<u64>().ok());
                if start != Some(if append { existing } else { 0 }) {
                    return Err("Server returned an invalid file range".into());
                }
            }
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
            let total = response.content_length().map(|n| n + count).unwrap_or(0);
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
                let mut target = dest.join(&name);
                let mut suffix = 1;
                while target.exists() {
                    let stem = Path::new(&name)
                        .file_stem()
                        .unwrap_or_default()
                        .to_string_lossy();
                    let ext = Path::new(&name)
                        .extension()
                        .map(|e| format!(".{}", e.to_string_lossy()))
                        .unwrap_or_default();
                    target = dest.join(format!("{stem} ({suffix}){ext}"));
                    suffix += 1;
                }
                publish_file(&partial, &target).await?;
                let _ = fs::remove_file(&metadata).await;
                if target
                    .extension()
                    .is_some_and(|v| v.eq_ignore_ascii_case("zip"))
                {
                    let zip = target.clone();
                    tokio::task::spawn_blocking(move || extract_zip(&zip))
                        .await
                        .map_err(|e| e.to_string())??;
                }
                return Ok(target);
            }
            if !failed {
                last = "Incomplete download".into();
            }
        }
        if attempt < 3 {
            tokio::select! {_=cancel.cancelled()=>return Err("Download cancelled".into()),_=tokio::time::sleep(Duration::from_secs(2*(attempt+1)))=>{}}
        }
    }
    Err(format!("Download failed after 4 attempts: {last}"))
}
fn extract_zip(path: &Path) -> Result<()> {
    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    let folder = path.with_extension("");
    if folder.exists() {
        return Err("ZIP saved; extraction folder already exists".into());
    }
    // Validate every entry before extracting anything. Keep the ZIP as a recovery copy.
    for i in 0..archive.len() {
        let entry = archive.by_index(i).map_err(|e| e.to_string())?;
        let name = entry
            .enclosed_name()
            .ok_or("ZIP contains a path outside the destination")?;
        if entry.unix_mode().is_some_and(|m| m & 0o170000 == 0o120000) {
            return Err("ZIP contains symlinks".into());
        }
        for part in name.components() {
            if let std::path::Component::Normal(v) = part {
                if safe_name(&v.to_string_lossy())? != v.to_string_lossy() {
                    return Err("ZIP contains an invalid filename".into());
                }
            }
        }
    }
    archive
        .extract(folder)
        .map_err(|e| format!("ZIP saved; extraction failed: {e}"))
}
pub async fn run(
    app: tauri::AppHandle,
    state: Arc<Downloads>,
    id: String,
    urls: Vec<String>,
    cancel: CancellationToken,
) {
    let result=async {
        let mut project=projects::find(&id)?;
        if project["status"]=="archive"{return Err("Restore the archived project first".into());}
        let root=projects::path_of(&project)?.canonicalize().map_err(|e|e.to_string())?;
        let dest=root.join("FOOTAGE");
        fs::create_dir_all(&dest).await.map_err(|e|e.to_string())?;
        if !dest.canonicalize().map_err(|e|e.to_string())?.starts_with(&root){return Err("FOOTAGE points outside the project".into());}
        project["footageUrls"]=json!(urls);project["status"]=json!("downloading");project["downloadError"]=json!("");projects::save(&project)?;
        let c=client()?;
        let work=tokio::select!{_=cancel.cancelled()=>return Err("Download cancelled".into()),j=jobs(&c,&urls)=>j?};
        let callback_app=app.clone();let on_progress:Arc<dyn Fn(Progress)+Send+Sync>=Arc::new(move|p|{let _=callback_app.emit("download-progress",p);});
        // Sequential transfers avoid saturating the disk and keep cancellation deterministic.
        for job in work {one(&c,&job,&dest,&cancel,on_progress.clone(),&id).await?;}
        Ok::<_,String>(())
    }.await;
    if let Ok(mut p) = projects::find(&id) {
        p["status"] = json!(if cancel.is_cancelled() {
            "paused"
        } else {
            "ready"
        });
        p["downloadError"] = json!(result.as_ref().err().cloned().unwrap_or_default());
        p["downloadProgress"] = json!({});
        let _ = projects::save(&p);
    }
    state.active.lock().unwrap().remove(&id);
    let _ = app.emit(
        "download-progress",
        Progress {
            project_id: id.clone(),
            file_url: String::new(),
            file_name: String::new(),
            bytes_downloaded: 0,
            total_bytes: 0,
            percent: if result.is_ok() { 100 } else { 0 },
            state: if cancel.is_cancelled() {
                "cancelled"
            } else if result.is_ok() {
                "complete"
            } else {
                "error"
            }
            .into(),
            error: result.err(),
        },
    );
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
    fn zip_extraction_keeps_recovery_archive_and_rejects_traversal() {
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
            let result = extract_zip(&path);
            assert!(path.exists());
            if name.starts_with("..") {
                assert!(result.is_err());
                assert!(!tmp.path().join("outside.mov").exists());
            } else {
                result.unwrap();
                assert_eq!(
                    std::fs::read(tmp.path().join("assets/nested/take.mov")).unwrap(),
                    b"video"
                );
            }
        }
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
