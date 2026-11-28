use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
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

#[derive(Debug, Clone, Serialize, Default)]
struct UpdateProgressPayload {
    stage: String,
    progress: f64,
    message: String,
}

#[tauri::command]
fn get_app_version(app: tauri::AppHandle) -> String {
    app.package_info().version.to_string()
}

fn is_allowed_release_url(url: &str) -> bool {
    url.starts_with("https://github.com/Losse-Leaf/MacOS/releases/download/")
        || url.starts_with("https://objects.githubusercontent.com/")
}

fn normalize_sha256_hex(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    let stripped = trimmed
        .strip_prefix("sha256:")
        .or_else(|| trimmed.strip_prefix("SHA256:"))
        .unwrap_or(trimmed)
        .trim();
    if stripped.len() == 64 && stripped.bytes().all(|b| b.is_ascii_hexdigit()) {
        Some(stripped.to_ascii_lowercase())
    } else {
        None
    }
}

fn shell_single_quoted(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn build_swap_script(target: &Path, source: &Path, old_pid: u32, work_dir: &Path) -> String {
    let target_q = shell_single_quoted(&target.to_string_lossy());
    let source_q = shell_single_quoted(&source.to_string_lossy());
    let pid_q = shell_single_quoted(&old_pid.to_string());
    let work_q = shell_single_quoted(&work_dir.to_string_lossy());

    format!(
        r#"#!/bin/bash
TARGET={target_q}
SOURCE={source_q}
OLD_PID={pid_q}
WORK_DIR={work_q}

if [[ "$OLD_PID" =~ ^[0-9]+$ ]] && [ "$OLD_PID" -gt 1 ]; then
    COUNT=0
    while kill -0 "$OLD_PID" 2>/dev/null; do
        sleep 0.2
        COUNT=$((COUNT + 1))
        if [ $COUNT -ge 75 ]; then
            kill -9 "$OLD_PID" 2>/dev/null || true
            break
        fi
    done
fi

sleep 0.3

INSTALL_DIR="$(dirname "$TARGET")"
APP_BASE="$(basename "$TARGET" .app)"
STAGING_PATH="${{INSTALL_DIR}}/.${{APP_BASE}}.installing.$$"
BACKUP_PATH="${{INSTALL_DIR}}/.${{APP_BASE}}.backup.$$"

rm -rf "$STAGING_PATH"
if ! cp -R "$SOURCE" "$STAGING_PATH"; then
    rm -rf "$STAGING_PATH"
    rm -rf "$WORK_DIR"
    exit 1
fi

if [ -d "$TARGET" ]; then
    if ! mv "$TARGET" "$BACKUP_PATH"; then
        rm -rf "$STAGING_PATH"
        rm -rf "$WORK_DIR"
        exit 1
    fi
fi

if mv "$STAGING_PATH" "$TARGET"; then
    rm -rf "$BACKUP_PATH"
    open "$TARGET"
    rm -rf "$WORK_DIR"
    exit 0
fi

if [ -d "$BACKUP_PATH" ]; then
    mv "$BACKUP_PATH" "$TARGET"
    open "$TARGET"
fi
rm -rf "$STAGING_PATH"
rm -rf "$WORK_DIR"
exit 1
"#
    )
}

fn is_dir_writable(dir: &Path) -> bool {
    if !dir.is_dir() {
        return false;
    }
    let probe = dir.join(format!(".looseleaf_write_test_{}", std::process::id()));
    match fs::OpenOptions::new().write(true).create_new(true).open(&probe) {
        Ok(_) => {
            let _ = fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

fn resolve_target_app_path() -> PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        for ancestor in exe.ancestors() {
            if ancestor.extension().and_then(|e| e.to_str()) == Some("app") {
                if let Some(parent) = ancestor.parent() {
                    if is_dir_writable(parent) {
                        return ancestor.to_path_buf();
                    }
                }
            }
        }
    }
    PathBuf::from("/Applications/LooseLeaf.app")
}

fn find_app_bundle(dir: &Path, depth: usize) -> Option<PathBuf> {
    if depth > 3 {
        return None;
    }
    let entries = fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if path.file_name().and_then(|n| n.to_str()) == Some("LooseLeaf.app") {
                return Some(path);
            }
            if let Some(found) = find_app_bundle(&path, depth + 1) {
                return Some(found);
            }
        }
    }
    None
}

fn emit_update_progress(app: &tauri::AppHandle, stage: &str, progress: f64, message: &str) {
    let _ = app.emit(
        "app-update-progress",
        UpdateProgressPayload {
            stage: stage.to_string(),
            progress,
            message: message.to_string(),
        },
    );
}

