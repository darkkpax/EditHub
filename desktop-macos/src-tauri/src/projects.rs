use chrono::{Datelike, Local, Utc};
use serde_json::{json, Value};
use sha1::{Digest, Sha1};
use std::{
    fs,
    path::{Path, PathBuf},
};
use walkdir::WalkDir;

pub type Result<T> = std::result::Result<T, String>;
pub const FOLDERS: &[&str] = &[
    "FOOTAGE",
    "SFX",
    "MUSIC",
    "READY VIDEOS",
    "MISC",
    "VOICE/ENCHANCE",
    "VOICE/NOT ENCHANCE",
    "DOCS",
    "GRAPHICS",
    "B-ROLL",
    "SUBS",
];
const MONTHS: &[&str] = &[
    "JANUARY",
    "FEBRUARY",
    "MARCH",
    "APRIL",
    "MAY",
    "JUNE",
    "JULY",
    "AUGUST",
    "SEPTEMBER",
    "OCTOBER",
    "NOVEMBER",
    "DECEMBER",
];
pub fn config_dir() -> PathBuf {
    // Debug builds can use isolated fixtures without touching the user's settings.
    if cfg!(debug_assertions) {
        if let Some(path) = std::env::var_os("EDITHUB_CONFIG_DIR") {
            return PathBuf::from(path);
        }
    }
    #[cfg(target_os = "macos")]
    {
        return dirs::home_dir()
            .expect("home directory")
            .join("Library/Application Support/EditHub");
    }
    #[allow(unreachable_code)]
    dirs::home_dir().expect("home directory").join(".edithub")
}

