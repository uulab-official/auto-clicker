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
#[cfg(target_os = "macos")]
const ALTERNATE_SHORTCUT: &str = "Control+Shift+Escape";

struct ShortcutRegistration {
    available: Vec<String>,
    error: Option<String>,
    warning: Option<String>,
}

fn summarize_shortcut_results(results: Vec<(&str, Result<(), String>)>) -> ShortcutRegistration {
    let mut available = Vec::new();
    let mut failures = Vec::new();
    for (label, result) in results {
        match result {
            Ok(()) => available.push(label.to_owned()),
            Err(error) => failures.push(format!("{label}: {error}")),
        }
    }
    let details = failures.join("; ");
    if available.is_empty() {
        ShortcutRegistration {
            available,
            error: Some(if details.is_empty() {
                "No emergency shortcut is available.".into()
            } else {
                details
            }),
            warning: None,
        }
    } else {
        ShortcutRegistration {
            available,
            error: None,
            warning: (!details.is_empty()).then_some(details),
        }
    }
}
#[cfg(any(target_os = "linux", test))]
fn is_wayland_session(session_type: Option<&str>, wayland_display: Option<&str>) -> bool {
    match session_type.filter(|s| !s.is_empty()) {
        Some(value) if value.eq_ignore_ascii_case("wayland") => true,
        Some(value) if value.eq_ignore_ascii_case("x11") => false,
        _ => wayland_display.is_some_and(|value| !value.is_empty()),
    }
}
#[derive(Clone, Serialize)]
struct Status {
    running: bool,
    completed_cycles: u64,
    error: Option<String>,
    shortcut_error: Option<String>,
    shortcut_warning: Option<String>,
    available_shortcuts: Vec<String>,
    paused_over_app: bool,
}
struct Inner {
    status: Status,
    cancel: Option<Arc<AtomicBool>>,
    installing: bool,
}
struct AppState(Mutex<Inner>);
struct UpdateSlot<T> {
    generation: u64,
    candidate: Option<(String, T)>,
}
impl<T> Default for UpdateSlot<T> {
    fn default() -> Self {
        Self {
            generation: 0,
            candidate: None,
        }
    }
}
impl<T> UpdateSlot<T> {
    fn begin_check(&mut self) -> u64 {
        self.generation = self.generation.wrapping_add(1);
        self.candidate = None;
        self.generation
    }
    fn finish_check(&mut self, generation: u64, candidate: Option<(String, T)>) -> bool {
        if generation != self.generation {
            return false;
        }
        self.candidate = candidate;
        true
    }
    fn take_approved(&mut self, version: &str) -> Result<T, String> {
        match &self.candidate {
            Some((candidate_version, _)) if candidate_version == version => {}
            _ => return Err("The selected update is no longer available; check again.".into()),
        }
        Ok(self.candidate.take().expect("candidate checked above").1)
    }
}
struct PendingUpdate(Mutex<UpdateSlot<Update>>);

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
    let generation = pending
        .0
        .lock()
        .map_err(|_| "Update state unavailable")?
        .begin_check();
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
    if !pending
        .0
        .lock()
        .map_err(|_| "Update state unavailable")?
        .finish_check(generation, update.map(|u| (u.version.clone(), u)))
    {
        return Err("This update check was superseded by a newer request.".into());
    }
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
    expected_version: String,
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
        .take_approved(&expected_version)?;
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
fn point_in_rect(x: f64, y: f64, left: i32, top: i32, width: u32, height: u32) -> bool {
    let (left, top) = (f64::from(left), f64::from(top));
    x >= left && y >= top && x < left + f64::from(width) && y < top + f64::from(height)
}
// A click landing on this app would press its own controls (for example the
// Stop button that replaced Start under the pointer), ending the run at once.
fn pointer_over_app(app: &tauri::AppHandle) -> bool {
    let Some(window) = app.get_webview_window("main") else {
        return false;
    };
    if !window.is_visible().unwrap_or(false)
        || window.is_minimized().unwrap_or(false)
        || !window.is_focused().unwrap_or(false)
    {
        return false;
    }
    match (window.cursor_position(), window.outer_position(), window.outer_size()) {
        (Ok(cursor), Ok(pos), Ok(size)) => {
            point_in_rect(cursor.x, cursor.y, pos.x, pos.y, size.width, size.height)
        }
        _ => false,
    }
}
fn set_paused_over_app(app: &tauri::AppHandle, paused: bool) {
    let state = app.state::<AppState>();
    if let Ok(mut inner) = state.0.lock() {
        if inner.status.paused_over_app != paused {
            inner.status.paused_over_app = paused;
            emit_status(app, inner.status.clone());
        }
    };
}
fn position_matches(target: Position, actual: (i32, i32)) -> bool {
    (i64::from(target.x) - i64::from(actual.0)).abs() <= 2
        && (i64::from(target.y) - i64::from(actual.1)).abs() <= 2
}
fn execute(
    config: &Config,
    cancel: &AtomicBool,
    mut cycle: impl FnMut(),
    mut click: impl FnMut(&Step) -> Result<(), String>,
) -> Result<(), String> {
    if !sleep_interruptibly(cancel, config.start_delay_ms) {
        return Ok(());
    }
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
    inner.status.paused_over_app = false;
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
                            if cancel.load(Ordering::Acquire) {
                                return Ok(());
                            }
                            enigo
                                .move_mouse(pos.x, pos.y, Coordinate::Abs)
                                .map_err(|e| e.to_string())?;
                            // Backends may clamp an unavailable display or reject a move silently.
                            // Give the OS time to process the move, but never click at a wrong point.
                            let mut matched = false;
                            for attempt in 0..=10 {
                                if cancel.load(Ordering::Acquire) {
                                    return Ok(());
                                }
                                let actual = enigo.location().map_err(|e| e.to_string())?;
                                if position_matches(*pos, actual) {
                                    matched = true;
                                    break;
                                }
                                if attempt < 10 && !sleep_interruptibly(&cancel, 10) {
                                    return Ok(());
                                }
                            }
                            if !matched {
                                return Err(format!("Could not move to ({}, {}). Check the display layout or permissions; this step was not clicked.", pos.x, pos.y));
                            }
                        }
                        let over_app = pointer_over_app(&app);
                        set_paused_over_app(&app, over_app);
                        if over_app {
                            return Ok(());
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
            inner.status.paused_over_app = false;
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
                shortcut_warning: None,
                available_shortcuts: Vec::new(),
                paused_over_app: false,
            },
            cancel: None,
            installing: false,
        })))
        .manage(PendingUpdate(Mutex::new(UpdateSlot::default())))
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            #[cfg(target_os = "linux")]
            let unsafe_session = is_wayland_session(
                std::env::var("XDG_SESSION_TYPE").ok().as_deref(),
                std::env::var("WAYLAND_DISPLAY").ok().as_deref(),
            );
            #[cfg(not(target_os = "linux"))]
            let unsafe_session = false;

            let registration = if unsafe_session {
                ShortcutRegistration {
                    available: Vec::new(),
                    error: Some("Wayland global emergency shortcuts are not supported. Sign in to an X11 session to run the clicker.".to_string()),
                    warning: None,
                }
            } else {
                let plugin_result = app.handle().plugin(
                    tauri_plugin_global_shortcut::Builder::new()
                        .with_handler(|app, _, event| {
                            if event.state == ShortcutState::Pressed { stop(app); }
                        })
                        .build(),
                );
                match plugin_result {
                    Ok(()) => {
                        let first = ("Ctrl+Shift+F8", app.global_shortcut().register(SHORTCUT).map_err(|e| e.to_string()));
                        #[cfg(target_os = "macos")]
                        let results = vec![first, ("Ctrl+Shift+Escape", app.global_shortcut().register(ALTERNATE_SHORTCUT).map_err(|e| e.to_string()))];
                        #[cfg(not(target_os = "macos"))]
                        let results = vec![first];
                        summarize_shortcut_results(results)
                    }
                    Err(error) => ShortcutRegistration { available: Vec::new(), error: Some(error.to_string()), warning: None },
                }
            };
            {
                let state = app.state::<AppState>();
                let mut inner = state.0.lock().unwrap();
                inner.status.shortcut_error = registration.error;
                inner.status.shortcut_warning = registration.warning;
                inner.status.available_shortcuts = registration.available;
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
    fn point_in_rect_covers_window_bounds_only() {
        assert!(point_in_rect(100.0, 200.0, 100, 200, 50, 40));
        assert!(point_in_rect(149.5, 239.5, 100, 200, 50, 40));
        assert!(!point_in_rect(150.0, 220.0, 100, 200, 50, 40));
        assert!(!point_in_rect(120.0, 199.9, 100, 200, 50, 40));
        assert!(point_in_rect(-1500.0, 10.0, -1920, 0, 1920, 1080));
    }
    #[test]
    fn shortcut_registration_requires_one_available_and_reports_partial_failure() {
        let all = summarize_shortcut_results(vec![
            ("Ctrl+Shift+F8", Ok(())),
            ("Ctrl+Shift+Escape", Ok(())),
        ]);
        assert_eq!(all.available, ["Ctrl+Shift+F8", "Ctrl+Shift+Escape"]);
        assert!(all.error.is_none() && all.warning.is_none());

        let partial = summarize_shortcut_results(vec![
            ("Ctrl+Shift+F8", Err("reserved".into())),
            ("Ctrl+Shift+Escape", Ok(())),
        ]);
        assert_eq!(partial.available, ["Ctrl+Shift+Escape"]);
        assert!(partial.error.is_none());
        assert!(partial.warning.unwrap().contains("Ctrl+Shift+F8: reserved"));

        let alternate_conflict = summarize_shortcut_results(vec![
            ("Ctrl+Shift+F8", Ok(())),
            ("Ctrl+Shift+Escape", Err("conflict".into())),
        ]);
        assert_eq!(alternate_conflict.available, ["Ctrl+Shift+F8"]);
        assert!(alternate_conflict.error.is_none());
        assert!(alternate_conflict
            .warning
            .unwrap()
            .contains("Ctrl+Shift+Escape: conflict"));

        let none = summarize_shortcut_results(vec![
            ("Ctrl+Shift+F8", Err("reserved".into())),
            ("Ctrl+Shift+Escape", Err("conflict".into())),
        ]);
        assert!(none.available.is_empty() && none.warning.is_none());
        let error = none.error.unwrap();
        assert!(error.contains("Ctrl+Shift+F8: reserved"));
        assert!(error.contains("Ctrl+Shift+Escape: conflict"));
    }
    #[test]
    fn start_delay_is_interruptible_before_first_click() {
        let config: Config = serde_json::from_str(r#"{"steps":[{"kind":"click","button":"left","clicks":1,"position":null,"interval_ms":10}],"repeat":1,"start_delay_ms":60000}"#).unwrap();
        let cancel = Arc::new(AtomicBool::new(false));
        let signal = cancel.clone();
        let (tx, rx) = std::sync::mpsc::channel();
        let worker = std::thread::spawn(move || {
            execute(
                &config,
                &signal,
                || {},
                |_| {
                    tx.send(()).unwrap();
                    Ok(())
                },
            )
            .unwrap();
        });
        assert!(rx.recv_timeout(Duration::from_millis(50)).is_err());
        cancel.store(true, Ordering::Release);
        worker.join().unwrap();
        assert!(rx.try_recv().is_err());
    }

    #[test]
    fn start_delay_occurs_before_the_first_click() {
        let config: Config = serde_json::from_str(r#"{"steps":[{"kind":"click","button":"left","clicks":1,"position":null,"interval_ms":10}],"repeat":1,"start_delay_ms":100}"#).unwrap();
        let started = Instant::now();
        let mut clicked_after = None;
        execute(
            &config,
            &AtomicBool::new(false),
            || {},
            |_| {
                clicked_after = Some(started.elapsed());
                Ok(())
            },
        )
        .unwrap();
        assert!(clicked_after.unwrap() >= Duration::from_millis(100));
    }
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
            start_delay_ms: 0,
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
            start_delay_ms: 0,
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

    #[test]
    fn older_update_check_cannot_replace_newer_result() {
        let mut pending = UpdateSlot::<u8>::default();
        let older = pending.begin_check();
        let newer = pending.begin_check();
        assert!(pending.finish_check(newer, Some(("2.0".into(), 2))));
        assert!(!pending.finish_check(older, Some(("1.5".into(), 1))));
        assert_eq!(pending.take_approved("2.0").unwrap(), 2);
    }

    #[test]
    fn installation_requires_exactly_the_approved_version() {
        let mut pending = UpdateSlot::<u8>::default();
        let check = pending.begin_check();
        pending.finish_check(check, Some(("2.0".into(), 2)));
        assert!(pending.take_approved("1.5").is_err());
        assert_eq!(pending.take_approved("2.0").unwrap(), 2);
    }

    #[test]
    fn position_mismatch_is_rejected_including_extreme_coordinates() {
        assert!(position_matches(
            Position { x: -1920, y: 300 },
            (-1920, 301)
        ));
        assert!(!position_matches(Position { x: -1920, y: 300 }, (0, 300)));
        assert!(!position_matches(
            Position {
                x: i32::MIN,
                y: i32::MAX
            },
            (i32::MAX, i32::MIN)
        ));
    }

    #[test]
    fn wayland_session_is_not_mistaken_for_x11() {
        assert!(is_wayland_session(Some("wayland"), None));
        assert!(is_wayland_session(None, Some("wayland-0")));
        assert!(is_wayland_session(Some("tty"), Some("wayland-0")));
        assert!(is_wayland_session(Some("unspecified"), Some("wayland-0")));
        assert!(!is_wayland_session(Some("tty"), None));
        assert!(!is_wayland_session(Some("x11"), Some("wayland-0")));
        assert!(!is_wayland_session(None, None));
    }
}
