#!/usr/bin/env bash
# Download and verify a public release before testing its installed app on a disposable VM.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || { echo 'Requires disposable GitHub-hosted runner' >&2; exit 1; }
version="${PUBLIC_VERSION:-0.1.4}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
case "$(uname -m)" in arm64) arch=aarch64 ;; x86_64) arch=x64 ;; *) exit 1 ;; esac
work=$(mktemp -d)
cleanup() {
  if mount | grep -Fq "$work/mount"; then hdiutil detach "$work/mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/mount" "$work/install"
gh api "repos/uulab-official/auto-clicker/releases/tags/v$version" > "$work/release.json"
python3 - "$work/release.json" "$arch" "$work/digest" "$version" <<'PY'
import importlib.util, json, pathlib, sys
spec = importlib.util.spec_from_file_location('release_info', '.github/scripts/public-update-e2e/release_info.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
release = json.loads(pathlib.Path(sys.argv[1]).read_text())
_, digest = module.select_baseline_asset(release, sys.argv[4], f'_{sys.argv[2]}.dmg')
pathlib.Path(sys.argv[3]).write_text(digest)
PY
gh release download "v$version" --repo uulab-official/auto-clicker --pattern "*_${arch}.dmg" --output "$work/public.dmg"
[[ "$(shasum -a 256 "$work/public.dmg" | awk '{print $1}')" == "$(cat "$work/digest")" ]] || { echo 'Public installer SHA-256 mismatch' >&2; exit 1; }
codesign --verify --strict "$work/public.dmg"
xcrun stapler validate "$work/public.dmg"
spctl --assess --type open --context context:primary-signature -vv "$work/public.dmg"
hdiutil attach "$work/public.dmg" -nobrowse -readonly -mountpoint "$work/mount" -quiet
ditto "$work/mount/Auto Clicker.app" "$work/install/Auto Clicker.app"
hdiutil detach "$work/mount" -quiet
app="$work/install/Auto Clicker.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]] || { echo 'Installed app version mismatch' >&2; exit 1; }
codesign --verify --deep --strict "$app"
echo "Testing signed public $version app from verified $arch DMG"
APP_BINARY="$app/Contents/MacOS/auto-clicker" bash .github/scripts/macos-profile-e2e/run.sh