#[cfg(target_os = "macos")]
fn default_icloud_drive(home: &Path) -> PathBuf {
    home.join("Library/Mobile Documents/com~apple~CloudDocs")
}
pub fn read_json(path: &Path) -> Result<Value> {
    serde_json::from_slice(&fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?)
        .map_err(|e| e.to_string())
}
pub fn write_json(path: &Path, value: &Value) -> Result<()> {
    fs::create_dir_all(path.parent().ok_or("Parent folder missing")?).map_err(|e| e.to_string())?;
    let temp = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
    fs::write(
        &temp,
        serde_json::to_vec_pretty(value).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    fs::rename(temp, path).map_err(|e| e.to_string())
}
pub fn settings() -> Result<Value> {
    let home = dirs::home_dir().ok_or("Home directory missing")?;
    #[cfg(target_os = "macos")]
    let mut s = json!({"projectsFolder":home.join("EditHub/Projects"),"downloadsFolder":home.join("Downloads"),"icloudPath":default_icloud_drive(&home),"davinciPath":"/Applications/DaVinci Resolve/DaVinci Resolve.app","autoArchiveDays":30,"autoImportPatterns":["*-enhanced*","*-enhanced-v2*"],"theme":"light"});
    #[cfg(not(target_os = "macos"))]
    let mut s = json!({"projectsFolder":home.join("EditHub/Projects"),"downloadsFolder":home.join("Downloads"),"icloudPath":home.join("iCloudDrive"),"davinciPath":r"C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe","autoArchiveDays":30,"autoImportPatterns":["*-enhanced*","*-enhanced-v2*"],"theme":"dark"});
    let path = config_dir().join("settings.json");
    if path.exists() {
        let existing = read_json(&path)?;
        s.as_object_mut()
            .unwrap()
            .extend(existing.as_object().ok_or("Invalid settings.json")?.clone());
    }
    #[cfg(windows)]
    if !Path::new(s["icloudPath"].as_str().unwrap_or("")).is_dir() {
        if let Ok(output) = crate::hidden_command("reg.exe")
            .args([
                "query",
                r"HKCU\Software\Apple Inc.\Internet Services",
                "/v",
                "ICDrive",
            ])
            .output()
        {
            let text = String::from_utf8_lossy(&output.stdout);
            if let Some(found) = text
                .lines()
                .find_map(|line| line.split_once("REG_SZ").map(|(_, value)| value.trim()))
            {
                if Path::new(found).is_dir() {
                    s["icloudPath"] = json!(found);
                }
            }
        }
    }
    Ok(s)
}
pub fn setting_path(s: &Value, key: &str) -> Result<PathBuf> {
    let raw = s[key]
        .as_str()
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| format!("Set {key} in Settings"))?;
    let path = PathBuf::from(raw);
    if !path.is_absolute() {
        return Err("Path must be absolute".into());
    }
    Ok(path)
}
pub fn roots(s: &Value) -> Result<Vec<PathBuf>> {
    let mut roots = vec![setting_path(s, "projectsFolder")?];
    if let Ok(cloud) = setting_path(s, "icloudPath") {
        roots.push(cloud.join("edithub/Videos"));
        roots.push(cloud.join("Videos"));
        roots.push(cloud.join("Edit Hub/Videos"));
    }
    Ok(roots)
}
fn project_at(path: &Path, year: Option<&str>, month: Option<&str>) -> Result<Value> {
    let name = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let manifest = path.join(".edithub.json");
    let mut info = if manifest.exists() {
        read_json(&manifest)?
    } else {
        let meta = read_json(&path.join(".edithub-metadata.json")).unwrap_or(json!({}));
        let mac = read_json(&path.join(format!("{name}.edithub"))).unwrap_or(json!({}));
        let id = format!(
            "{:x}",
            Sha1::digest(path.to_string_lossy().to_lowercase().as_bytes())
        )[..32]
            .to_string();
        json!({"id":meta["projectId"].as_str().or(mac["projectId"].as_str()).unwrap_or(&id),"name":name,"createdAt":"","lastOpenedAt":"","status":if mac.is_object() && mac["projectId"].is_string(){"archive"}else{"ready"},"footageUrls":meta.get("footageLinks").or(mac.get("footageLinks")).cloned().unwrap_or(json!([])),"editor":"davinci"})
    };
    if !info.is_object() {
        return Err("Invalid manifest".into());
    }
    if info["editor"].is_null() {
        info["editor"] = json!("davinci");
    }
    info["folderPath"] = json!(path);
    if info["year"].is_null() {
        info["year"] = json!(year);
    }
    if info["month"].is_null() {
        info["month"] = json!(month);
    }
    // Imported projects did not have an EditHub manifest. The filesystem's
    // creation date is the only reliable creation date for those folders and
    // also prevents first-run adoption from making every project look new.
    if let Ok(metadata) = fs::metadata(path) {
        if let Ok(created) = metadata.created().or_else(|_| metadata.modified()) {
            info["createdAt"] = json!(chrono::DateTime::<Utc>::from(created).to_rfc3339());
        }
    }
    Ok(info)
}
fn scan(root: &Path) -> Result<Vec<Value>> {
    if !root.exists() {
        return Ok(vec![]);
    }
    let mut result = vec![];
    let mut iter = WalkDir::new(root)
        .min_depth(1)
        .max_depth(4)
        .follow_links(false)
        .into_iter();
    while let Some(entry) = iter.next() {
        let e = entry.map_err(|e| e.to_string())?;
        if !e.file_type().is_dir() {
            continue;
        }
        let name = e.file_name().to_string_lossy();
        if name.starts_with('.') || name.starts_with("__extracting_") {
            iter.skip_current_dir();
            continue;
        }
        let relative = e.path().strip_prefix(root).unwrap();
        let parts: Vec<_> = relative.iter().filter_map(|v| v.to_str()).collect();
        let in_month = parts.len() == 3
            && parts[0].len() == 4
            && parts[0].parse::<u32>().is_ok()
            && (MONTHS.contains(&parts[1].to_uppercase().as_str())
                || parts[1].parse::<u32>().is_ok_and(|m| (1..=12).contains(&m)));
        if e.path().join(".edithub.json").exists()
            || e.path().join(".edithub-metadata.json").exists()
            || e.path().join(format!("{name}.edithub")).exists()
            || in_month
        {
            result.push(project_at(
                e.path(),
                parts.first().copied(),
                parts.get(1).copied(),
            )?);
            iter.skip_current_dir();
        }
    }
    Ok(result)
}
pub fn list() -> Result<Vec<Value>> {
    let s = settings()?;
    let roots = roots(&s)?;
    let mut found = vec![];
    let mut ids = std::collections::HashSet::new();
    for (i, root) in roots.iter().enumerate() {
        for mut p in scan(root)? {
            if ids.insert(p["id"].as_str().unwrap_or("").to_string()) {
                if i > 0 {
                    p["status"] = json!("archive");
                }
                found.push(p);
            }
        }
    }
    found.sort_by(|a, b| b["lastOpenedAt"].as_str().cmp(&a["lastOpenedAt"].as_str()));
    Ok(found)
}

