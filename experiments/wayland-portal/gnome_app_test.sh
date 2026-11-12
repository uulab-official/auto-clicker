#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && -n "${RUNNER_TEMP:-}" ]] || exit 1
work=$(mktemp -d "$RUNNER_TEMP/gnome-portal.XXXXXX")
shell_pid='' probe_pid='' pipewire_pid='' keyboard_pid='' app_pid='' target_pid=''
trap 'cat "$work/app.log" "$work/target.log" "$work/keyboard.log" "$work/shell.log" 2>/dev/null || true; /usr/bin/python3 experiments/wayland-portal/list_accessible.py || true' ERR
cleanup() {
  for pid in "$app_pid" "$target_pid"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  [[ -z "$keyboard_pid" ]] || kill "$keyboard_pid" 2>/dev/null || true
  [[ -z "$probe_pid" ]] || kill "$probe_pid" 2>/dev/null || true
  [[ -z "$pipewire_pid" ]] || kill "$pipewire_pid" 2>/dev/null || true
  [[ -z "$shell_pid" ]] || kill "$shell_pid" 2>/dev/null || true
  if mountpoint -q "$work/runtime/doc"; then fusermount -u "$work/runtime/doc" || true; fi
  rm -rf "$work" || true
}
trap cleanup EXIT
mkdir -m 700 "$work/runtime"
mkdir -p "$work/data/applications" "$work/config" "$work/cache"
cat >"$work/data/applications/kr.co.uulab.autoclicker.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Auto Clicker Portal Prototype
Exec=$PWD/experiments/wayland-portal/target/debug/wayland-portal-prototype
Terminal=false
EOF
export XDG_RUNTIME_DIR="$work/runtime" XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export WAYLAND_DISPLAY=wayland-ci XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome
export NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge LANG=C.UTF-8 LIBGL_ALWAYS_SOFTWARE=1
unset DISPLAY WAYLAND_PROTOTYPE_ALLOW_SINGLE_CLICK
dbus-update-activation-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_DATA_HOME XDG_CONFIG_HOME NO_AT_BRIDGE
gnome-shell --headless --virtual-monitor=800x600 --wayland-display="$WAYLAND_DISPLAY" >"$work/shell.log" 2>&1 & shell_pid=$!
for _ in $(seq 1 60); do [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break; kill -0 "$shell_pid" || { cat "$work/shell.log"; exit 1; }; sleep 1; done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || { cat "$work/shell.log"; exit 1; }
pipewire >"$work/pipewire.log" 2>&1 & pipewire_pid=$!
echo '--- Actual GNOME desktop portal interfaces ---'
portal_ready=''
for _ in $(seq 1 8); do
  if timeout 35s gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop >"$work/interfaces"; then portal_ready=1; break; fi
  sleep 3
done
[[ "$portal_ready" == 1 ]] || { cat "$work/shell.log"; exit 1; }
grep -E 'interface org.freedesktop.portal.(GlobalShortcuts|RemoteDesktop)' "$work/interfaces" || true
echo '--- Start experimental Tauri app and approve shortcut ---'
AUTOCLICKER_EXPERIMENTAL_WAYLAND=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=wayland src-tauri/target/release/auto-clicker >"$work/app.log" 2>&1 & app_pid=$!
sleep 5
/usr/bin/python3 experiments/wayland-portal/gnome_approve.py gnome-control-center-global-shortcuts-provider 'Add Keyboard Shortcuts' Add
echo '--- Prepare isolated virtual keyboard ---'
WAYLAND_PROTOTYPE_TARGET_READY="$XDG_RUNTIME_DIR/target-ready" WAYLAND_PROTOTYPE_WAIT_FILE="$XDG_RUNTIME_DIR/send-key" WAYLAND_PROTOTYPE_KEYBOARD_TEST=1 experiments/wayland-portal/target/debug/wayland-portal-prototype >"$work/keyboard.log" 2>&1 & keyboard_pid=$!
sleep 5
/usr/bin/python3 experiments/wayland-portal/gnome_approve.py xdg-desktop-portal-gnome 'Remote Desktop' --enable-remote
/usr/bin/python3 experiments/wayland-portal/gnome_approve.py xdg-desktop-portal-gnome 'Remote Desktop' Share
echo '--- Start test target and verify actual click followed by actual stop ---'
/usr/bin/python3 experiments/wayland-portal/sway_target.py "$work/received" >"$work/target.log" 2>&1 & target_pid=$!
for _ in $(seq 1 100); do grep -q TARGET_READY "$work/target.log" && break; kill -0 "$target_pid" || { cat "$work/target.log"; exit 1; }; sleep .1; done
touch "$XDG_RUNTIME_DIR/target-ready"
for _ in $(seq 1 100); do [[ -f "$XDG_RUNTIME_DIR/pointer-ready" ]] && break; kill -0 "$keyboard_pid" || { cat "$work/keyboard.log"; exit 1; }; sleep .1; done
[[ -f "$XDG_RUNTIME_DIR/pointer-ready" ]]
if [[ "${GNOME_TEST_REVOKE:-}" == 1 ]]; then
  /usr/bin/python3 experiments/wayland-portal/gnome_revoke_driver.py "$app_pid" "$work/received" "$work/app.log"
  kill "$keyboard_pid" 2>/dev/null || true
  wait "$keyboard_pid" || true; keyboard_pid=''
  cat "$work/app.log" "$work/keyboard.log" "$work/target.log"
  exit 0
fi
/usr/bin/python3 experiments/wayland-portal/gnome_tauri_driver.py "$app_pid" "$work/received" "$XDG_RUNTIME_DIR/send-key"
wait "$keyboard_pid"; keyboard_pid=''
cat "$work/app.log" "$work/keyboard.log" "$work/target.log"
grep -q 'CI Wayland app window hidden' "$work/app.log"
grep -q 'CI Wayland window restore requested' "$work/app.log"
grep -q 'CI Wayland window visibility after restore: Ok(true)' "$work/app.log"
grep -q 'CI observed emergency shortcut activation' "$work/app.log"
grep -q 'CI Wayland run result: Ok(())' "$work/app.log"
