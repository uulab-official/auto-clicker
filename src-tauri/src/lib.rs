mod engine;

use engine::{Config, MouseButton, Position, Step};
use enigo::{Button, Coordinate, Direction, Enigo, Mouse, Settings};
use serde::Serialize;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use std::time::{Duration, Instant};
use tauri::{Emitter, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
use tauri_plugin_updater::{Update, UpdaterExt};

const SHORTCUT: &str = "Control+Shift+F8";
#[derive(Clone, Serialize)]
struct Status {
    running: bool,
    completed_cycles: u64,
    error: Option<String>,
    shortcut_error: Option<String>,
}
struct Inner {
    status: Status,
    cancel: Option<Arc<AtomicBool>>,
    installing: bool,
}
struct AppState(Mutex<Inner>);
struct PendingUpdate(Mutex<Option<Update>>);

#[derive(Serialize)]
struct UpdateInfo {
    version: String,
    current_version: String,
    notes: Option<String>,
}

#[tauri::command]
async fn check_update(
    app: tauri::AppHandle,
    pending: tauri::State<'_, PendingUpdate>,
) -> Result<Option<UpdateInfo>, String> {
    *pending.0.lock().map_err(|_| "Update state unavailable")? = None;
    let update = app
        .updater()
        .map_err(|e| e.to_string())?
        .check()
        .await
        .map_err(|e| e.to_string())?;
    let info = update.as_ref().map(|u| UpdateInfo {
        version: u.version.clone(),
        current_version: u.current_version.clone(),
        notes: u.body.clone(),
    });
    *pending.0.lock().map_err(|_| "Update state unavailable")? = update;
    Ok(info)
}

struct InstallGuard(tauri::AppHandle);
impl Drop for InstallGuard {
    fn drop(&mut self) {
        let state = self.0.state::<AppState>();
        if let Ok(mut inner) = state.0.lock() {
            inner.installing = false;
        };
    }
}

#[tauri::command]
async fn install_update(
    app: tauri::AppHandle,
    pending: tauri::State<'_, PendingUpdate>,
) -> Result<(), String> {
    {
        let state = app.state::<AppState>();
        let mut inner = state.0.lock().map_err(|_| "State unavailable")?;
        if inner.status.running {
            return Err("Stop the clicker before installing an update.".into());
        }
        if inner.installing {
            return Err("An update is already being installed.".into());
        }
        inner.installing = true;
    }
    let _guard = InstallGuard(app.clone());
    let update = pending
        .0
        .lock()
        .map_err(|_| "Update state unavailable")?
        .take()
        .ok_or("Check for an update first.")?;
    update
        .download_and_install(|_, _| {}, || {})
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

fn emit_status(app: &tauri::AppHandle, status: Status) {
    let _ = app.emit("run-status", status);
}
fn sleep_interruptibly(cancel: &AtomicBool, ms: u64) -> bool {
    let until = Instant::now() + Duration::from_millis(ms);
    loop {
        if cancel.load(Ordering::Acquire) {
            return false;
        }
        let remaining = until.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return true;
        }
        std::thread::sleep(remaining.min(Duration::from_millis(10)));
    }
}
fn execute(
    config: &Config,
    cancel: &AtomicBool,
    mut cycle: impl FnMut(),
    mut click: impl FnMut(&Step) -> Result<(), String>,
) -> Result<(), String> {
    let mut completed = 0;
    loop {
        for step in &config.steps {
            if cancel.load(Ordering::Acquire) {
                return Ok(());
            }
            match step {
                Step::Wait { duration_ms } => {
                    if !sleep_interruptibly(cancel, *duration_ms) {
                        return Ok(());
                    }
                }
                Step::Click { interval_ms, .. } => {
                    click(step)?;
                    if !sleep_interruptibly(cancel, *interval_ms) {
                        return Ok(());
                    }
                }
            }
        }
        completed += 1;
        cycle();
        if config.repeat.is_some_and(|n| completed >= n) {
            return Ok(());
        }
    }
}
fn start(app: &tauri::AppHandle, config: Config) -> Result<(), String> {
    engine::validate(&config)?;
    let state = app.state::<AppState>();
    let mut inner = state.0.lock().map_err(|_| "State unavailable")?;
    if inner.status.running {
        return Err("A run is already active.".into());
    }
    if inner.installing {
        return Err("Cannot start while an update is installing.".into());
    }
    if let Some(error) = &inner.status.shortcut_error {
        return Err(format!(
            "Cannot start without a working emergency shortcut: {error}"
        ));
    }
    let cancel = Arc::new(AtomicBool::new(false));
    inner.cancel = Some(cancel.clone());
    inner.status.running = true;
    inner.status.completed_cycles = 0;
    inner.status.error = None;
    let status = inner.status.clone();
    drop(inner);
    emit_status(app, status);
    let app = app.clone();
    std::thread::spawn(move || {
        let result = (|| {
            let mut enigo = Enigo::new(&Settings::default())
                .map_err(|e| format!("Input initialization failed: {e}"))?;
            execute(
                &config,
                &cancel,
                || {
                    let state = app.state::<AppState>();
                    if let Ok(mut inner) = state.0.lock() {
                        inner.status.completed_cycles += 1;
                        emit_status(&app, inner.status.clone());
                    };
                },
                |step| {
                    if let Step::Click {
                        button,
                        clicks,
                        position,
                        ..
                    } = step
                    {
                        if let Some(pos) = position {
                            enigo
                                .move_mouse(pos.x, pos.y, Coordinate::Abs)
                                .map_err(|e| e.to_string())?;
                        }
                        let button = match button {
                            MouseButton::Left => Button::Left,
                            MouseButton::Right => Button::Right,
                            MouseButton::Middle => Button::Middle,
                        };
                        for index in 0..*clicks {
                            if cancel.load(Ordering::Acquire) {
                                break;
                            }
                            if index > 0 && !sleep_interruptibly(&cancel, 50) {
                                break;
                            }
                            enigo
                                .button(button, Direction::Click)
                                .map_err(|e| e.to_string())?;
                        }
                    }
                    Ok(())
                },
            )
        })();
        let state = app.state::<AppState>();
        if let Ok(mut inner) = state.0.lock() {
            inner.status.running = false;
            inner.status.error = result.err();
            inner.cancel = None;
            emit_status(&app, inner.status.clone());
        };
    });
    Ok(())
}
fn stop(app: &tauri::AppHandle) {
    let state = app.state::<AppState>();
    if let Ok(inner) = state.0.lock() {
        if let Some(cancel) = &inner.cancel {
            cancel.store(true, Ordering::Release);
        }
    };
}
#[tauri::command]
fn start_run(app: tauri::AppHandle, config: Config) -> Result<(), String> {
    start(&app, config)
}
#[tauri::command]
fn stop_run(app: tauri::AppHandle) {
    stop(&app);
}
#[tauri::command]
fn get_status(state: tauri::State<'_, AppState>) -> Result<Status, String> {
    Ok(state
        .0
        .lock()
        .map_err(|_| "State unavailable")?
        .status
        .clone())
}
#[tauri::command]
fn cursor_position() -> Result<Position, String> {
    let enigo = Enigo::new(&Settings::default()).map_err(|e| e.to_string())?;
    let (x, y) = enigo.location().map_err(|e| e.to_string())?;
    Ok(Position { x, y })
}
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(AppState(Mutex::new(Inner {
            status: Status {
                running: false,
                completed_cycles: 0,
                error: None,
                shortcut_error: None,
            },
            cancel: None,
            installing: false,
        })))
        .manage(PendingUpdate(Mutex::new(None)))
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _, event| {
                    if event.state != ShortcutState::Pressed {
                        return;
                    }
                    stop(app);
                })
                .build(),
        )
        .setup(|app| {
            if let Err(e) = app.global_shortcut().register(SHORTCUT) {
                app.state::<AppState>()
                    .0
                    .lock()
                    .unwrap()
                    .status
                    .shortcut_error = Some(e.to_string());
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            start_run,
            stop_run,
            get_status,
            cursor_position,
            check_update,
            install_update
        ])
        .run(tauri::generate_context!())
        .expect("error while running application");
}

