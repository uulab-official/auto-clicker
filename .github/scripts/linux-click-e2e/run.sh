#!/usr/bin/env bash
# Never run against a user's display: this script is limited to a GitHub VM's Xvfb.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${DISPLAY:-}" =~ ^:[0-9]+$ ]] || { echo 'Requires GitHub Actions and an isolated local X display' >&2; exit 1; }
ps -eo args= | grep -F -- "Xvfb $DISPLAY " | grep -qv 'grep' || { echo 'DISPLAY is not backed by the expected Xvfb process' >&2; exit 1; }
work=$(mktemp -d)
app_pid=''
target_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true
  rm -r "$work"
}
trap cleanup EXIT
mkdir -p "$work/config" "$work/data" "$work/cache"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
export LANG=C.UTF-8 WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11 NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge
/usr/bin/python3 .github/scripts/linux-click-e2e/target.py "$work/count" >"$work/target.log" 2>&1 & target_pid=$!
src-tauri/target/release/auto-clicker >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 60); do
  if [[ -f "$work/count" ]] && xdotool search --onlyvisible --name '^Auto Clicker$' >/dev/null 2>&1; then break; fi
  kill -0 "$app_pid" 2>/dev/null && kill -0 "$target_pid" 2>/dev/null || { cat "$work/app.log" "$work/target.log"; exit 1; }
  sleep 1
done
[[ -f "$work/count" ]] || { echo 'Target window did not start' >&2; exit 1; }
/usr/bin/python3 .github/scripts/linux-click-e2e/start.py "$app_pid"
xdotool mousemove 1150 900
count=0
for _ in $(seq 1 15); do
  count=$(cat "$work/count")
  (( count >= 2 )) && break
  sleep 1
done
(( count >= 2 )) || { cat "$work/app.log"; echo "Expected at least two actual clicks; received $count" >&2; exit 1; }
xdotool key --clearmodifiers ctrl+shift+F8
sleep 2
stopped=$(cat "$work/count")
sleep 3
after=$(cat "$work/count")
[[ "$stopped" == "$after" ]] || { echo "Clicks continued after emergency stop: $stopped -> $after" >&2; exit 1; }
kill -0 "$app_pid" 2>/dev/null || { cat "$work/app.log"; echo 'App exited unexpectedly' >&2; exit 1; }
echo "Verified $count target clicks and no additional clicks after global emergency stop"
