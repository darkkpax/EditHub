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
    let mut work = state.work.lock().unwrap();
    let active = &mut work.active;
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
    state.work.lock().unwrap().active.remove("__update__");
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
    if !state.work.lock().unwrap().active.is_empty() {
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
async fn setup_library(videos_folder: String) -> Result<Value> {
    let folder = PathBuf::from(videos_folder);
    if !folder.is_absolute() {
        return Err("Videos folder path must be absolute".into());
    }
    std::fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    let folder = folder.canonicalize().map_err(|e| e.to_string())?;
    let adopted = tauri::async_runtime::spawn_blocking({
        let folder = folder.clone();
        move || projects::adopt_library(&folder)
    })
    .await
    .map_err(|e| e.to_string())??;
    let mut settings = projects::settings()?;
    settings["projectsFolder"] = json!(folder.to_string_lossy().to_string());
    settings["onboardingComplete"] = json!(true);
    #[cfg(target_os = "macos")]
    {
        if let Some(home) = dirs::home_dir() {
            let drive = home.join("Library/Mobile Documents/com~apple~CloudDocs");
            if drive.is_dir() {
                std::fs::create_dir_all(drive.join("edithub/Videos")).map_err(|e| e.to_string())?;
                settings["icloudPath"] = json!(drive.to_string_lossy().to_string());
            }
        }
    }
    projects::write_json(&projects::config_dir().join("settings.json"), &settings)?;
    Ok(json!({"settings":settings,"adopted":adopted}))
}
#[tauri::command]
async fn list_projects(state: State<'_, Arc<downloads::Downloads>>) -> Result<Vec<Value>> {
    let mut list = tauri::async_runtime::spawn_blocking(projects::list)
        .await
        .map_err(|e| e.to_string())??;
    let work = state.work.lock().unwrap();
    for p in &mut list {
        let id = p["id"].as_str().unwrap_or("");
        if work.running.as_deref() == Some(id) {
            p["status"] = json!("downloading");
        } else if let Some(position) = work.pending.iter().position(|job| job.id == id) {
            p["status"] = json!("queued");
            p["downloadQueuePosition"] = json!(position + 1);
        } else if p["status"] == "downloading" || p["status"] == "queued" {
            p["status"] = json!("paused");
            p["downloadError"] = json!("Previous download interrupted. Select Resume to continue");
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
async fn import_project_files(id: String, relative: String, paths: Vec<String>) -> Result<usize> {
    tauri::async_runtime::spawn_blocking(move || projects::import_paths(&id, &relative, &paths))
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
    tauri::async_runtime::spawn_blocking(move || projects::create(&name, &editor, urls))
        .await
        .map_err(|e| e.to_string())?
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
    let operation = Operation::reserve(state.inner().clone(), &id)?;
    let lookup = id.clone();
    let mut project = tauri::async_runtime::spawn_blocking(move || projects::find(&lookup))
        .await
        .map_err(|e| e.to_string())??;
    if project["status"] == "archive" {
        return Err("Restore the project first".into());
    }
    if project["footageUrls"] != json!(urls) {
        project
            .as_object_mut()
            .unwrap()
            .remove("downloadCompletedJobs");
    }
    project["footageUrls"] = json!(urls);
    project["status"] = json!("queued");
    project["downloadError"] = json!("");
    projects::save(&project)?;
    {
        let mut work = state.work.lock().unwrap();
        let cancel = work.active[&id].clone();
        work.pending.push_back(downloads::QueuedDownload {
            id: id.clone(),
            project,
            cancel,
        });
        let _ = app.emit(
            "download-progress",
            downloads::project_progress(&id, "queued", "Waiting in queue", None),
        );
    }
    operation.handoff();
    tauri::async_runtime::spawn(downloads::run(app, state.inner().clone()));
    Ok(())
}
#[tauri::command]
async fn cancel_downloads(
    app: tauri::AppHandle,
    state: State<'_, Arc<downloads::Downloads>>,
    id: String,
) -> Result<()> {
    let mut work = state.work.lock().unwrap();
    if let Some(index) = work.pending.iter().position(|job| job.id == id) {
        let mut project = work.pending[index].project.clone();
        project["status"] = json!("paused");
        projects::save(&project)?;
        work.pending.remove(index);
        work.active.remove(&id);
        let _ = app.emit(
            "download-progress",
            downloads::project_progress(&id, "cancelled", "", None),
        );
    } else if work.running.as_deref() == Some(&id) {
        work.active[&id].cancel();
    }
    Ok(())
}

#[tauri::command]
async fn prioritize_download(
    state: State<'_, Arc<downloads::Downloads>>,
    id: String,
) -> Result<()> {
    state.work.lock().unwrap().prioritize(&id)
}

struct Operation {
    state: Arc<downloads::Downloads>,
    id: Option<String>,
}
impl Operation {
    fn reserve(state: Arc<downloads::Downloads>, id: &str) -> Result<Self> {
        {
            let mut work = state.work.lock().unwrap();
            let active = &mut work.active;
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
            id: Some(id.into()),
        })
    }

    fn handoff(mut self) {
        self.id = None;
    }
}
impl Drop for Operation {
    fn drop(&mut self) {
        if let Some(id) = &self.id {
            self.state.work.lock().unwrap().active.remove(id);
        }
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
#[tauri::command]
async fn archive_inactive_projects(state: State<'_, Arc<downloads::Downloads>>) -> Result<usize> {
    let _operation = Operation::reserve(state.inner().clone(), "__smart_archive__")?;
    let days = projects::settings()?["autoArchiveDays"]
        .as_i64()
        .unwrap_or(30);
    tauri::async_runtime::spawn_blocking(move || projects::archive_inactive(days))
        .await
        .map_err(|e| e.to_string())?
}
fn hidden_command(program: impl AsRef<std::ffi::OsStr>) -> std::process::Command {
    #[allow(unused_mut)]
    let mut c = std::process::Command::new(program);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x08000000);
    }
    c
}

fn editor_is_available(path: &std::path::Path) -> bool {
    #[cfg(target_os = "macos")]
    {
        path.is_dir() && path.extension().is_some_and(|value| value == "app")
    }
    #[cfg(not(target_os = "macos"))]
    {
        path.is_file()
    }
}

fn launch_editor(path: &std::path::Path) -> Result<()> {
    #[cfg(target_os = "macos")]
    let result = hidden_command("open").arg("-a").arg(path).spawn();
    #[cfg(not(target_os = "macos"))]
    let result = hidden_command(path).spawn();
    result.map(|_| ()).map_err(|error| error.to_string())
}

async fn run_bridge(app: &tauri::AppHandle, p: &Value, action: &str) -> Result<()> {
    let exe = projects::setting_path(&projects::settings()?, "davinciPath")?;
    if !editor_is_available(&exe) {
        return Err("Editor not found. Set its path in Settings".into());
    }
    if action == "export" {
        launch_editor(&exe)?;
    }
    let bridge = app
        .path()
        .resolve(
            "resources/resolve_project_bridge.py",
            tauri::path::BaseDirectory::Resource,
        )
        .map_err(|e| e.to_string())?;
    #[cfg(target_os = "macos")]
    let runner = PathBuf::from("/usr/bin/python3");
    #[cfg(not(target_os = "macos"))]
    let runner = exe.parent().unwrap().join("fuscript.exe");
    let folder = projects::path_of(p)?;
    let name = p["name"].as_str().unwrap_or("Project").to_string();
    let action = action.to_string();
    tauri::async_runtime::spawn_blocking(move || {
        let mut c = hidden_command(if runner.exists() {
            runner
        } else {
            PathBuf::from("python3")
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
    if !editor_is_available(&exe) {
        return Err("Editor not found. Set its path in Settings".into());
    }
    launch_editor(&exe)?;
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
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
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
            setup_library,
            list_projects,
            project_entries,
            import_project_files,
            previews::project_preview,
            create_project,
            start_downloads,
            cancel_downloads,
            prioritize_download,
            reveal_project,
            delete_project,
            transfer_project,
            archive_inactive_projects,
            open_project,
            auth::google_status,
            auth::configure_google,
            auth::connect_google
        ])
        .build(tauri::generate_context!())
        .expect("error building EditHub")
        .run(|_app, _event| {
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Reopen { .. } = _event {
                if let Some(window) = _app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.unminimize();
                    let _ = window.set_focus();
                }
            }
        });
}
