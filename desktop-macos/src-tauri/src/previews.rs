use super::projects::Result;
use std::path::{Path, PathBuf};

use base64::{engine::general_purpose::STANDARD, Engine};
use sha2::{Digest, Sha256};
use std::{
    sync::OnceLock,
    time::{Duration, UNIX_EPOCH},
};
use tokio::sync::Semaphore;

fn is_video(path: &Path) -> bool {
    path.extension().and_then(|v| v.to_str()).is_some_and(|v| {
        ["mp4", "mov", "mkv", "avi", "webm", "mxf", "m4v", "mts"]
            .contains(&v.to_ascii_lowercase().as_str())
    })
}
fn candidates(root: &Path) -> Vec<PathBuf> {
    // Bound background work for very large footage trees; only a few sources are needed for a cover.
    let mut files: Vec<_> = walkdir::WalkDir::new(root)
        .max_depth(10)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| e.depth() == 0 || !e.file_name().to_string_lossy().starts_with('.'))
        .take(4096)
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .map(|e| e.into_path())
        .filter(|p| {
            is_video(p)
                || p.extension().and_then(|v| v.to_str()).is_some_and(|v| {
                    ["jpg", "jpeg", "png", "webp"].contains(&v.to_ascii_lowercase().as_str())
                })
        })
        .collect();
    files.sort_by_key(|p| (!is_video(p), p.clone()));
    files.truncate(4);
    files
}
fn cache_key(path: &Path) -> Result<String> {
    let meta = path.metadata().map_err(|e| e.to_string())?;
    let modified = meta
        .modified()
        .ok()
        .and_then(|v| v.duration_since(UNIX_EPOCH).ok())
        .map(|v| v.as_nanos())
        .unwrap_or(0);
    Ok(format!(
        "{:x}",
        Sha256::digest(format!(
            "cover-v1:{}:{}:{modified}",
            path.display(),
            meta.len()
        ))
    ))
}
async fn frame(source: &Path, seek: &str) -> Option<Vec<u8>> {
    let mut command = super::hidden_command("ffmpeg");
    command
        .args([
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-protocol_whitelist",
            "file,pipe",
            "-ss",
            seek,
            "-i",
        ])
        .arg(source)
        .args([
            "-frames:v",
            "1",
            "-vf",
            "scale=480:270:force_original_aspect_ratio=increase,crop=480:270",
            "-threads",
            "1",
            "-filter_threads",
            "1",
            "-f",
            "image2pipe",
            "-vcodec",
            "mjpeg",
            "pipe:1",
        ]);
    let mut command = tokio::process::Command::from(command);
    command.kill_on_drop(true);
    let out = tokio::time::timeout(Duration::from_secs(8), command.output())
        .await
        .ok()?
        .ok()?;
    (out.status.success() && out.stdout.starts_with(&[0xff, 0xd8]) && out.stdout.len() < 1_000_000)
        .then_some(out.stdout)
}
async fn quicklook_frame(source: &Path) -> Option<Vec<u8>> {
    // macOS ships Quick Look even when ffmpeg is not installed. It covers MOV,
    // MP4 and common camera formats, so covers work on a clean Mac.
    #[cfg(target_os = "macos")]
    {
        let output = std::env::temp_dir().join(format!("edithub-preview-{}", uuid::Uuid::new_v4()));
        tokio::fs::create_dir_all(&output).await.ok()?;
        let result = tokio::process::Command::new("/usr/bin/qlmanage")
            .args(["-t", "-s", "480", "-o"])
            .arg(&output)
            .arg(source)
            .output()
            .await
            .ok();
        let image = if result.is_some_and(|result| result.status.success()) {
            let mut files = tokio::fs::read_dir(&output).await.ok()?;
            let mut bytes = None;
            while let Ok(Some(entry)) = files.next_entry().await {
                if entry.path().extension().is_some_and(|ext| ext.eq_ignore_ascii_case("png")) {
                    bytes = tokio::fs::read(entry.path()).await.ok();
                    break;
                }
            }
            bytes
        } else { None };
        let _ = tokio::fs::remove_dir_all(&output).await;
        image
    }
    #[cfg(not(target_os = "macos"))]
    { let _ = source; None }
}
#[tauri::command]
pub async fn project_preview(id: String, folder_path: String) -> Result<Option<String>> {
    static WORKERS: OnceLock<Semaphore> = OnceLock::new();
    let _permit = WORKERS
        .get_or_init(|| Semaphore::new(2))
        .acquire()
        .await
        .map_err(|e| e.to_string())?;
    let files = tokio::task::spawn_blocking(move || {
        let root = super::projects::known_subpath(
            &id,
            Path::new(&folder_path),
            "",
            &super::projects::roots(&super::projects::settings()?)?,
        )?;
        let footage = root.join("FOOTAGE");
        // Do not follow a replaced footage folder outside the selected project.
        let footage = match footage.canonicalize() {
            Ok(p) if p.starts_with(&root) => p,
            _ => return Ok(Vec::new()),
        };
        Ok::<_, String>(candidates(&footage))
    })
    .await
    .map_err(|e| e.to_string())??;
    for source in files {
        let key = cache_key(&source)?;
        let cache = super::projects::config_dir()
            .join("previews")
            .join(format!("{key}.jpg"));
        if let Ok(bytes) = tokio::fs::read(&cache).await {
            if bytes.starts_with(&[0xff, 0xd8]) {
                return Ok(Some(format!(
                    "data:image/jpeg;base64,{}",
                    STANDARD.encode(bytes)
                )));
            }
        }
        let bytes = match frame(&source, "1").await {
            Some(v) => Some(v),
            None => match frame(&source, "0").await {
                Some(v) => Some(v),
                None => quicklook_frame(&source).await,
            },
        };
        if let Some(bytes) = bytes {
            let _ = tokio::fs::create_dir_all(cache.parent().unwrap()).await;
            let _ = tokio::fs::write(&cache, &bytes).await;
            return Ok(Some(format!(
                "data:image/jpeg;base64,{}",
                STANDARD.encode(bytes)
            )));
        }
    }
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ignores_partial_audio_and_hidden_files() {
        let temp = tempfile::tempdir().unwrap();
        for name in [
            "take.mp4",
            "still.jpg",
            "unfinished.mp4.part",
            "voice.wav",
            ".hidden.mov",
        ] {
            std::fs::write(temp.path().join(name), b"fixture").unwrap();
        }
        let files = candidates(temp.path());
        assert_eq!(files.len(), 2);
        assert!(files[0].ends_with("take.mp4"));
    }
    #[test]
    fn cache_key_changes_when_source_changes() {
        let temp = tempfile::tempdir().unwrap();
        let file = temp.path().join("take.mp4");
        std::fs::write(&file, b"first").unwrap();
        let first = cache_key(&file).unwrap();
        std::fs::write(&file, b"longer replacement").unwrap();
        assert_ne!(first, cache_key(&file).unwrap());
    }
}
