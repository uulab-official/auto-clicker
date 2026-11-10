#!/usr/bin/env bash
# Runs exclusively on a disposable GitHub Actions VM with its own Xvfb display.
set -euo pipefail
baseline_version="${EXPECTED_BASELINE_VERSION:-0.1.0}"
expected_version="${EXPECTED_UPDATE_VERSION:-0.1.1}"
work="$(mktemp -d)"
app_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill -- "-$app_pid" 2>/dev/null || true
  rm -r "$work"
}
trap cleanup EXIT
mkdir -p "$work/install" "$work/config" "$work/data" "$work/cache"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
export APPIMAGE_EXTRACT_AND_RUN=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11 LANG=C.UTF-8 NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge
if [[ "${PUBLIC_UPDATE_PROBE_ONLY:-0}" != 1 ]]; then
curl --fail --location --silent --show-error -o "$work/latest.json" 'https://github.com/uulab-official/auto-clicker/releases/latest/download/latest.json'
python3 - "$work/latest.json" "$work/target.url" "$expected_version" <<'PY'
import json, pathlib, sys
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
if m['version'] != sys.argv[3]: raise SystemExit('Latest public release does not match expected version')
pathlib.Path(sys.argv[2]).write_text(m['platforms']['linux-x86_64']['url'])
PY
curl --fail --location --silent --show-error -H 'Accept: application/octet-stream' -H 'User-Agent: auto-clicker-release-verification' -o "$work/expected.AppImage" "$(cat "$work/target.url")"
fi
python3 .github/scripts/public-update-e2e/release_info.py "$baseline_version" "$expected_version" _amd64.AppImage "$work/install/Auto Clicker.AppImage"
chmod +x "$work/install/Auto Clicker.AppImage"
if [[ "${PUBLIC_UPDATE_PROBE_ONLY:-0}" != 1 ]]; then
base_hash=$(sha256sum "$work/install/Auto Clicker.AppImage" | awk '{print $1}')
expected_hash=$(sha256sum "$work/expected.AppImage" | awk '{print $1}')
[[ "$base_hash" != "$expected_hash" ]] || { echo 'Baseline and update must differ' >&2; exit 1; }
fi
setsid "$work/install/Auto Clicker.AppImage" >"$work/app.log" 2>&1 &
app_pid=$!
window=''
for _ in $(seq 1 90); do
  window=$(xdotool search --onlyvisible --name '^Auto Clicker$' 2>/dev/null | head -1 || true)
  [[ -z "$window" ]] || break
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 1
done
[[ -n "$window" ]] || { cat "$work/app.log"; echo 'Published application did not open' >&2; exit 1; }
app_window_pid=$(xdotool getwindowpid "$window")
echo "Published $baseline_version started, target PID: $app_window_pid"
if [[ "${PUBLIC_UPDATE_PROBE_ONLY:-0}" == 1 ]]; then
  /usr/bin/python3 .github/scripts/public-update-e2e/linux-press.py "$app_window_pid" probe
  echo 'Accessibility probe passed; no application action was invoked'
  exit 0
fi
/usr/bin/python3 .github/scripts/public-update-e2e/linux-press.py "$app_window_pid"
updated=0
for _ in $(seq 1 180); do
  hash=$(sha256sum "$work/install/Auto Clicker.AppImage" | awk '{print $1}')
  if [[ "$hash" == "$expected_hash" ]]; then updated=1; break; fi
  sleep 1
done
[[ "$updated" == 1 ]] || { cat "$work/app.log"; echo 'Public update was not installed' >&2; exit 1; }
echo "Actual published $baseline_version AppImage updated to public $expected_version; payload SHA256 matched"
kill -- "-$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; app_pid=''
setsid "$work/install/Auto Clicker.AppImage" >"$work/relaunch.log" 2>&1 &
app_pid=$!
for _ in $(seq 1 60); do
  if xdotool search --onlyvisible --name '^Auto Clicker$' >/dev/null 2>&1; then echo 'Updated public application relaunched'; exit 0; fi
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 1
done
cat "$work/relaunch.log"; echo 'Updated application did not relaunch' >&2; exit 1
