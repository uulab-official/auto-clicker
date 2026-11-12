//! Identify the topmost X11 window at a screen position without moving the pointer.
//!
//! Window managers commonly wrap a client in a separate frame window.  Compare
//! the top-level children of the root, rather than comparing client IDs directly.

use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::sync::{Mutex, OnceLock};
use tauri::WebviewWindow;
use x11rb::connection::Connection;
use x11rb::protocol::xproto::ConnectionExt;
use x11rb::rust_connection::RustConnection;

// Reuse a separate X connection rather than opening one for every click. The
// connection is never accessed by GTK and is serialized across click workers.
static CONNECTION: OnceLock<Mutex<Option<RustConnection>>> = OnceLock::new();

/// Return `None` on any uncertainty so the caller can keep the safe geometric
/// fallback. No input events are injected, and the pointer is never moved.
pub(crate) fn target_is_app(window: &WebviewWindow, x: f64, y: f64) -> Option<bool> {
    if !x.is_finite() || !y.is_finite() || x < f64::from(i16::MIN) || x > f64::from(i16::MAX)
        || y < f64::from(i16::MIN) || y > f64::from(i16::MAX)
    {
        return None;
    }
    let app = match window.window_handle().ok()?.as_raw() {
        RawWindowHandle::Xlib(handle) => u32::try_from(handle.window).ok()?,
        RawWindowHandle::Xcb(handle) => handle.window.get(),
        // Never apply an X11 window ID to a native Wayland surface.
        _ => return None,
    };
    let mut connection = CONNECTION.get_or_init(|| Mutex::new(None)).lock().ok()?;
    if connection.is_none() {
        *connection = Some(x11rb::connect(None).ok()?.0);
    }
    let result = query_target(connection.as_ref()?, app, x as i16, y as i16);
    if result.is_none() {
        // A restarted X server, invalidated window, or failed connection must
        // not leave a permanently broken connection in the process.
        *connection = None;
    }
    result
}

fn query_target(conn: &RustConnection, app: u32, x: i16, y: i16) -> Option<bool> {
    if app == 0 {
        return None;
    }
    let mut child = app;
    let mut root = 0;
    // Parent traversal is bounded to avoid hanging on malformed window trees.
    for _ in 0..64 {
        let tree = conn.query_tree(child).ok()?.reply().ok()?;
        if tree.root == 0 || tree.parent == 0 {
            return None;
        }
        root = tree.root;
        if tree.parent == root {
            break;
        }
        if tree.parent == child {
            return None;
        }
        child = tree.parent;
    }
    if root == 0 {
        return None;
    }
    // Ensure traversal did reach the root, including if the depth limit was hit.
    if conn.query_tree(child).ok()?.reply().ok()?.parent != root {
        return None;
    }
    let hit = conn.translate_coordinates(root, root, x, y).ok()?.reply().ok()?;
    if !hit.same_screen {
        return None;
    }
    Some(hit.child == child)
}

#[cfg(test)]
mod tests {
    use super::*;
    use x11rb::protocol::xproto::{
        ConfigureWindowAux, CreateWindowAux, StackMode, WindowClass,
    };
    use x11rb::COPY_DEPTH_FROM_PARENT;

    // Run against an isolated Xvfb server, never a user's desktop.
    #[test]
    fn overlapping_client_and_window_manager_frame() {
        if std::env::var_os("X11_HIT_TEST_REQUIRED").is_none() {
            return;
        }
        let (conn, screen) = x11rb::connect(None).expect("isolated X server is required");
        let root = conn.setup().roots[screen].root;
        let create = |parent, x, y, width, height| {
            let id = conn.generate_id().unwrap();
            conn.create_window(
                COPY_DEPTH_FROM_PARENT,
                id,
                parent,
                x,
                y,
                width,
                height,
                0,
                WindowClass::INPUT_OUTPUT,
                0,
                &CreateWindowAux::new(),
            ).unwrap().check().unwrap();
            conn.map_window(id).unwrap().check().unwrap();
            id
        };
        // The frame models a reparenting window manager. The target covers
        // the same point, and is raised after mapping, as a real foreground app.
        let frame = create(root, 20, 20, 200, 200);
        let client = create(frame, 0, 0, 200, 200);
        let target = create(root, 20, 20, 200, 200);
        conn.configure_window(target, &ConfigureWindowAux::new().stack_mode(StackMode::ABOVE))
            .unwrap().check().unwrap();
        assert_eq!(query_target(&conn, client, 70, 70), Some(false));
        conn.configure_window(frame, &ConfigureWindowAux::new().stack_mode(StackMode::ABOVE))
            .unwrap().check().unwrap();
        assert_eq!(query_target(&conn, client, 70, 70), Some(true));
        assert_eq!(query_target(&conn, client, 300, 300), Some(false));
        assert_eq!(query_target(&conn, 0, 70, 70), None);
    }
}
