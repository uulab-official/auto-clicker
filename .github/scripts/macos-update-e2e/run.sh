#!/usr/bin/env bash
# Runs only on an isolated GitHub macOS runner, never on the user's desktop.
set -euo pipefail
work="$(mktemp -d)"
work="$(cd "$work" && pwd -P)" # updater rejects symlinked /var paths on macOS
app_pid=''
server_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  if mount | grep -Fq "$work/mount"; then hdiutil detach "$work/mount" -quiet || true; fi
  rm -r "$work"
}
trap cleanup EXIT
mkdir -p "$work/mount" "$work/install" "$work/server" "$work/config" "$work/data"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data"
# Download the actual published Apple Silicon installer, mount it read-only,
# install in a temporary directory and launch its actual executable.
case "$(uname -m)" in
  arm64) mac_arch=aarch64 ;;
  x86_64) mac_arch=x64 ;;
  *) echo 'Unsupported runner architecture' >&2; exit 1 ;;
esac
curl --fail --location --silent --show-error -o "$work/public.dmg" "https://github.com/uulab-official/auto-clicker/releases/download/v0.1.0/Auto-Clicker_0.1.0_${mac_arch}.dmg"
codesign --verify --verbose=2 "$work/public.dmg"
xcrun stapler validate "$work/public.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$work/public.dmg"
hdiutil attach "$work/public.dmg" -nobrowse -readonly -mountpoint "$work/mount" -quiet
ditto "$work/mount/Auto Clicker.app" "$work/install/Published.app"
hdiutil detach "$work/mount" -quiet
codesign --verify --deep --strict "$work/install/Published.app"
"$work/install/Published.app/Contents/MacOS/auto-clicker" >"$work/public.log" 2>&1 &
app_pid=$!
sleep 8
if ! kill -0 "$app_pid" 2>/dev/null; then cat "$work/public.log"; echo 'Published app failed to start' >&2; exit 1; fi
echo 'Published notarized 0.1.0 installed and started in isolated runner'
kill "$app_pid"; wait "$app_pid" 2>/dev/null || true
app_pid=''
# Hosted macOS runners can launch the process but do not guarantee a usable
# WindowServer/WebView. In this disposable checkout, invoke the real Tauri
# commands directly; this verifies backend update behavior, not UI interaction.
python3 - <<'PYCODE'
from pathlib import Path
path = Path('src-tauri/src/lib.rs')
source = path.read_text()
marker = '        .setup(|app| {\n'
assert source.count(marker) == 1
fixture = """        .setup(|app| {
            if std::env::var_os("AUTOCLICKER_UPDATE_FIXTURE").is_some() {
                let handle = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    match check_update(handle.clone(), handle.state::<PendingUpdate>()).await {
                        Ok(Some(info)) => {
                            eprintln!("fixture: update {} available", info.version);
                            match install_update(handle.clone(), handle.state::<PendingUpdate>(), info.version).await {
                                Ok(()) => eprintln!("fixture: update installed"),
                                Err(error) => eprintln!("fixture: installation failed: {error}"),
                            }
                        }
                        Ok(None) => eprintln!("fixture: no update available"),
                        Err(error) => eprintln!("fixture: update check failed: {error}"),
                    }
                });
            }
"""
path.write_text(source.replace(marker, fixture))
PYCODE
./node_modules/.bin/tauri signer generate --ci -p 'fixture-only' -w "$work/key" >/dev/null
export TAURI_SIGNING_PRIVATE_KEY="$(cat "$work/key")" TAURI_SIGNING_PRIVATE_KEY_PASSWORD='fixture-only' VITE_UPDATE_E2E=1
export FIXTURE_PUBLIC_KEY="$(cat "$work/key.pub")" FIXTURE_DIR="$work" MAC_ARCH="$mac_arch"
python3 - <<'PY'
import json, os, pathlib
work = pathlib.Path(os.environ['FIXTURE_DIR'])
for version in ('0.1.1', '0.1.2'):
    config = {'version': version, 'bundle': {'createUpdaterArtifacts': True},
              'plugins': {'updater': {'pubkey': os.environ['FIXTURE_PUBLIC_KEY'],
                 'endpoints': ['http://127.0.0.1:18792/latest.json'],
                 'dangerousInsecureTransportProtocol': True}}}
    (work / (version + '.json')).write_text(json.dumps(config))
PY
npm run tauri build -- --bundles app --config "$work/0.1.2.json"
candidate='src-tauri/target/release/bundle/macos/Auto Clicker.app.tar.gz'
test -f "$candidate" && test -f "$candidate.sig"
cp "$candidate" "$work/server/candidate.tar.gz"
python3 - "$candidate.sig" "$work/server/latest.json" <<'PY'
import json, os, pathlib, sys
platform = 'darwin-aarch64' if os.environ['MAC_ARCH'] == 'aarch64' else 'darwin-x86_64'
manifest = {'version':'0.1.2','notes':'Isolated CI fixture',
  'platforms':{platform:{'signature':pathlib.Path(sys.argv[1]).read_text().strip(),
    'url':'http://127.0.0.1:18792/candidate.tar.gz'}}}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest))
PY
npm run tauri build -- --bundles app --config "$work/0.1.1.json"
ditto 'src-tauri/target/release/bundle/macos/Auto Clicker.app' "$work/install/Fixture.app"
python3 -m http.server 18792 --bind 127.0.0.1 --directory "$work/server" >"$work/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 30); do curl --silent --fail http://127.0.0.1:18792/latest.json >/dev/null && break; sleep 1; done
AUTOCLICKER_UPDATE_FIXTURE=1 "$work/install/Fixture.app/Contents/MacOS/auto-clicker" >"$work/fixture.log" 2>&1 &
app_pid=$!
updated=0
for _ in $(seq 1 120); do
  actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/install/Fixture.app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$actual" == '0.1.2' ]]; then updated=1; break; fi
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep 1
done
if [[ "$updated" != 1 ]]; then cat "$work/fixture.log"; cat "$work/server.log"; echo 'Installed app did not update' >&2; exit 1; fi
grep -q 'GET /candidate.tar.gz' "$work/server.log"
for _ in $(seq 1 10); do grep -q 'fixture: update installed' "$work/fixture.log" && break; sleep 1; done
grep -q 'fixture: update installed' "$work/fixture.log"
echo 'Fixture 0.1.1 updated in place to signed 0.1.2 app using Tauri commands (UI not tested)'
kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true
app_pid=''
"$work/install/Fixture.app/Contents/MacOS/auto-clicker" >"$work/relaunch.log" 2>&1 &
app_pid=$!
sleep 8
if ! kill -0 "$app_pid" 2>/dev/null; then cat "$work/relaunch.log"; echo 'Updated app did not relaunch' >&2; exit 1; fi
echo 'Updated fixture app relaunched'
