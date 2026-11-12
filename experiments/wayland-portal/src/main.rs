//! Isolated-CI-only portal probe. It is not linked to the shipping application.
//! This binary creates no application window, so there is no UI window to hide.
//! Full application integration must hide/restore the real window and verify it.

use ashpd::desktop::{
    global_shortcuts::{GlobalShortcuts, NewShortcut},
    remote_desktop::{DeviceType, KeyState, RemoteDesktop},
    PersistMode,
};
use futures_util::StreamExt;
use std::{env, error::Error, os::unix::fs::FileTypeExt, path::Path, time::Duration};
use wayland_portal_prototype::SafetyGate;

type Result<T> = std::result::Result<T, Box<dyn Error>>;
const STOP: &str = "emergency-stop";

fn require_isolated_runner() -> Result<()> {
    let runtime = env::var("XDG_RUNTIME_DIR")?;
    let temp = env::var("RUNNER_TEMP")?;
    if env::var("CI").as_deref() != Ok("true")
        || env::var("GITHUB_ACTIONS").as_deref() != Ok("true")
        || env::var("WAYLAND_DISPLAY").as_deref() != Ok("wayland-ci")
        || !Path::new(&runtime).starts_with(Path::new(&temp))
        || !std::fs::metadata(Path::new(&runtime).join("wayland-ci"))?
            .file_type()
            .is_socket()
    {
        return Err("This experimental probe only runs inside its isolated GitHub runner".into());
    }
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    require_isolated_runner()?;
    match tokio::time::timeout(Duration::from_secs(90), probe()).await {
        Ok(result) => result,
        Err(_) => Err("Portal request timed out; no click was sent".into()),
    }
}

