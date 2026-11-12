#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && -n "${RUNNER_TEMP:-}" ]] || exit 1
mode=${1:?loop_stop or remote_closed}
[[ "$mode" == loop_stop || "$mode" == remote_closed ]] || exit 1
work=$(mktemp -d "$RUNNER_TEMP/tauri-sway.XXXXXX")
sway_pid='' mock_pid='' target_pid='' app_pid=''
trap 'cat "$work/app.log" "$work/mock.log" "$work/target.log" "$work/sway.log" 2>/dev/null || true' ERR
cleanup() {
  for pid in "$app_pid" "$mock_pid" "$target_pid" "$sway_pid"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  if mountpoint -q "$work/runtime/doc"; then fusermount -u "$work/runtime/doc" || true; fi
  rm -rf "$work" || true
}
trap cleanup EXIT
mkdir -m 700 "$work/runtime"
mkdir -p "$work/data" "$work/config" "$work/cache"
export XDG_RUNTIME_DIR="$work/runtime" XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export WAYLAND_DISPLAY=wayland-ci XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway
export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman GDK_BACKEND=wayland NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge LANG=C.UTF-8 WEBKIT_DISABLE_COMPOSITING_MODE=1
unset DISPLAY
printf 'output HEADLESS-1 resolution 800x600\nxwayland disable\n' >"$work/sway.conf"
sway -c "$work/sway.conf" >"$work/sway.log" 2>&1 & sway_pid=$!
for _ in $(seq 1 30); do
  [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break
  for socket in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do [[ ! -S "$socket" ]] || { ln -s "${socket##*/}" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"; break; }; done
  kill -0 "$sway_pid" || { cat "$work/sway.log"; exit 1; }
  sleep 1
done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]
for _ in $(seq 1 30); do
  for socket in "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do [[ ! -S "$socket" ]] || { export SWAYSOCK="$socket"; break; }; done
  [[ -z "${SWAYSOCK:-}" ]] || break
  kill -0 "$sway_pid" || { cat "$work/sway.log"; exit 1; }
  sleep 1
done
[[ -n "${SWAYSOCK:-}" && -S "$SWAYSOCK" ]]
dbus-update-activation-environment WAYLAND_DISPLAY XDG_RUNTIME_DIR XDG_SESSION_TYPE XDG_CURRENT_DESKTOP GDK_BACKEND GTK_MODULES NO_AT_BRIDGE
: > "$work/events"; : > "$work/received"
/usr/bin/python3 experiments/wayland-portal/sway_target.py "$work/received" >"$work/target.log" 2>&1 & target_pid=$!
for _ in $(seq 1 30); do grep -q TARGET_READY "$work/target.log" && break; kill -0 "$target_pid"; sleep 1; done
grep -q TARGET_READY "$work/target.log"
MOCK_REAL_WAYLAND_POINTER=1 /usr/bin/python3 experiments/wayland-portal/mock_portal.py "$mode" "$work/events" >"$work/mock.log" 2>&1 & mock_pid=$!
for _ in $(seq 1 30); do grep -q MOCK_PORTAL_READY "$work/mock.log" && break; kill -0 "$mock_pid" || { cat "$work/mock.log"; exit 1; }; sleep 1; done
grep -q MOCK_PORTAL_READY "$work/mock.log"
AUTOCLICKER_EXPERIMENTAL_WAYLAND=1 src-tauri/target/release/auto-clicker >"$work/app.log" 2>&1 & app_pid=$!
/usr/bin/python3 experiments/wayland-portal/tauri_driver.py "$app_pid" "$work/received" "$mode"
if [[ "$mode" == loop_stop ]]; then diff -u <(printf '272 1\n272 0\n') "$work/events"; else [[ ! -s "$work/events" ]]; fi