pub fn adopt_library(root: &Path) -> Result<usize> {
    let mut adopted = 0;
    for mut project in scan(root)? {
        let folder = PathBuf::from(
            project["folderPath"]
                .as_str()
                .ok_or("Project folder path missing")?,
        );
        let manifest = folder.join(".edithub.json");
        if manifest.exists() {
            continue;
        }
        project["status"] = json!("ready");
        if !project["createdAt"].as_str().is_some_and(|value| !value.is_empty()) {
            project["createdAt"] = json!(Utc::now().to_rfc3339());
        }
        if !project["lastOpenedAt"].as_str().is_some_and(|value| !value.is_empty()) {
            project["lastOpenedAt"] = project["createdAt"].clone();
        }
        project.as_object_mut().unwrap().remove("folderPath");
        write_json(&manifest, &project)?;
        adopted += 1;
    }
    Ok(adopted)
}
pub fn find(id: &str) -> Result<Value> {
    list()?
        .into_iter()
        .find(|p| p["id"].as_str() == Some(id))
        .ok_or("Project not found".into())
}
pub fn path_of(p: &Value) -> Result<PathBuf> {
    Ok(PathBuf::from(
        p["folderPath"].as_str().ok_or("Project path missing")?,
    ))
}
pub fn save(p: &Value) -> Result<()> {
    let path = path_of(p)?;
    let mut value = p.clone();
    value.as_object_mut().unwrap().remove("folderPath");
    value.as_object_mut().unwrap().remove("sizeBytes");
    write_json(&path.join(".edithub.json"), &value)
}
pub fn create(name: &str, editor: &str, urls: Vec<String>) -> Result<Value> {
    let name = super::downloads::safe_name(name.trim())?;
    if editor != "davinci" {
        return Err("Unsupported editor".into());
    }
    for url in &urls {
        super::downloads::normalize(url)?;
    }
    let date = Local::now();
    let month = MONTHS[date.month0() as usize];
    let year = date.year().to_string();
    let root = setting_path(&settings()?, "projectsFolder")?;
    let path = root.join(&year).join(month).join(&name);
    fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
    fs::create_dir(&path)
        .map_err(|e| format!("Could not create project (it may already exist): {e}"))?;
    for folder in FOLDERS {
        fs::create_dir_all(path.join(folder)).map_err(|e| e.to_string())?;
    }
    let now = Utc::now().to_rfc3339();
    let p = json!({"id":uuid::Uuid::new_v4().to_string(),"name":name,"year":year,"month":month,"createdAt":now,"lastOpenedAt":now,"footageUrls":urls,"status":"ready","downloadProgress":{},"downloadError":"","editor":editor,"folderPath":path});
    save(&p)?;
    Ok(p)
}
pub fn entries(path: &Path) -> Result<Vec<Value>> {
    let mut result = vec![];
    for entry in fs::read_dir(path).map_err(|e| e.to_string())? {
        let e = entry.map_err(|e| e.to_string())?;
        let kind = e.file_type().map_err(|e| e.to_string())?;
        if kind.is_symlink() || e.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        result.push(json!({"name":e.file_name().to_string_lossy(),"path":e.path(),"isFolder":kind.is_dir(),"sizeBytes":if kind.is_dir(){0}else{e.metadata().map_err(|e|e.to_string())?.len()}}));
    }
    result.sort_by(|a, b| {
        b["isFolder"]
            .as_bool()
            .cmp(&a["isFolder"].as_bool())
            .then(a["name"].as_str().cmp(&b["name"].as_str()))
    });
    Ok(result)
}
fn unused_destination(parent: &Path, source: &Path) -> Result<PathBuf> {
    let name = source
        .file_name()
        .filter(|name| !name.is_empty())
        .ok_or("Dropped item has no filename")?;
    let direct = parent.join(name);
    if !direct.exists() {
        return Ok(direct);
    }
    let stem = source.file_stem().unwrap_or(name).to_string_lossy();
    let extension = source
        .extension()
        .filter(|extension| !extension.is_empty())
        .map(|extension| format!(".{}", extension.to_string_lossy()))
        .unwrap_or_default();
    for number in 2..10_000 {
        let candidate = parent.join(format!("{stem} {number}{extension}"));
        if !candidate.exists() {
            return Ok(candidate);
        }
    }
    Err("Too many files with the same name in this folder".into())
}
fn copy_into(parent: &Path, source: &Path) -> Result<()> {
    let source_metadata = fs::symlink_metadata(source).map_err(|e| e.to_string())?;
    if source_metadata.file_type().is_symlink() {
        return Err("Symbolic links cannot be imported".into());
    }
    let source = source.canonicalize().map_err(|e| e.to_string())?;
    let target = unused_destination(parent, &source)?;
    if source_metadata.is_dir() {
        copy_tree(&source, &target)
    } else if source_metadata.is_file() {
        fs::copy(&source, &target).map(|_| ()).map_err(|e| e.to_string())
    } else {
        Err("Only files and folders can be imported".into())
    }
}
pub fn import_paths(id: &str, relative: &str, paths: &[String]) -> Result<usize> {
    if paths.is_empty() {
        return Err("Drop at least one file".into());
    }
    let project = find(id)?;
    if project["status"] == "archive" {
        return Err("Restore the project before importing files".into());
    }
    let root = path_of(&project)?.canonicalize().map_err(|e| e.to_string())?;
    let destination = validated_subpath(id, relative)?;
    if !destination.is_dir() {
        return Err("Open a project folder before dropping files".into());
    }
    let mut imported = 0;
    for raw in paths {
        let source = PathBuf::from(raw);
        let canonical = source.canonicalize().map_err(|e| e.to_string())?;
        if canonical.starts_with(&root) {
            return Err("This item is already inside the project".into());
        }
        copy_into(&destination, &source)?;
        imported += 1;
    }
    Ok(imported)
}
pub fn known_subpath(
    id: &str,
    project: &Path,
    relative: &str,
    allowed: &[PathBuf],
) -> Result<PathBuf> {
    let root = project.canonicalize().map_err(|e| e.to_string())?;
    if !allowed.iter().any(|p| {
        p.canonicalize()
            .is_ok_and(|p| root != p && root.starts_with(p))
    }) {
        return Err("Project is outside configured root folders".into());
    }
    if project_at(project, None, None)?["id"].as_str() != Some(id) {
        return Err("Project identity changed. Refresh projects".into());
    }
    let path = root
        .join(relative)
        .canonicalize()
        .map_err(|e| e.to_string())?;
    if !path.starts_with(&root) {
        return Err("Path outside project".into());
    }
    Ok(path)
}
pub fn validated_subpath(id: &str, relative: &str) -> Result<PathBuf> {
    let root = path_of(&find(id)?)?
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let path = root
        .join(relative)
        .canonicalize()
        .map_err(|e| e.to_string())?;
    if !path.starts_with(root) {
        return Err("Path outside project".into());
    }
    Ok(path)
}
fn copy_tree(from: &Path, to: &Path) -> Result<()> {
    fs::create_dir(to).map_err(|e| e.to_string())?;
    for entry in WalkDir::new(from).min_depth(1).follow_links(false) {
        let e = entry.map_err(|e| e.to_string())?;
        let target = to.join(e.path().strip_prefix(from).unwrap());
        if e.file_type().is_symlink() {
            return Err("Project contains symlinks. Copy stopped; original preserved".into());
        }
        if e.file_type().is_dir() {
            fs::create_dir(&target).map_err(|e| e.to_string())?;
        } else {
            fs::copy(e.path(), &target).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}
pub fn transfer(id: &str, restore: bool) -> Result<()> {
    let mut p = find(id)?;
    let src = path_of(&p)?.canonicalize().map_err(|e| e.to_string())?;
    let s = settings()?;
    let root = if restore {
        setting_path(&s, "projectsFolder")?
    } else {
        setting_path(&s, "icloudPath")?.join("edithub/Videos")
    };
    let year = super::downloads::safe_name(p["year"].as_str().unwrap_or("Unknown"))?;
    let month = super::downloads::safe_name(p["month"].as_str().unwrap_or("Unknown"))?;
    let parent = root.join(year).join(month);
    fs::create_dir_all(&parent).map_err(|e| e.to_string())?;
    let parent = parent.canonicalize().map_err(|e| e.to_string())?;
    if parent.starts_with(&src) {
        return Err("Archive must be outside the project".into());
    }
    let dest = parent.join(src.file_name().unwrap());
    if dest.exists() {
        return Err("Project already exists in destination".into());
    }
    // Publish only a complete copy; an interrupted transfer cannot look like a project.
    let staging = parent.join(format!(".edithub-transfer-{}", uuid::Uuid::new_v4()));
    let copied = (|| {
        copy_tree(&src, &staging)?;
        p["folderPath"] = json!(staging);
        p["status"] = json!(if restore { "ready" } else { "archive" });
        save(&p)?;
        fs::rename(&staging, &dest).map_err(|e| e.to_string())
    })();
    if let Err(error) = copied {
        // staging is a new UUID directory we own; copy_tree never follows links.
        if staging.exists() {
            let _ = fs::remove_dir_all(&staging);
        }
        return Err(format!("Transfer stopped; original preserved: {error}"));
    }
    fs::remove_dir_all(&src)
        .map_err(|e| format!("Copy created; could not remove original folder: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn direct_folder_lookup_validates_identity_and_containment() {
        let tmp = tempfile::tempdir().unwrap();
        let project = tmp.path().join("2026/OCTOBER/Test");
        fs::create_dir_all(project.join("FOOTAGE")).unwrap();
        write_json(&project.join(".edithub.json"), &json!({"id":"test"})).unwrap();
        let roots = vec![tmp.path().to_path_buf()];
        assert!(known_subpath("test", &project, "FOOTAGE", &roots).is_ok());
        assert!(known_subpath("wrong", &project, "FOOTAGE", &roots).is_err());
        assert!(known_subpath("test", &project, "../../..", &roots).is_err());
        assert!(known_subpath("test", &project, "FOOTAGE", &[project.join("FOOTAGE")]).is_err());
    }
    #[test]
    fn missing_legacy_editor_defaults_to_resolve_without_rewriting() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("2026/OCTOBER/Legacy");
        fs::create_dir_all(&dir).unwrap();
        for manifest in [
            json!({"id":"old","name":"Legacy"}),
            json!({"id":"old","name":"Legacy","editor":null}),
        ] {
            write_json(&dir.join(".edithub.json"), &manifest).unwrap();
            assert_eq!(scan(tmp.path()).unwrap()[0]["editor"], "davinci");
            assert_eq!(read_json(&dir.join(".edithub.json")).unwrap(), manifest);
        }
    }
    #[test]
    fn rejects_removed_editor() {
        assert!(create("Test", "premiere", vec![]).is_err());
    }
    #[test]
    fn reads_flutter_manifest_without_writing_it() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("2026/OCTOBER/Клип");
        fs::create_dir_all(dir.join("FOOTAGE")).unwrap();
        let manifest = json!({"id":"flutter-id","name":"Клип","createdAt":"2026-10-18T12:00:00Z","lastOpenedAt":"2026-10-18T12:00:00Z","editor":"premiere","status":"paused","footageUrls":["https://example.com/file.mov"],"unknownFutureField":42});
        write_json(&dir.join(".edithub.json"), &manifest).unwrap();
        let result = scan(tmp.path()).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"], "flutter-id");
        assert_eq!(result[0]["editor"], "premiere");
        assert_eq!(result[0]["year"], "2026");
        assert_eq!(read_json(&dir.join(".edithub.json")).unwrap(), manifest);
    }
    #[test]
    fn reads_mac_metadata_and_plain_month_folders() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("2026/10/MacProject");
        fs::create_dir_all(&dir).unwrap();
        write_json(
            &dir.join(".edithub-metadata.json"),
            &json!({"projectId":"mac-id","footageLinks":["https://example.com/file.mov"]}),
        )
        .unwrap();
        let result = scan(tmp.path()).unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0]["id"], "mac-id");
        assert_eq!(result[0]["footageUrls"][0], "https://example.com/file.mov");
    }
    #[test]
    fn adopts_plain_month_projects_once() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("2026/OCTOBER/Imported project");
        fs::create_dir_all(&dir).unwrap();
        assert_eq!(adopt_library(tmp.path()).unwrap(), 1);
        assert!(dir.join(".edithub.json").is_file());
        assert_eq!(adopt_library(tmp.path()).unwrap(), 0);
    }
    #[test]
    fn copies_dropped_files_without_overwriting() {
        let tmp = tempfile::tempdir().unwrap();
        let source = tmp.path().join("source/clip.mov");
        let destination = tmp.path().join("destination");
        fs::create_dir_all(source.parent().unwrap()).unwrap();
        fs::create_dir_all(&destination).unwrap();
        fs::write(&source, b"first").unwrap();
        copy_into(&destination, &source).unwrap();
        fs::write(&source, b"second").unwrap();
        copy_into(&destination, &source).unwrap();
        assert_eq!(fs::read(destination.join("clip.mov")).unwrap(), b"first");
        assert_eq!(fs::read(destination.join("clip 2.mov")).unwrap(), b"second");
    }
}
