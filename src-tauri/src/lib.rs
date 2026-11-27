use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;
use tauri::{Emitter, Manager, State};
use tauri_plugin_deep_link::DeepLinkExt;

const DEFAULT_HUB_URL: &str = "https://leaf.starryheavens.uk";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct StoredCredentials {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub device_token: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub device_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub device_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub account_sub: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub account_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub account_email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hub_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct HubConfig {
    pub hub_url: Option<String>,
}

struct PendingDeepLinks(Mutex<Vec<String>>);

fn storage_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let base = app
        .path()
        .data_dir()
        .map_err(|e| format!("无法获取应用支持目录: {e}"))?;
    let dir = base.join("LooseLeaf");
    if !dir.exists() {
        fs::create_dir_all(&dir).map_err(|e| format!("无法创建凭据目录: {e}"))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
        }
    }
    Ok(dir)
}

fn write_secure_json(path: &PathBuf, content: &[u8]) -> Result<(), String> {
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, content).map_err(|e| format!("写入临时凭据文件失败: {e}"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600));
    }
    fs::rename(&tmp, path).map_err(|e| format!("替换凭据文件失败: {e}"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }
    Ok(())
}

#[tauri::command]
fn load_credentials(app: tauri::AppHandle) -> Result<StoredCredentials, String> {
    let dir = storage_dir(&app)?;
    let creds_path = dir.join("credentials.json");
    let hub_path = dir.join("hub_config.json");

    let mut creds = if creds_path.exists() {
        let raw = fs::read_to_string(&creds_path).map_err(|e| format!("读取凭据失败: {e}"))?;
        serde_json::from_str::<StoredCredentials>(&raw).unwrap_or_default()
    } else {
        StoredCredentials::default()
    };

    if creds.hub_url.as_deref().unwrap_or("").trim().is_empty() {
        if hub_path.exists() {
            if let Ok(raw) = fs::read_to_string(&hub_path) {
                if let Ok(cfg) = serde_json::from_str::<HubConfig>(&raw) {
                    if let Some(url) = cfg.hub_url {
                        if !url.trim().is_empty() {
                            creds.hub_url = Some(url);
                        }
                    }
                }
            }
        }
    }

    if creds.hub_url.as_deref().unwrap_or("").trim().is_empty() {
        creds.hub_url = Some(DEFAULT_HUB_URL.to_string());
    }

    Ok(creds)
}

#[tauri::command]
fn save_credentials(app: tauri::AppHandle, creds: StoredCredentials) -> Result<(), String> {
    let dir = storage_dir(&app)?;
    let creds_path = dir.join("credentials.json");
    let hub_path = dir.join("hub_config.json");

    let mut vault_only = creds.clone();
    let hub_url = vault_only.hub_url.take();

    let creds_bytes =
        serde_json::to_vec_pretty(&vault_only).map_err(|e| format!("序列化凭据失败: {e}"))?;
    write_secure_json(&creds_path, &creds_bytes)?;

    if let Some(url) = hub_url {
        let cleaned = url.trim().trim_end_matches('/').to_string();
        if !cleaned.is_empty() {
            let hub_bytes = serde_json::to_vec_pretty(&HubConfig {
                hub_url: Some(cleaned),
            })
            .map_err(|e| format!("序列化中枢配置失败: {e}"))?;
            write_secure_json(&hub_path, &hub_bytes)?;
        }
    }

    Ok(())
}

#[tauri::command]
fn clear_credentials(app: tauri::AppHandle) -> Result<(), String> {
    let dir = storage_dir(&app)?;
    let creds_path = dir.join("credentials.json");
    let empty = StoredCredentials::default();
    let bytes = serde_json::to_vec_pretty(&empty).map_err(|e| format!("序列化空凭据失败: {e}"))?;
    write_secure_json(&creds_path, &bytes)?;
    Ok(())
}

#[tauri::command]
fn get_device_hostname() -> String {
    #[cfg(target_os = "macos")]
    {
        if let Ok(out) = Command::new("scutil").args(["--get", "ComputerName"]).output() {
            if out.status.success() {
                let name = String::from_utf8_lossy(&out.stdout).trim().to_string();
                if !name.is_empty() {
                    return name;
                }
            }
        }
    }
    if let Ok(out) = Command::new("hostname").output() {
        if out.status.success() {
            let name = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !name.is_empty() {
                return name;
            }
        }
    }
    "Mac".to_string()
}

#[tauri::command]
fn get_pending_deep_links(state: State<'_, PendingDeepLinks>) -> Vec<String> {
    let mut guard = state.0.lock().unwrap_or_else(|e| e.into_inner());
    let urls = guard.clone();
    guard.clear();
    urls
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(PendingDeepLinks(Mutex::new(Vec::new())))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_deep_link::init())
        .setup(|app| {
            if let Ok(Some(initial_urls)) = app.deep_link().get_current() {
                let list: Vec<String> = initial_urls.into_iter().map(|u| u.to_string()).collect();
                if !list.is_empty() {
                    let state = app.state::<PendingDeepLinks>();
                    let mut guard = state.0.lock().unwrap_or_else(|e| e.into_inner());
                    guard.extend(list);
                }
            }

            let handle = app.handle().clone();
            app.deep_link().on_open_url(move |event| {
                let urls: Vec<String> = event.urls().iter().map(|u| u.to_string()).collect();
                if urls.is_empty() {
                    return;
                }
                if let Some(win) = handle.get_webview_window("main") {
                    let _ = win.set_focus();
                }
                if handle.emit("deep-link-url", &urls).is_err() {
                    let state = handle.state::<PendingDeepLinks>();
                    let mut guard = state.0.lock().unwrap_or_else(|e| e.into_inner());
                    guard.extend(urls);
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_credentials,
            save_credentials,
            clear_credentials,
            get_device_hostname,
            get_pending_deep_links
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
