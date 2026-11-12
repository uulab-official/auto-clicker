//! CI-only Wayland experiment. This is not a supported production backend.
//!
//! It accepts only current-pointer clicks, keeps a portal shortcut session
//! alive, hides the app while running and restores it when execution stops.
//! Portal backends used in the test are mocks; do not enable this for users.
use super::{
    emit_status,
    engine::{Config, MouseButton, Step},
    stop, AppState,
};
use ashpd::desktop::{
    global_shortcuts::{GlobalShortcuts, NewShortcut},
    remote_desktop::{DeviceType, KeyState, RemoteDesktop},
    PersistMode,
};
use futures_util::StreamExt;
use std::{
    env,
    os::unix::fs::FileTypeExt,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::Duration,
};
use tauri::Manager;

const STOP_ID: &str = "emergency-stop";

pub fn isolated_ci_only() -> bool {
    let Ok(runtime) = env::var("XDG_RUNTIME_DIR") else {
        return false;
    };
    let Ok(temp) = env::var("RUNNER_TEMP") else {
        return false;
    };
    let Ok(runtime) = Path::new(&runtime).canonicalize() else {
        return false;
    };
    let Ok(temp) = Path::new(&temp).canonicalize() else {
        return false;
    };
    env::var("AUTOCLICKER_EXPERIMENTAL_WAYLAND").as_deref() == Ok("1")
        && env::var("CI").as_deref() == Ok("true")
        && env::var("GITHUB_ACTIONS").as_deref() == Ok("true")
        && env::var("WAYLAND_DISPLAY").as_deref() == Ok("wayland-ci")
        && env::var("DISPLAY").is_err()
        && runtime.starts_with(temp)
        && std::fs::metadata(runtime.join("wayland-ci")).is_ok_and(|m| m.file_type().is_socket())
}

fn shortcut_unavailable(app: &tauri::AppHandle, error: &str) {
    stop(app);
    let state = app.state::<AppState>();
    if let Ok(mut inner) = state.0.lock() {
        inner.status.shortcut_error = Some(error.to_string());
        inner.status.available_shortcuts.clear();
        emit_status(app, inner.status.clone());
    };
}

pub fn initialize_shortcut(app: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        if let Err(error) = run_shortcut(&app).await {
            shortcut_unavailable(
                &app,
                &format!("Wayland emergency shortcut unavailable: {error}"),
            );
        }
    });
}

