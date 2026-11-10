#!/usr/bin/env bash
# Runs only on a disposable GitHub macOS VM. Uses targeted AX, not host input.
set -euo pipefail
baseline_version="${EXPECTED_BASELINE_VERSION:-0.1.0}"
expected_version="${EXPECTED_UPDATE_VERSION:-0.1.1}"
work="$(cd "$(mktemp -d)" && pwd -P)"
app_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  if mount | grep -Fq "$work/mount"; then hdiutil detach "$work/mount" -quiet || true; fi
  rm -r "$work"
}
trap cleanup EXIT
mkdir -p "$work/mount" "$work/install" "$work/expected" "$work/config" "$work/data"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" LANG=en_US.UTF-8
case "$(uname -m)" in
  arm64) download_arch=aarch64; platform=darwin-aarch64 ;;
  x86_64) download_arch=x64; platform=darwin-x86_64 ;;
  *) echo 'Unsupported runner architecture' >&2; exit 1 ;;
esac
if [[ "${PUBLIC_UPDATE_PROBE_ONLY:-0}" != 1 ]]; then
curl --fail --location --silent --show-error -o "$work/latest.json" 'https://github.com/uulab-official/auto-clicker/releases/latest/download/latest.json'
python3 - "$work/latest.json" "$work/target.url" "$platform" "$expected_version" <<'PY'
import json, pathlib, sys
m=json.loads(pathlib.Path(sys.argv[1]).read_text())
if m['version'] != sys.argv[4]: raise SystemExit('Latest public release does not match expected version')
pathlib.Path(sys.argv[2]).write_text(m['platforms'][sys.argv[3]]['url'])
PY
curl --fail --location --silent --show-error -H 'Accept: application/octet-stream' -H 'User-Agent: auto-clicker-release-verification' -o "$work/update.tar.gz" "$(cat "$work/target.url")"
tar -xzf "$work/update.tar.gz" -C "$work/expected"
expected_app="$(find "$work/expected" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$expected_app" ]] || { echo 'Published update app missing from archive' >&2; exit 1; }
expected_hash=$(shasum -a 256 "$expected_app/Contents/MacOS/auto-clicker" | awk '{print $1}')
fi
python3 .github/scripts/public-update-e2e/release_info.py "$baseline_version" "$expected_version" "_${download_arch}.dmg" "$work/public.dmg"
codesign --verify --strict "$work/public.dmg"
xcrun stapler validate "$work/public.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$work/public.dmg"
hdiutil attach "$work/public.dmg" -nobrowse -readonly -mountpoint "$work/mount" -quiet
ditto "$work/mount/Auto Clicker.app" "$work/install/Auto Clicker.app"
hdiutil detach "$work/mount" -quiet
app="$work/install/Auto Clicker.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$baseline_version" ]] || { echo "Expected original release version $baseline_version" >&2; exit 1; }
"$app/Contents/MacOS/auto-clicker" >"$work/app.log" 2>&1 & app_pid=$!
sleep 8
kill -0 "$app_pid" 2>/dev/null || { cat "$work/app.log"; echo 'Original application did not start' >&2; exit 1; }
swiftc .github/scripts/public-update-e2e/mac-press.swift -o "$work/press"
if [[ "${PUBLIC_UPDATE_PROBE_ONLY:-0}" == 1 ]]; then
  "$work/press" "$app_pid" probe
  echo 'Accessibility probe passed; no application action was invoked'
  exit 0
fi
"$work/press" "$app_pid"
updated=0
for _ in $(seq 1 180); do
  version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$version" == "$expected_version" ]]; then
    hash=$(shasum -a 256 "$app/Contents/MacOS/auto-clicker" | awk '{print $1}')
    if [[ "$hash" == "$expected_hash" ]]; then updated=1; break; fi
  fi
  sleep 1
done
[[ "$updated" == 1 ]] || { cat "$work/app.log"; echo 'Public update did not install the expected application' >&2; exit 1; }
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
echo "Original published $baseline_version updated to public notarized $expected_version and executable SHA256 matched"
kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; app_pid=''
"$app/Contents/MacOS/auto-clicker" >"$work/relaunch.log" 2>&1 & app_pid=$!
sleep 8
kill -0 "$app_pid" 2>/dev/null || { cat "$work/relaunch.log"; echo 'Updated application did not relaunch' >&2; exit 1; }
echo 'Updated public application relaunched'