fn perform_app_update_blocking(
    app: &tauri::AppHandle,
    download_url: String,
    expected_sha256: String,
    asset_name: String,
) -> Result<(), String> {
    if !is_allowed_release_url(&download_url) {
        return Err("更新下载地址不在官方 GitHub Release 允许列表中".to_string());
    }
    let wanted_hex = normalize_sha256_hex(&expected_sha256)
        .ok_or_else(|| "更新包缺少有效的 SHA256 摘要，已中止安装".to_string())?;

    let target_app = resolve_target_app_path();
    let target_parent = target_app
        .parent()
        .ok_or_else(|| "无法定位目标安装目录".to_string())?;
    if !is_dir_writable(target_parent) {
        return Err(format!(
            "没有权限写入安装目录 {}，请将应用移至「应用程序」文件夹或使用终端脚本升级",
            target_parent.display()
        ));
    }

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let work_dir = std::env::temp_dir().join(format!("looseleaf-update-{}-{}", std::process::id(), nanos));
    fs::create_dir_all(&work_dir).map_err(|e| format!("创建更新临时目录失败: {e}"))?;

    let result = (|| -> Result<(), String> {
        let label = Path::new(&asset_name)
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("LooseLeaf.zip");
        emit_update_progress(app, "downloading", 0.15, &format!("正在下载 {label}…"));

        let zip_path = work_dir.join("update.zip");
        let curl_out = Command::new("curl")
            .args(["-fsSL", "--retry", "2", "-o"])
            .arg(&zip_path)
            .arg(&download_url)
            .output()
            .map_err(|e| format!("无法启动下载器: {e}"))?;
        if !curl_out.status.success() {
            let err_text = String::from_utf8_lossy(&curl_out.stderr);
            return Err(format!("下载更新包失败: {}", err_text.trim()));
        }

        emit_update_progress(app, "verifying", 0.55, "正在校验更新包 SHA256 完整性…");
        let shasum_out = Command::new("shasum")
            .args(["-a", "256"])
            .arg(&zip_path)
            .output()
            .map_err(|e| format!("SHA256 校验工具启动失败: {e}"))?;
        if !shasum_out.status.success() {
            return Err("无法计算更新包 SHA256 摘要".to_string());
        }
        let shasum_stdout = String::from_utf8_lossy(&shasum_out.stdout);
        let actual_hex = shasum_stdout
            .split_whitespace()
            .next()
            .and_then(normalize_sha256_hex)
            .ok_or_else(|| "无法解析更新包 SHA256 输出".to_string())?;
        if actual_hex != wanted_hex {
            return Err("更新包校验失败（SHA256 不匹配），已中止安装".to_string());
        }

        emit_update_progress(app, "extracting", 0.75, "正在解压新版应用包…");
        let extract_dir = work_dir.join("extracted");
        fs::create_dir_all(&extract_dir).map_err(|e| format!("创建解压目录失败: {e}"))?;
        let ditto_out = Command::new("ditto")
            .args(["-x", "-k"])
            .arg(&zip_path)
            .arg(&extract_dir)
            .output()
            .map_err(|e| format!("解压工具启动失败: {e}"))?;
        if !ditto_out.status.success() {
            let err_text = String::from_utf8_lossy(&ditto_out.stderr);
            return Err(format!("解压新版应用包失败: {}", err_text.trim()));
        }

        let source_app = find_app_bundle(&extract_dir, 0)
            .ok_or_else(|| "更新压缩包中未找到 LooseLeaf.app".to_string())?;

        emit_update_progress(app, "relaunching", 0.92, "正在准备原子替换并重启应用…");
        let script_path = work_dir.join("swap.sh");
        let script_content = build_swap_script(&target_app, &source_app, std::process::id(), &work_dir);
        fs::write(&script_path, script_content.as_bytes())
            .map_err(|e| format!("写入替换脚本失败: {e}"))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&script_path, fs::Permissions::from_mode(0o700))
                .map_err(|e| format!("设置替换脚本权限失败: {e}"))?;
        }

        let launch_cmd = format!(
            "nohup /bin/bash {} >/dev/null 2>&1 &",
            shell_single_quoted(&script_path.to_string_lossy())
        );
        let spawn_status = Command::new("/bin/bash")
            .args(["-c", &launch_cmd])
            .status()
            .map_err(|e| format!("启动更新守护脚本失败: {e}"))?;
        if !spawn_status.success() {
            return Err("无法在后台拉起应用替换脚本".to_string());
        }

        emit_update_progress(app, "done", 1.0, "更新就绪，正在重启…");
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_dir_all(&work_dir);
    }
    result
}

#[tauri::command]
async fn perform_app_update(
    app: tauri::AppHandle,
    download_url: String,
    expected_sha256: String,
    asset_name: String,
) -> Result<(), String> {
    let app_clone = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        perform_app_update_blocking(&app_clone, download_url, expected_sha256, asset_name)
    })
    .await
    .map_err(|e| format!("更新任务异常中断: {e}"))??;

    std::thread::sleep(Duration::from_millis(120));
    app.exit(0);
    Ok(())
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
            get_pending_deep_links,
            get_app_version,
            perform_app_update
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_official_release_urls_only() {
        assert!(is_allowed_release_url(
            "https://github.com/Losse-Leaf/MacOS/releases/download/v4.2.0/LooseLeaf-v4.2.0-arm64.zip"
        ));
        assert!(is_allowed_release_url(
            "https://objects.githubusercontent.com/github-production-release-asset/123"
        ));
        assert!(!is_allowed_release_url("http://github.com/Losse-Leaf/MacOS/releases/download/x.zip"));
        assert!(!is_allowed_release_url("https://evil.example.com/LooseLeaf.zip"));
    }

    #[test]
    fn normalizes_sha256_digests_strictly() {
        let hex = "A".repeat(64);
        assert_eq!(normalize_sha256_hex(&format!("sha256:{hex}")), Some("a".repeat(64)));
        assert_eq!(normalize_sha256_hex(&hex), Some("a".repeat(64)));
        assert_eq!(normalize_sha256_hex("sha256:short"), None);
        assert_eq!(normalize_sha256_hex(&"z".repeat(64)), None);
    }

    #[test]
    fn builds_atomic_swap_script_with_escaped_paths_and_rollback() {
        let script = build_swap_script(
            Path::new("/Applications/LooseLeaf's.app"),
            Path::new("/tmp/extract/LooseLeaf.app"),
            4321,
            Path::new("/tmp/work"),
        );
        assert!(script.contains("TARGET='/Applications/LooseLeaf'\\''s.app'"));
        assert!(script.contains("OLD_PID='4321'"));
        assert!(script.contains("BACKUP_PATH="));
        assert!(script.contains("mv \"$BACKUP_PATH\" \"$TARGET\""));
        assert!(!script.contains("xattr -cr"));
    }
}