async fn run_shortcut(app: &tauri::AppHandle) -> Result<(), String> {
    let portal = GlobalShortcuts::new().await.map_err(|e| e.to_string())?;
    let registry = zbus::Proxy::new(portal.connection(), "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.host.portal.Registry").await.map_err(|e| e.to_string())?;
    let options: std::collections::HashMap<&str, zbus::zvariant::Value<'_>> = std::collections::HashMap::new();
    let registered: Result<(), _> = registry.call("Register", &("kr.co.uulab.autoclicker", &options)).await;
    eprintln!("CI host portal registration: {registered:?}");
    let session = portal.create_session().await.map_err(|e| e.to_string())?;
    let session_path: String =
        serde_json::from_value(serde_json::to_value(&session).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let session_proxy = zbus::Proxy::new(
        portal.connection(),
        "org.freedesktop.portal.Desktop",
        session_path.as_str(),
        "org.freedesktop.portal.Session",
    )
    .await
    .map_err(|e| e.to_string())?;
    let bus = zbus::fdo::DBusProxy::new(portal.connection())
        .await
        .map_err(|e| e.to_string())?;
    let owner_changes = bus
        .receive_name_owner_changed_with_args(&[(0, "org.freedesktop.portal.Desktop")])
        .await
        .map_err(|e| e.to_string())?;
    let activated = portal
        .receive_activated()
        .await
        .map_err(|e| e.to_string())?;
    let changed = portal
        .receive_shortcuts_changed()
        .await
        .map_err(|e| e.to_string())?;
    // Read the raw signal. The portal specifies an a{sv} details body; a
    // typed unit stream may silently discard it during deserialization.
    let closed = session_proxy
        .receive_signal("Closed")
        .await
        .map_err(|e| e.to_string())?;
    tokio::pin!(activated, changed, closed, owner_changes);
    let requested =
        [NewShortcut::new(STOP_ID, "Emergency stop").preferred_trigger(Some("CTRL+SHIFT+F8"))];
    let response = portal
        .bind_shortcuts(&session, &requested, None)
        .await
        .map_err(|e| e.to_string())?
        .response()
        .map_err(|e| e.to_string())?;
    let label = response
        .shortcuts()
        .iter()
        .find(|s| s.id() == STOP_ID && !s.trigger_description().trim().is_empty())
        .ok_or("No emergency shortcut was bound")?
        .trigger_description()
        .to_owned();
    {
        let state = app.state::<AppState>();
        let mut inner = state.0.lock().map_err(|_| "State unavailable")?;
        inner.status.shortcut_error = None;
        inner.status.available_shortcuts = vec![label];
        emit_status(app, inner.status.clone());
    }
    loop {
        tokio::select! {
            biased;
            event = activated.next() => match event {
                Some(event) if event.session_handle().as_str() == session_path && event.shortcut_id() == STOP_ID => {
                    eprintln!("CI observed emergency shortcut activation");
                    stop(app);
                },
                Some(_) => {},
                None => return Err("Shortcut event stream ended".into()),
            },
            event = changed.next() => match event {
                Some(event) if event.session_handle().as_str() == session_path => {
                    if !event.shortcuts().iter().any(|s| s.id() == STOP_ID && !s.trigger_description().trim().is_empty()) {
                        return Err("Shortcut was revoked".into());
                    }
                },
                Some(_) => {},
                None => return Err("Shortcut update stream ended".into()),
            },
            _ = closed.next() => return Err("Shortcut portal session closed".into()),
            _ = owner_changes.next() => return Err("Desktop portal service disconnected or changed owner".into()),
        }
    }
}

struct RestoreWindow(tauri::WebviewWindow);
impl Drop for RestoreWindow {
    fn drop(&mut self) {
        let _ = self.0.show();
        eprintln!("CI Wayland window restore requested");
        eprintln!("CI Wayland window visibility after restore: {:?}", self.0.is_visible());
    }
}

pub fn validate_config(config: &Config) -> Result<(), String> {
    if config.steps.iter().any(|step| {
        matches!(
            step,
            Step::Click {
                position: Some(_),
                ..
            }
        )
    }) {
        return Err("Wayland experiment supports only clicks at the current pointer; fixed coordinates are not supported.".into());
    }
    Ok(())
}

pub fn spawn_run(app: tauri::AppHandle, config: Config, cancel: Arc<AtomicBool>) {
    // Additional containment for the disposable CI experiment, independent
    // of the async portal loop: never run unbounded while debugging a lost
    // signal, and restore the window if the portal future stalls.
    let finished = Arc::new(AtomicBool::new(false));
    let watchdog_done = finished.clone();
    let watchdog_cancel = cancel.clone();
    let watchdog_app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(8));
        if !watchdog_done.load(Ordering::Acquire) {
            eprintln!("CI safety watchdog stopped the experimental run");
            watchdog_cancel.store(true, Ordering::Release);
            if let Some(window) = watchdog_app.get_webview_window("main") {
                let _ = window.show();
            }
        }
    });
    tauri::async_runtime::spawn(async move {
        let result = run(&app, &config, &cancel).await;
        eprintln!("CI Wayland run result: {result:?}");
        finished.store(true, Ordering::Release);
        let state = app.state::<AppState>();
        if let Ok(mut inner) = state.0.lock() {
            inner.status.running = false;
            inner.status.error = result.err();
            inner.cancel = None;
            emit_status(&app, inner.status.clone());
        };
    });
}

