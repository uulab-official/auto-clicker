#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && -n "${RUNNER_TEMP:-}" ]] || exit 1
work=$(mktemp -d "$RUNNER_TEMP/gnome-portal.XXXXXX")
shell_pid='' probe_pid='' pipewire_pid='' keyboard_pid=''
trap 'cat "$work/probe.log" "$work/keyboard.log" "$work/shell.log" 2>/dev/null || true; /usr/bin/python3 experiments/wayland-portal/list_accessible.py || true' ERR
cleanup() {
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
timeout 35s gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop >"$work/interfaces" || { cat "$work/shell.log"; exit 1; }
grep -E 'interface org.freedesktop.portal.(GlobalShortcuts|RemoteDesktop)' "$work/interfaces" || true
echo '--- Approve actual GNOME shortcut in disposable desktop ---'
WAYLAND_PROTOTYPE_WAIT_STOP=1 experiments/wayland-portal/target/debug/wayland-portal-prototype >"$work/probe.log" 2>&1 & probe_pid=$!
sleep 5
/usr/bin/python3 experiments/wayland-portal/gnome_approve.py gnome-control-center-global-shortcuts-provider 'Add Keyboard Shortcuts' Add
for _ in $(seq 1 50); do grep -q 'Portal assigned emergency stop' "$work/probe.log" && break; kill -0 "$probe_pid" || { cat "$work/probe.log"; exit 1; }; sleep .2; done
cat "$work/probe.log"
grep -q 'Portal assigned emergency stop' "$work/probe.log"
echo '--- Approve one test keyboard session in disposable desktop ---'
WAYLAND_PROTOTYPE_KEYBOARD_TEST=1 experiments/wayland-portal/target/debug/wayland-portal-prototype >"$work/keyboard.log" 2>&1 & keyboard_pid=$!
sleep 5
/usr/bin/python3 experiments/wayland-portal/gnome_approve.py xdg-desktop-portal-gnome 'Remote Desktop' Share
for _ in $(seq 1 50); do grep -q ACTUAL_SHORTCUT_ACTIVATED "$work/probe.log" && break; sleep .2; done
cat "$work/keyboard.log" "$work/probe.log" "$work/shell.log"
grep -q ACTUAL_SHORTCUT_ACTIVATED "$work/probe.log"
wait "$keyboard_pid"
keyboard_pid=''
wait "$probe_pid"
probe_pid=''
