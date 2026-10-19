mod auth;
mod downloads;
mod previews;
mod projects;
use projects::Result;
use serde_json::{json, Value};
use std::{path::PathBuf, sync::Arc};
use tauri::{Emitter, Manager, State};

#[tauri::command]
fn ensure_idle_for_update(
    state: State<'_, Arc<downloads::Downloads>>,
    reserve: bool,
) -> Result<()> {
    let mut active = state.active.lock().unwrap();
    if !active.is_empty() {
        return Err("Wait for current operations before installing the update".into());
    }
    if reserve {
        active.insert(
            "__update__".into(),
            tokio_util::sync::CancellationToken::new(),
        );
    }
    Ok(())
}

#[tauri::command]
fn release_update_install(state: State<'_, Arc<downloads::Downloads>>) {
    state.active.lock().unwrap().remove("__update__");
}

#[tauri::command]
async fn get_settings() -> Result<Value> {
    projects::settings()
}
#[tauri::command]
async fn save_settings(
    state: State<'_, Arc<downloads::Downloads>>,
    settings: Value,
) -> Result<Value> {
    if !state.active.lock().unwrap().is_empty() {
        return Err("Wait for current operations before changing settings".into());
    }
    let mut current = projects::settings()?;
    let update = settings.as_object().ok_or("Invalid settings")?;
    for key in [
        "projectsFolder",
        "downloadsFolder",
        "icloudPath",
        "davinciPath",
    ] {
        if update.contains_key(key) {
            projects::setting_path(&settings, key)?;
        }
    }
    current.as_object_mut().unwrap().extend(update.clone());
    projects::write_json(&projects::config_dir().join("settings.json"), &current)?;
    Ok(current)
}
#[tauri::command]
async fn list_projects(state: State<'_, Arc<downloads::Downloads>>) -> Result<Vec<Value>> {
    let mut list = tauri::async_runtime::spawn_blocking(projects::list)
        .await
        .map_err(|e| e.to_string())??;
    let active = state.active.lock().unwrap();
    for p in &mut list {
        if p["status"] == "downloading" && !active.contains_key(p["id"].as_str().unwrap_or("")) {
            p["status"] = json!("paused");
            p["downloadError"] =
                json!("Previous download interrupted. Select Retry download to resume");
        }
    }
    Ok(list)
}
#[tauri::command]
async fn project_entries(
    id: String,
    relative: String,
    folder_path: Option<String>,
) -> Result<Vec<Value>> {
    tauri::async_runtime::spawn_blocking(move || {
        let path = if let Some(folder) = folder_path {
            projects::known_subpath(
                &id,
                std::path::Path::new(&folder),
                &relative,
                &projects::roots(&projects::settings()?)?,
            )?
        } else {
            projects::validated_subpath(&id, &relative)?
        };
        projects::entries(&path)
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn create_project(
    state: State<'_, Arc<downloads::Downloads>>,
    name: String,
    editor: String,
    urls: Vec<String>,
) -> Result<Value> {
    let _operation = Operation::reserve(state.inner().clone(), "__create__")?;
    projects::create(&name, &editor, urls)
}
#[tauri::command]
async fn start_downloads(
    app: tauri::AppHandle,
    state: State<'_, Arc<downloads::Downloads>>,
    id: String,
    urls: Vec<String>,
) -> Result<()> {
    if urls.is_empty() {
        return Err("Add at least one URL".into());
    }
    for url in &urls {
        downloads::normalize(url)?;
    }
    let p = projects::find(&id)?;
    if p["status"] == "archive" {
        return Err("Restore the project first".into());
    }
    let cancel = tokio_util::sync::CancellationToken::new();
    {
        let mut active = state.active.lock().unwrap();
        if active.contains_key("__update__") {
            return Err("Update installation in progress".into());
        }
        if active.contains_key(&id) {
            return Err("Project is already downloading".into());
        }
        active.insert(id.clone(), cancel.clone());
    }
    let _ = app.emit(
        "download-progress",
        downloads::Progress {
            project_id: id.clone(),
            file_url: String::new(),
            file_name: "Preparing files…".into(),
            bytes_downloaded: 0,
            total_bytes: 0,
            percent: 0,
            state: "downloading".into(),
            error: None,
        },
    );
    let owned = state.inner().clone();
    tauri::async_runtime::spawn(downloads::run(app, owned, id, urls, cancel));
    Ok(())
}
#[tauri::command]
async fn cancel_downloads(state: State<'_, Arc<downloads::Downloads>>, id: String) -> Result<()> {
    if let Some(cancel) = state.active.lock().unwrap().get(&id) {
        cancel.cancel();
    }
    Ok(())
}
struct Operation {
    state: Arc<downloads::Downloads>,
    id: String,
}
impl Operation {
    fn reserve(state: Arc<downloads::Downloads>, id: &str) -> Result<Self> {
        {
            let mut active = state.active.lock().unwrap();
            if active.contains_key("__update__") {
                return Err("Update installation in progress".into());
            }
            if active.contains_key(id) {
                return Err("Wait for the current operation to finish or cancel it".into());
            }
            active.insert(id.into(), tokio_util::sync::CancellationToken::new());
        }
        Ok(Self {
            state,
            id: id.into(),
        })
    }
}
impl Drop for Operation {
    fn drop(&mut self) {
        self.state.active.lock().unwrap().remove(&self.id);
    }
}
#[tauri::command]
async fn reveal_project(id: String, relative: String) -> Result<()> {
    let path = projects::validated_subpath(&id, &relative)?;
    open::that_detached(path).map_err(|e| e.to_string())
}
#[tauri::command]
async fn delete_project(state: State<'_, Arc<downloads::Downloads>>, id: String) -> Result<()> {
    let _operation = Operation::reserve(state.inner().clone(), &id)?;
    let p = projects::find(&id)?;
    let path = projects::path_of(&p)?
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let allowed = projects::roots(&projects::settings()?)?
        .iter()
        .filter_map(|p| p.canonicalize().ok())
        .any(|root| path != root && path.starts_with(root));
    if !allowed {
        return Err("Project is outside configured root folders".into());
    }
    tauri::async_runtime::spawn_blocking(move || trash::delete(path).map_err(|e| e.to_string()))
        .await
        .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn transfer_project(
    app: tauri::AppHandle,
    state: State<'_, Arc<downloads::Downloads>>,
    id: String,
    restore: bool,
) -> Result<()> {
    let _operation = Operation::reserve(state.inner().clone(), &id)?;
    if !restore {
        let p = projects::find(&id)?;
        if p["editor"] != "davinci" {
            return Err("This project uses an unsupported editor".into());
        }
        run_bridge(&app, &p, "export").await?;
    }
    tauri::async_runtime::spawn_blocking(move || projects::transfer(&id, restore))
        .await
        .map_err(|e| e.to_string())?
}
fn hidden_command(program: impl AsRef<std::ffi::OsStr>) -> std::process::Command {
    let mut c = std::process::Command::new(program);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x08000000);
    }
    c
}
async fn run_bridge(app: &tauri::AppHandle, p: &Value, action: &str) -> Result<()> {
    let exe = projects::setting_path(&projects::settings()?, "davinciPath")?;
    if !exe.is_file() {
        return Err("Editor not found. Set its path in Settings".into());
    }
    if action == "export" {
        hidden_command(&exe).spawn().map_err(|e| e.to_string())?;
    }
    let bridge = app
        .path()
        .resolve(
            "resources/resolve_project_bridge.py",
            tauri::path::BaseDirectory::Resource,
        )
        .map_err(|e| e.to_string())?;
    let runner = exe.parent().unwrap().join("fuscript.exe");
    let folder = projects::path_of(p)?;
    let name = p["name"].as_str().unwrap_or("Project").to_string();
    let action = action.to_string();
    tauri::async_runtime::spawn_blocking(move || {
        let mut c = hidden_command(if runner.exists() {
            runner
        } else {
            PathBuf::from("python")
        });
        c.arg(bridge)
            .args([
                "--action",
                &action,
                "--project-name",
                &name,
                "--project-folder",
            ])
            .arg(&folder)
            .arg("--drp-path")
            .arg(folder.join(format!("{name}.drp")))
            .args(["--timeout", "45"]);
        let out = c
            .output()
            .map_err(|e| format!("Editor export failed. Original preserved: {e}"))?;
        if !out.status.success() {
            return Err(format!(
                "Could not save editor project. Original preserved: {}",
                String::from_utf8_lossy(&out.stderr)
            ));
        }
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn open_project(
    app: tauri::AppHandle,
    state: State<'_, Arc<downloads::Downloads>>,
    id: String,
) -> Result<String> {
    let _operation = Operation::reserve(state.inner().clone(), &id)?;
    let mut p = projects::find(&id)?;
    let settings = projects::settings()?;
    if p["editor"] != "davinci" {
        return Err("This project uses an unsupported editor".into());
    }
    let exe = projects::setting_path(&settings, "davinciPath")?;
    if !exe.is_file() {
        return Err("Editor not found. Set its path in Settings".into());
    }
    hidden_command(&exe).spawn().map_err(|e| e.to_string())?;
    run_bridge(&app, &p, "open")
        .await
        .map_err(|e| format!("Editor started, but the project could not be opened: {e}"))?;
    p["lastOpenedAt"] = json!(chrono::Utc::now().to_rfc3339());
    p["status"] = json!("active");
    projects::save(&p)?;
    Ok("Project opened".into())
}
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(Arc::new(downloads::Downloads::default()))
        .setup(|app| {
            use tauri::{
                menu::{Menu, MenuItem},
                tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
            };
            let show = MenuItem::with_id(app, "show", "Open", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;
            TrayIconBuilder::with_id("main")
                .icon(app.default_window_icon().ok_or("missing app icon")?.clone())
                .tooltip("Projects")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if matches!(
                        event,
                        TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            ..
                        }
                    ) {
                        if let Some(window) = tray.app_handle().get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if window.app_handle().tray_by_id("main").is_some() {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            ensure_idle_for_update,
            release_update_install,
            get_settings,
            save_settings,
            list_projects,
            project_entries,
            previews::project_preview,
            create_project,
            start_downloads,
            cancel_downloads,
            reveal_project,
            delete_project,
            transfer_project,
            open_project,
            auth::google_status,
            auth::configure_google,
            auth::connect_google
        ])
        .run(tauri::generate_context!())
        .expect("error running EditHub");
}