async fn probe() -> Result<()> {
    if env::var("WAYLAND_PROTOTYPE_KEYBOARD_TEST").as_deref() == Ok("1") {
        let remote = RemoteDesktop::new().await?;
        let session = remote.create_session().await?;
        let device_types = if env::var("WAYLAND_PROTOTYPE_WAIT_FILE").is_ok() {
            DeviceType::Keyboard | DeviceType::Pointer
        } else {
            DeviceType::Keyboard.into()
        };
        remote
            .select_devices(&session, device_types, None, PersistMode::DoNot)
            .await?
            .response()?;
        println!("Requesting isolated keyboard permission");
        let selected = remote.start(&session, None).await?.response()?;
        if !selected.devices().contains(DeviceType::Keyboard) {
            return Err("Keyboard control was not granted".into());
        }
        if selected.devices().contains(DeviceType::Pointer) {
            remote.notify_pointer_motion(&session, 150.0, 150.0).await?;
        }
        if let Ok(marker) = env::var("WAYLAND_PROTOTYPE_WAIT_FILE") {
            let path = Path::new(&marker);
            if !path.starts_with(env::var("XDG_RUNTIME_DIR")?) {
                return Err("Marker must be inside the isolated runtime".into());
            }
            println!("Isolated virtual keyboard ready and waiting for test marker");
            tokio::time::timeout(Duration::from_secs(20), async {
                while !path.exists() {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await?;
        }
        println!("Isolated virtual keyboard granted; sending Ctrl+Shift+F8 once");
        for key in [29, 42, 66] {
            remote
                .notify_keyboard_keycode(&session, key, KeyState::Pressed)
                .await?;
        }
        for key in [66, 42, 29] {
            remote
                .notify_keyboard_keycode(&session, key, KeyState::Released)
                .await?;
        }
        tokio::time::sleep(Duration::from_secs(2)).await;
        return Ok(());
    }
    if env::var("WAYLAND_PROTOTYPE_REMOTE_PREFLIGHT").as_deref() == Ok("1") {
        let remote = RemoteDesktop::new().await?;
        let control = remote.create_session().await?;
        remote
            .select_devices(
                &control,
                DeviceType::Pointer.into(),
                None,
                PersistMode::DoNot,
            )
            .await?
            .response()?;
        println!(
            "Requesting pointer permission from the actual portal; no pointer events will be sent"
        );
        let selected = remote.start(&control, None).await?.response()?;
        println!("Actual portal returned devices: {:?}", selected.devices());
        return Ok(());
    }
    let mut gate = SafetyGate::default();
    let shortcut_portal = GlobalShortcuts::new().await?;
    // Unsandboxed apps may need to associate this D-Bus connection with a
    // matching installed desktop file. Older portal versions lack Registry.
    let registry = zbus::Proxy::new(
        shortcut_portal.connection(),
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.host.portal.Registry",
    )
    .await?;
    let options: std::collections::HashMap<&str, zbus::zvariant::Value<'_>> =
        std::collections::HashMap::new();
    let registered: std::result::Result<(), _> = registry
        .call("Register", &("kr.co.uulab.autoclicker", &options))
        .await;
    println!("Host application registration result: {:?}", registered);
    let shortcuts = shortcut_portal.create_session().await?;
    // Signals are subscribed before binding so a revocation cannot be missed.
    let activated = shortcut_portal.receive_activated().await?;
    let changed = shortcut_portal.receive_shortcuts_changed().await?;
    let shortcut_closed = shortcuts.receive_closed().await?;
    tokio::pin!(activated, changed, shortcut_closed);
    let expected_session: String = serde_json::from_value(serde_json::to_value(&shortcuts)?)?;
    let requested =
        [NewShortcut::new(STOP, "Emergency stop").preferred_trigger(Some("CTRL+SHIFT+F8"))];
    let bound = shortcut_portal
        .bind_shortcuts(&shortcuts, &requested, None)
        .await?
        .response()?;
    println!("Portal returned shortcut bindings: {:?}", bound.shortcuts());
    let assigned = bound
        .shortcuts()
        .iter()
        .find(|shortcut| shortcut.id() == STOP && !shortcut.trigger_description().trim().is_empty())
        .ok_or("The compositor did not bind a usable emergency shortcut")?;
    println!(
        "Portal assigned emergency stop: {}",
        assigned.trigger_description()
    );
    if env::var("WAYLAND_PROTOTYPE_WAIT_STOP").as_deref() == Ok("1") {
        while let Some(signal) = activated.next().await {
            if signal.session_handle().as_str() == expected_session && signal.shortcut_id() == STOP
            {
                println!("ACTUAL_SHORTCUT_ACTIVATED");
                return Ok(());
            }
        }
        return Err("Shortcut event stream ended".into());
    }
    gate.set_shortcut_bound(true);

    let remote = RemoteDesktop::new().await?;
    let control = remote.create_session().await?;
    let control_closed = control.receive_closed().await?;
    tokio::pin!(control_closed);
    remote
        .select_devices(
            &control,
            DeviceType::Pointer.into(),
            None,
            PersistMode::DoNot,
        )
        .await?
        .response()?;
    let selected = remote.start(&control, None).await?.response()?;
    if !selected.devices().contains(DeviceType::Pointer) {
        return Err("Pointer control was not granted".into());
    }
    gate.set_pointer_granted(true);
    // No window exists in this standalone probe. The production app must
    // actively hide its real window and independently confirm that state.
    gate.set_app_hidden(true);
    println!("All restricted preconditions met; no app window exists");

    // Require an explicit opt-in in addition to runner isolation. There is no
    // coordinate selection or continuous clicking in this experiment.
    if env::var("WAYLAND_PROTOTYPE_ALLOW_SINGLE_CLICK").as_deref() != Ok("1") {
        return Ok(());
    }
    let delay = tokio::time::sleep(Duration::from_secs(2));
    tokio::pin!(delay);
    loop {
        tokio::select! {
            biased;
            signal = activated.next() => {
                match signal {
                    Some(signal) if signal.session_handle().as_str() == expected_session && signal.shortcut_id() == STOP => {
                        gate.stop();
                        println!("Emergency stop received; no click sent");
                        return Ok(());
                    }
                    None => return Err("Shortcut event stream ended".into()),
                    _ => {}
                }
            }
            signal = changed.next() => {
                match signal {
                    Some(signal) if signal.session_handle().as_str() == expected_session => {
                        if !signal.shortcuts().iter().any(|s| s.id() == STOP && !s.trigger_description().trim().is_empty()) {
                            gate.stop();
                            return Err("Emergency shortcut was revoked".into());
                        }
                    }
                    None => return Err("Shortcut change stream ended".into()),
                    _ => {}
                }
            }
            _ = shortcut_closed.next() => { gate.stop(); return Err("Shortcut session closed".into()); }
            _ = control_closed.next() => { gate.stop(); return Err("Remote control session closed".into()); }
            _ = &mut delay => {
                if !gate.can_click() { return Err("Safety preconditions were lost".into()); }
                // BTN_LEFT is the Linux evdev code. Always attempt a release,
                // including after a press error, to avoid a stuck button.
                let press = remote.notify_pointer_button(&control, 0x110, KeyState::Pressed).await;
                let release = remote.notify_pointer_button(&control, 0x110, KeyState::Released).await;
                press?;
                release?;
                println!("Sent one pointer click to the isolated test target");
                return Ok(());
            }
        }
    }
}