async fn run(app: &tauri::AppHandle, config: &Config, cancel: &AtomicBool) -> Result<(), String> {
    let portal = RemoteDesktop::new().await.map_err(|e| e.to_string())?;
    let session = portal.create_session().await.map_err(|e| e.to_string())?;
    eprintln!("CI remote session: {:?}", serde_json::to_value(&session));
    let session_path: String =
        serde_json::from_value(serde_json::to_value(&session).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let session_proxy = zbus::Proxy::new(
        portal.connection(),
        "org.freedesktop.portal.Desktop",
        session_path.as_str(),
        "org.freedesktop.portal.Session",
    )
    .await
    .map_err(|e| e.to_string())?;
    let closed = session_proxy
        .receive_signal("Closed")
        .await
        .map_err(|e| e.to_string())?;
    tokio::pin!(closed);
    portal
        .select_devices(
            &session,
            DeviceType::Pointer.into(),
            None,
            PersistMode::DoNot,
        )
        .await
        .map_err(|e| e.to_string())?
        .response()
        .map_err(|e| e.to_string())?;
    let selected = portal
        .start(&session, None)
        .await
        .map_err(|e| e.to_string())?
        .response()
        .map_err(|e| e.to_string())?;
    eprintln!("CI remote pointer permission returned");
    if !selected.devices().contains(DeviceType::Pointer) {
        return Err("Pointer control was not granted".into());
    }
    if cancel.load(Ordering::Acquire) {
        return Ok(());
    }
    let window = app
        .get_webview_window("main")
        .ok_or("Application window unavailable")?;
    window.hide().map_err(|e| e.to_string())?;
    let _restore = RestoreWindow(window.clone());
    if window.is_visible().map_err(|e| e.to_string())? {
        return Err("Could not hide application window safely".into());
    }
    eprintln!("CI Wayland app window hidden");
    let mut count = 0;
    let mut delay = config.start_delay_ms;
    loop {
        while delay > 0 {
            let slice = delay.min(10);
            tokio::select! { biased;
                _ = closed.next() => { eprintln!("CI observed remote session close"); return Err("Remote desktop session closed".into()); },
                _ = tokio::time::sleep(Duration::from_millis(slice)) => {}
            }
            if cancel.load(Ordering::Acquire) {
                return Ok(());
            }
            if window.is_visible().map_err(|e| e.to_string())? {
                return Err("Application window was shown while clicking".into());
            }
            delay -= slice;
        }
        for step in &config.steps {
            if cancel.load(Ordering::Acquire) {
                return Ok(());
            }
            if window.is_visible().map_err(|e| e.to_string())? {
                return Err("Application window was shown while clicking".into());
            }
            match step {
                Step::Wait { duration_ms } => delay = *duration_ms,
                Step::Click {
                    button,
                    clicks,
                    position,
                    interval_ms,
                } => {
                    if position.is_some() {
                        return Err("Fixed coordinates are not supported in this experiment".into());
                    }
                    let code = match button {
                        MouseButton::Left => 0x110,
                        MouseButton::Right => 0x111,
                        MouseButton::Middle => 0x112,
                    };
                    for index in 0..*clicks {
                        if index > 0 {
                            tokio::time::sleep(Duration::from_millis(50)).await;
                        }
                        if cancel.load(Ordering::Acquire) {
                            return Ok(());
                        }
                        let press = tokio::time::timeout(
                            Duration::from_secs(2),
                            portal.notify_pointer_button(&session, code, KeyState::Pressed),
                        )
                        .await;
                        eprintln!("CI pointer press request returned: {press:?}");
                        let release = tokio::time::timeout(
                            Duration::from_secs(2),
                            portal.notify_pointer_button(&session, code, KeyState::Released),
                        )
                        .await;
                        press
                            .map_err(|_| "Pointer press timed out")?
                            .map_err(|e| e.to_string())?;
                        release
                            .map_err(|_| "Pointer release timed out")?
                            .map_err(|e| e.to_string())?;
                    }
                    delay = *interval_ms;
                }
            }
            while delay > 0 {
                let slice = delay.min(10);
                tokio::select! { biased;
                    _ = closed.next() => { eprintln!("CI observed remote session close"); return Err("Remote desktop session closed".into()); },
                    _ = tokio::time::sleep(Duration::from_millis(slice)) => {}
                }
                if cancel.load(Ordering::Acquire) {
                    return Ok(());
                }
                if window.is_visible().map_err(|e| e.to_string())? {
                    return Err("Application window was shown while clicking".into());
                }
                delay -= slice;
            }
        }
        count += 1;
        {
            let state = app.state::<AppState>();
            let mut inner = state.0.lock().map_err(|_| "State unavailable")?;
            inner.status.completed_cycles += 1;
            emit_status(app, inner.status.clone());
        }
        if count >= 2 || config.repeat.is_some_and(|n| count >= n) {
            return Ok(());
        }
    }
}
