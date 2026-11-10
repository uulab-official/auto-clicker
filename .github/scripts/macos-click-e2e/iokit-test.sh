#!/usr/bin/env bash
# All synthetic input is restricted to a disposable GitHub-hosted macOS VM.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || { echo 'Requires disposable GitHub-hosted runner' >&2; exit 1; }
shortcut=${AUTOCLICKER_TEST_SHORTCUT:-Escape}
[[ "$shortcut" == F8 || "$shortcut" == Escape ]] || exit 2
work=$(mktemp -d)
app_pid='' target_pid='' control_pid=''
cleanup() {
  [[ -z "$control_pid" ]] || kill "$control_pid" 2>/dev/null || true
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
clang -Wno-deprecated-declarations -framework IOKit -framework CoreFoundation .github/scripts/macos-click-e2e/iokit-shortcut.c -o "$work/iokit-shortcut"
swiftc .github/scripts/macos-click-e2e/target.swift -o "$work/target"
swiftc .github/scripts/macos-click-e2e/control.swift -o "$work/control"
swiftc .github/scripts/macos-click-e2e/carbon-control.swift -o "$work/carbon-control"

# An independent F7 listener distinguishes event-delivery failures from an
# app shortcut failure. It never registers the app's F8 or Escape combination.
"$work/carbon-control" >"$work/carbon.log" 2>&1 & control_pid=$!
for _ in $(seq 1 50); do grep -q 'Carbon control ready' "$work/carbon.log" && break; sleep .1; done
grep -q 'Carbon control ready' "$work/carbon.log" || { cat "$work/carbon.log"; exit 1; }
"$work/iokit-shortcut" F7 >"$work/inject.log" 2>&1 || { cat "$work/inject.log"; exit 1; }
sleep 1
cat "$work/inject.log" "$work/carbon.log"
grep -q 'Carbon control hotkey received' "$work/carbon.log" || { echo 'Synthetic HIDSystem input did not reach independent Carbon control; app shortcut cannot be assessed' >&2; exit 1; }
kill "$control_pid" 2>/dev/null || true; control_pid=''

"$work/target" "$work/events" >"$work/target.log" 2>&1 & target_pid=$!
src-tauri/target/release/auto-clicker >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 60); do
  [[ -s "$work/events" ]] && break
  kill -0 "$target_pid" && kill -0 "$app_pid" || { cat "$work/target.log" "$work/app.log"; exit 1; }
  sleep 1
done
read -r label x y < "$work/events"
[[ "$label" == point ]] || exit 1
"$work/control" move "$x" "$y"
"$work/control" start "$app_pid"
count=0
for _ in $(seq 1 20); do count=$(grep -c '^click ' "$work/events" || true); (( count >= 2 )) && break; sleep 1; done
(( count >= 2 )) || { cat "$work/app.log"; echo 'No actual target clicks' >&2; exit 1; }
"$work/iokit-shortcut" "$shortcut" || exit 1
sleep 2
stopped=$(grep -c '^click ' "$work/events" || true)
sleep 3
after=$(grep -c '^click ' "$work/events" || true)
[[ "$stopped" == "$after" ]] || { cat "$work/app.log"; echo "Clicks continued after IOKit shortcut $shortcut: $stopped -> $after" >&2; exit 1; }
"$work/control" dump "$app_pid" >"$work/ax.log"
grep -q 'Start clicking' "$work/ax.log" || { cat "$work/ax.log"; echo 'App not idle after shortcut' >&2; exit 1; }
echo "Synthetic IOKit HIDSystem Ctrl+Shift+$shortcut stopped actual clicks; physical keyboard was not tested"
