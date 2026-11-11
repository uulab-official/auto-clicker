#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${DISPLAY:-}" =~ ^:[0-9]+$ ]] || exit 1
ps -eo args= | grep -F -- "Xvfb $DISPLAY " | grep -qv grep || exit 1
work=$(mktemp -d)
app_pid='' target_pid=''
cleanup() { [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true; [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$work/config" "$work/data" "$work/cache"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" LANG=C.UTF-8 WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11 NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge
/usr/bin/python3 .github/scripts/linux-delay-e2e/target.py "$work/events" >"$work/target.log" 2>&1 & target_pid=$!
"$APP_BINARY" >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 60); do [[ -f "$work/events" ]] && xdotool search --onlyvisible --name '^Auto Clicker$' >/dev/null 2>&1 && break; kill -0 "$app_pid" && kill -0 "$target_pid"; sleep 1; done
/usr/bin/python3 .github/scripts/public-pause-e2e/verify.py "$app_pid" "$work/events" || { cat "$work/app.log" "$work/target.log"; exit 1; }
