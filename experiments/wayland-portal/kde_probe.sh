#!/usr/bin/env bash
# Read-only capability/permission-dialog probe in a private virtual KWin.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && -n "${RUNNER_TEMP:-}" ]] || exit 1
work=$(mktemp -d "$RUNNER_TEMP/kde-portal.XXXXXX")
kwin_pid='' probe_pid=''
cleanup() {
  [[ -z "$probe_pid" ]] || kill "$probe_pid" 2>/dev/null || true
  [[ -z "$kwin_pid" ]] || kill "$kwin_pid" 2>/dev/null || true
  if mountpoint -q "$work/runtime/doc"; then fusermount -u "$work/runtime/doc" || true; fi
  rm -rf "$work" || true
}
trap cleanup EXIT
mkdir -m 700 "$work/runtime"
mkdir -p "$work/data" "$work/config" "$work/cache"
export XDG_RUNTIME_DIR="$work/runtime" XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export WAYLAND_DISPLAY=wayland-ci XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true
export QT_QPA_PLATFORM=wayland QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge LANG=C.UTF-8
unset DISPLAY
kwin_wayland --virtual --socket="$WAYLAND_DISPLAY" --width=800 --height=600 --no-lockscreen >"$work/kwin.log" 2>&1 & kwin_pid=$!
for _ in $(seq 1 60); do [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break; kill -0 "$kwin_pid" || { cat "$work/kwin.log"; exit 1; }; sleep 1; done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || { cat "$work/kwin.log"; exit 1; }
dbus-update-activation-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION QT_QPA_PLATFORM QT_LINUX_ACCESSIBILITY_ALWAYS_ON NO_AT_BRIDGE
echo '--- xdg-desktop-portal interfaces ---'
timeout 35s gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop >"$work/interfaces" || { cat "$work/interfaces" "$work/kwin.log"; exit 1; }
rg 'interface org.freedesktop.portal.(GlobalShortcuts|RemoteDesktop)' "$work/interfaces" || true
echo '--- Begin actual portal shortcut request: no pointer input enabled ---'
unset WAYLAND_PROTOTYPE_ALLOW_SINGLE_CLICK
experiments/wayland-portal/target/debug/wayland-portal-prototype >"$work/probe.log" 2>&1 & probe_pid=$!
sleep 20
cat "$work/probe.log"
if kill -0 "$probe_pid" 2>/dev/null; then echo 'Portal request pending; inspecting permission dialog accessibility'; else wait "$probe_pid" || true; probe_pid=''; fi
/usr/bin/python3 experiments/wayland-portal/list_accessible.py || true
cat "$work/kwin.log"