#[cfg(test)]
mod run_tests {
    use super::*;
    #[test]
    fn executes_steps_in_order_for_each_cycle() {
        let config = Config {
            steps: vec![
                Step::Click {
                    button: MouseButton::Left,
                    clicks: 1,
                    position: Some(Position { x: 1, y: 2 }),
                    interval_ms: 10,
                },
                Step::Click {
                    button: MouseButton::Right,
                    clicks: 1,
                    position: None,
                    interval_ms: 10,
                },
            ],
            repeat: Some(2),
        };
        let mut buttons = Vec::new();
        let mut cycles = 0;
        execute(
            &config,
            &AtomicBool::new(false),
            || cycles += 1,
            |step| {
                if let Step::Click { button, .. } = step {
                    buttons.push(format!("{button:?}"));
                }
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(buttons, ["Left", "Right", "Left", "Right"]);
        assert_eq!(cycles, 2);
    }
    #[test]
    fn cancelled_run_does_not_click() {
        let config = Config {
            steps: vec![Step::Click {
                button: MouseButton::Left,
                clicks: 1,
                position: None,
                interval_ms: 10,
            }],
            repeat: None,
        };
        let mut clicks = 0;
        execute(
            &config,
            &AtomicBool::new(true),
            || {},
            |_| {
                clicks += 1;
                Ok(())
            },
        )
        .unwrap();
        assert_eq!(clicks, 0);
    }

    #[test]
    fn cancellation_interrupts_long_wait() {
        let cancel = Arc::new(AtomicBool::new(false));
        let signal = cancel.clone();
        let worker = std::thread::spawn(move || sleep_interruptibly(&signal, 60_000));
        cancel.store(true, Ordering::Release);
        assert!(!worker.join().unwrap());
    }
}
