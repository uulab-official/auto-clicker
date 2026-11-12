#!/usr/bin/env bash
set -euo pipefail
[[ "${CI:-}" == true && "${GITHUB_ACTIONS:-}" == true ]] || exit 1
work=$(mktemp -d)
weston_pid='' app_pid=''
cleanup() { [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true; [[ -z "$weston_pid" ]] || kill "$weston_pid" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$work/runtime" "$work/data" "$work/config" "$work/cache"
chmod 700 "$work/runtime"
export XDG_RUNTIME_DIR="$work/runtime" XDG_DATA_HOME="$work/data" XDG_CONFIG_HOME="$work/config" XDG_CACHE_HOME="$work/cache"
export WAYLAND_DISPLAY=wayland-ci XDG_SESSION_TYPE=wayland GDK_BACKEND=wayland NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge LANG=C.UTF-8 WEBKIT_DISABLE_COMPOSITING_MODE=1
unset DISPLAY
weston --backend=headless-backend.so --use-pixman --socket="$WAYLAND_DISPLAY" --idle-time=0 >"$work/weston.log" 2>&1 & weston_pid=$!
for _ in $(seq 1 30); do [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break; kill -0 "$weston_pid"; sleep 1; done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || { cat "$work/weston.log"; exit 1; }
"$APP_BINARY" >"$work/app.log" 2>&1 & app_pid=$!
/usr/bin/python3 .github/scripts/wayland-guard-e2e/check.py "$app_pid" || { cat "$work/weston.log" "$work/app.log"; exit 1; }
