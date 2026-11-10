#!/usr/bin/env bash
# This deliberately drives a mouse only on a disposable GitHub-hosted VM.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || { echo 'Requires disposable GitHub-hosted runner' >&2; exit 1; }
work=$(mktemp -d)
app_pid='' target_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true
  if mount | grep -Fq "$work/mount"; then hdiutil detach "$work/mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/mount" "$work/install"
case "$(uname -m)" in arm64) arch=aarch64 ;; x86_64) arch=x64 ;; *) exit 1 ;; esac
# The shared resolver requires a later target version; it downloads only the
# first version, verifies its release identity and checks its SHA-256 digest.
python3 .github/scripts/public-update-e2e/release_info.py 0.1.3 0.1.4 "_${arch}.dmg" "$work/public.dmg"
codesign --verify --strict "$work/public.dmg"
xcrun stapler validate "$work/public.dmg"
hdiutil attach "$work/public.dmg" -nobrowse -readonly -mountpoint "$work/mount" -quiet
ditto "$work/mount/Auto Clicker.app" "$work/install/Auto Clicker.app"
hdiutil detach "$work/mount" -quiet
swiftc .github/scripts/macos-click-e2e/target.swift -o "$work/target"
swiftc .github/scripts/macos-click-e2e/control.swift -o "$work/control"
"$work/target" "$work/events" >"$work/target.log" 2>&1 & target_pid=$!
"$work/install/Auto Clicker.app/Contents/MacOS/auto-clicker" >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 30); do
  [[ -s "$work/events" ]] && break
  kill -0 "$target_pid" && kill -0 "$app_pid" || { cat "$work/target.log" "$work/app.log"; exit 1; }
  sleep 1
done
read -r label x y < "$work/events"
[[ "$label" == point ]] || { echo 'Target failed to report its position' >&2; exit 1; }
"$work/control" move "$x" "$y"
"$work/control" start "$app_pid"
count=0
for _ in $(seq 1 20); do
  count=$(grep -c '^click ' "$work/events" || true)
  (( count >= 2 )) && break
  sleep 1
done
(( count >= 2 )) || { "$work/control" dump "$app_pid" || true; cat "$work/app.log" "$work/target.log" "$work/events"; echo "Expected at least two target clicks, received $count" >&2; exit 1; }
"$work/control" stop
sleep 2
stopped=$(grep -c '^click ' "$work/events" || true)
sleep 3
after=$(grep -c '^click ' "$work/events" || true)
[[ "$stopped" == "$after" ]] || { echo "Clicks continued after stop: $stopped -> $after" >&2; exit 1; }
kill -0 "$app_pid" || { cat "$work/app.log"; exit 1; }
echo "Public 0.1.3 produced $count actual target clicks and stopped after Ctrl+Shift+F8"

# Configure two positions through the real UI, then check the target's recorded
# input order for two complete cycles. Position capture uses the actual cursor.
"$work/control" button "$app_pid" 'Sequence' 0
"$work/control" button "$app_pid" 'Pick position' 0
"$work/control" move "$((x - 40))" "$y"
sleep 4
"$work/control" button "$app_pid" '+ Add click' 0
"$work/control" button "$app_pid" 'Pick position' 1
"$work/control" move "$((x + 40))" "$y"
sleep 4
before=$(grep -c '^click ' "$work/events" || true)
"$work/control" start "$app_pid"
for _ in $(seq 1 20); do
  count=$(grep -c '^click ' "$work/events" || true)
  (( count >= before + 4 )) && break
  sleep 1
done
(( count >= before + 4 )) || { "$work/control" dump "$app_pid" || true; cat "$work/events"; echo 'Sequence did not deliver four clicks' >&2; exit 1; }
head -n "$((before + 5))" "$work/events" | tail -4 | awk '
  /^click / { expected = (NR % 2 == 1 ? 40 : 120); if ($2 < expected - 2 || $2 > expected + 2) exit 1; next }
  { exit 1 }
' || { cat "$work/events"; echo 'Sequence click order differed from expected positions' >&2; exit 1; }
"$work/control" stop
sleep 2
stopped=$(grep -c '^click ' "$work/events" || true)
sleep 3
after=$(grep -c '^click ' "$work/events" || true)
[[ "$stopped" == "$after" ]] || { echo "Sequence continued after stop: $stopped -> $after" >&2; exit 1; }
echo 'Public 0.1.3 delivered two repetitions of the two-position sequence in order and stopped'
