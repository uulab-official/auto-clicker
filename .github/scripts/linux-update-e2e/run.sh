#!/usr/bin/env bash
# Runs only inside an isolated GitHub Actions Linux VM and Xvfb display.
set -euo pipefail
export APPIMAGE_EXTRACT_AND_RUN=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11 LANG=C.UTF-8
work="$(mktemp -d)"
server_pid=''
app_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill -- "-$app_pid" 2>/dev/null || true
  [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
  rm -r "$work"
}
trap cleanup EXIT
mkdir -p "$work/install" "$work/server" "$work/config" "$work/data" "$work/cache"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"

# Install and launch the actual public 0.1.0 AppImage. No real mouse clicks.
curl --fail --location --silent --show-error -o "$work/install/public.AppImage" \
  'https://github.com/uulab-official/auto-clicker/releases/download/v0.1.0/Auto-Clicker_0.1.0_amd64.AppImage'
chmod +x "$work/install/public.AppImage"
setsid "$work/install/public.AppImage" >"$work/public.log" 2>&1 &
app_pid=$!
found=0
for _ in $(seq 1 90); do
  if xdotool search --onlyvisible --name 'Auto Clicker' >/dev/null 2>&1; then found=1; break; fi
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep 1
done
if [[ "$found" != 1 ]]; then cat "$work/public.log"; echo 'Public AppImage did not open a visible window' >&2; exit 1; fi
echo 'Public v0.1.0 AppImage installed and opened in Xvfb'
kill -- "-$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
app_pid=''

# Build two disposable, distinct versions. The only UI change simulates a user
# pressing the install button; the real Tauri updater performs check/install.
cat >> src/main.ts <<'JS'
{
  const timer = window.setInterval(() => {
    const button = document.querySelector<HTMLButtonElement>('button[data-action="install-update"]');
    if (button && !button.disabled) { window.clearInterval(timer); button.click(); }
  }, 250);
}
JS
./node_modules/.bin/tauri signer generate --ci -p 'fixture-only' -w "$work/key" >/dev/null
export TAURI_SIGNING_PRIVATE_KEY="$(cat "$work/key")" TAURI_SIGNING_PRIVATE_KEY_PASSWORD='fixture-only'
export FIXTURE_PUBLIC_KEY="$(cat "$work/key.pub")" FIXTURE_DIR="$work"
python3 - <<'PY'
import json, os, pathlib
work = pathlib.Path(os.environ['FIXTURE_DIR'])
for version in ('0.1.1', '0.1.2'):
    config = {'version': version, 'bundle': {'createUpdaterArtifacts': True},
              'plugins': {'updater': {'pubkey': os.environ['FIXTURE_PUBLIC_KEY'],
                 'endpoints': ['http://127.0.0.1:18791/latest.json'],
                 'dangerousInsecureTransportProtocol': True}}}
    (work / (version + '.json')).write_text(json.dumps(config))
PY
npm run tauri build -- --bundles appimage --config "$work/0.1.2.json"
candidate="$(find src-tauri/target/release/bundle/appimage -maxdepth 1 -name '*0.1.2*.AppImage' -type f -print -quit)"
test -n "$candidate" && test -f "$candidate.sig"
cp "$candidate" "$work/server/candidate.AppImage"
python3 - "$candidate.sig" "$work/server/latest.json" <<'PY'
import json, pathlib, sys
manifest = {'version':'0.1.2','notes':'Isolated CI fixture',
  'platforms':{'linux-x86_64':{'signature':pathlib.Path(sys.argv[1]).read_text().strip(),
    'url':'http://127.0.0.1:18791/candidate.AppImage'}}}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest))
PY
npm run tauri build -- --bundles appimage --config "$work/0.1.1.json"
base="$(find src-tauri/target/release/bundle/appimage -maxdepth 1 -name '*0.1.1*.AppImage' -type f -print -quit)"
test -n "$base"
cp "$base" "$work/install/fixture.AppImage"
chmod +x "$work/install/fixture.AppImage"
python3 -m http.server 18791 --bind 127.0.0.1 --directory "$work/server" >"$work/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 30); do curl --silent --fail http://127.0.0.1:18791/latest.json >/dev/null && break; sleep 1; done
setsid "$work/install/fixture.AppImage" >"$work/fixture.log" 2>&1 &
app_pid=$!
expected="$(sha256sum "$work/server/candidate.AppImage" | cut -d' ' -f1)"
updated=0
for _ in $(seq 1 120); do
  actual="$(sha256sum "$work/install/fixture.AppImage" | cut -d' ' -f1)"
  if [[ "$actual" == "$expected" ]]; then updated=1; break; fi
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep 1
done
if [[ "$updated" != 1 ]]; then cat "$work/fixture.log"; cat "$work/server.log"; echo 'Installed AppImage did not update to signed candidate' >&2; exit 1; fi
grep -q 'GET /candidate.AppImage' "$work/server.log"
echo 'Fixture v0.1.1 updated in place to signed v0.1.2 AppImage (SHA-256 matched)'

kill -- "-$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
app_pid=''
# Relaunch the replaced AppImage and check that a GUI window opens.
setsid "$work/install/fixture.AppImage" >"$work/relaunch.log" 2>&1 &
app_pid=$!
found=0
for _ in $(seq 1 90); do
  if xdotool search --onlyvisible --name 'Auto Clicker' >/dev/null 2>&1; then found=1; break; fi
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep 1
done
if [[ "$found" != 1 ]]; then cat "$work/relaunch.log"; echo 'Updated AppImage did not relaunch' >&2; exit 1; fi
echo 'Updated fixture AppImage relaunched in Xvfb'
