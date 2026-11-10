#!/usr/bin/env bash
# Native dialog interactions are confined to a disposable GitHub Actions Xvfb.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${DISPLAY:-}" =~ ^:[0-9]+$ ]] || { echo 'Requires GitHub Actions and an isolated local X display' >&2; exit 1; }
ps -eo args= | grep -F -- "Xvfb $DISPLAY " | grep -qv grep || { echo 'DISPLAY is not backed by Xvfb' >&2; exit 1; }
work=$(mktemp -d)
app_pid=''
wm_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  [[ -z "$wm_pid" ]] || kill "$wm_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/config" "$work/data" "$work/cache" "$work/files"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
export LANG=C.UTF-8 WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11 NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge
openbox --sm-disable >"$work/openbox.log" 2>&1 & wm_pid=$!
for _ in $(seq 1 30); do
  if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -Eq 'window id # 0x[0-9a-f]+'; then break; fi
  kill -0 "$wm_pid" 2>/dev/null || { cat "$work/openbox.log"; exit 1; }
  sleep 0.2
done
xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -Eq 'window id # 0x[0-9a-f]+' || { cat "$work/openbox.log"; echo 'Openbox did not register with X11' >&2; exit 1; }
/usr/bin/python3 .github/scripts/linux-profile-e2e/drive.py prepare "$work/files"
src-tauri/target/release/auto-clicker >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 60); do
  xdotool search --onlyvisible --name '^Auto Clicker$' >/dev/null 2>&1 && break
  kill -0 "$app_pid" 2>/dev/null || { cat "$work/app.log"; exit 1; }
  sleep 1
done
kill -0 "$app_pid" 2>/dev/null || { cat "$work/app.log"; exit 1; }
/usr/bin/python3 .github/scripts/linux-profile-e2e/drive.py test "$app_pid" "$work/files"
echo 'Verified native settings export, import, invalid-file preservation, and dialog cancellation'
