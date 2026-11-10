#!/usr/bin/env bash
# Runs only in a disposable GitHub macOS VM; all input remains inside that VM.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || { echo 'Requires disposable GitHub-hosted runner' >&2; exit 1; }
work=$(mktemp -d)
app_pid='' target_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
clang -dynamiclib -fblocks -framework Carbon -framework CoreFoundation .github/scripts/macos-click-e2e/queue-hotkey.c -o "$work/interposer.dylib"
shopt -s nullglob
libs=(src-tauri/target/release/deps/libglobal_hotkey-*.rlib)
[[ ${#libs[@]} == 1 ]] || { echo 'Expected exactly one compiled global-hotkey library' >&2; exit 1; }
rustc --edition=2021 .github/scripts/macos-click-e2e/queue-id.rs -L dependency=src-tauri/target/release/deps --extern "global_hotkey=${libs[0]}" -o "$work/shortcut-id"
shortcut_id=$("$work/shortcut-id")
[[ "$shortcut_id" =~ ^[0-9]+$ ]] || { echo 'Invalid shortcut id' >&2; exit 1; }
swiftc .github/scripts/macos-click-e2e/target.swift -o "$work/target"
swiftc .github/scripts/macos-click-e2e/control.swift -o "$work/control"
"$work/target" "$work/events" >"$work/target.log" 2>&1 & target_pid=$!
DYLD_INSERT_LIBRARIES="$work/interposer.dylib" AUTOCLICKER_QUEUE_TEST_SIGNAL="$work/signal" AUTOCLICKER_QUEUE_TEST_ID="$shortcut_id" src-tauri/target/release/auto-clicker >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 60); do
  [[ -s "$work/events" ]] && grep -q 'queue-test: prepared shortcut id=' "$work/app.log" && break
  kill -0 "$target_pid" && kill -0 "$app_pid" || { cat "$work/target.log" "$work/app.log"; exit 1; }
  sleep 1
done
if ! grep -q 'queue-test: prepared shortcut id=' "$work/app.log"; then cat "$work/app.log"; echo 'Test library did not initialize in the app process' >&2; exit 1; fi
read -r label x y < "$work/events"
[[ "$label" == point ]] || { echo 'Target did not start' >&2; exit 1; }
"$work/control" fast "$app_pid"
"$work/control" move "$x" "$y"
"$work/control" start "$app_pid"
count=0
for _ in $(seq 1 30); do
  count=$(grep -c '^click ' "$work/events" || true)
  (( count >= 20 )) && break
  sleep 0.1
done
(( count >= 20 )) || { cat "$work/app.log" "$work/events"; echo 'Target received fewer than 20 clicks in three seconds; fast interval not established' >&2; exit 1; }
echo "Target received $count clicks within three seconds after 10 ms interval input"
touch "$work/signal"
for _ in $(seq 1 30); do grep -q 'queue-test: posted in-process Carbon hotkey event status=0/0/0' "$work/app.log" && break; sleep 0.2; done
grep -q 'queue-test: posted in-process Carbon hotkey event status=0/0/0' "$work/app.log" || { cat "$work/app.log"; echo 'In-process Carbon event was not posted successfully' >&2; exit 1; }
sleep 2
stopped=$(grep -c '^click ' "$work/events" || true)
sleep 3
after=$(grep -c '^click ' "$work/events" || true)
[[ "$stopped" == "$after" ]] || { cat "$work/app.log"; echo "App continued clicking after in-process Carbon event: $stopped -> $after" >&2; exit 1; }
"$work/control" dump "$app_pid" >"$work/accessibility.log"
grep -q 'Start clicking' "$work/accessibility.log" || { cat "$work/accessibility.log"; echo 'App did not return to idle state' >&2; exit 1; }
echo 'In-process Carbon hotkey event stopped real clicks; physical keyboard and WindowServer delivery were not tested.'
