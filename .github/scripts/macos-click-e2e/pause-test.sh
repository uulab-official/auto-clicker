#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || exit 1
work=$(mktemp -d)
app_pid='' target_pid=''
cleanup() { [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true; [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
swiftc .github/scripts/macos-click-e2e/target.swift -o "$work/target"
swiftc .github/scripts/macos-click-e2e/control.swift -o "$work/control"
"$work/target" "$work/events" >"$work/target.log" 2>&1 & target_pid=$!
"$APP_BINARY" >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 60); do [[ -s "$work/events" ]] && break; kill -0 "$target_pid" && kill -0 "$app_pid" || exit 1; sleep 1; done
read -r label x y < "$work/events"
[[ "$label" == point ]] || exit 1
"$work/control" finite "$app_pid"
read -r appx appy < <("$work/control" app-point "$app_pid")
"$work/control" move "$appx" "$appy"
"$work/control" diagnose "$app_pid"
"$work/control" start "$app_pid"
"$work/control" diagnose "$app_pid"
sleep 6
"$work/control" diagnose "$app_pid"
cat "$work/events"
"$work/control" dump "$app_pid" > "$work/paused"
cat "$work/paused"
grep -qi 'paused while the pointer' "$work/paused" || { echo 'No paused state' >&2; exit 1; }
grep -q 'Completed cycles: 0' "$work/paused" || { echo 'Cycle advanced while blocked' >&2; exit 1; }
[[ "$(grep -c '^click ' "$work/events" || true)" == 0 ]] || { echo 'Unexpected target click while blocked' >&2; exit 1; }
"$work/control" move "$x" "$y"
sleep 5
"$work/control" dump "$app_pid" > "$work/resumed"
cat "$work/events" "$work/resumed"
[[ "$(grep -c '^click ' "$work/events" || true)" == 1 ]] || { echo 'Expected exactly one click after resume' >&2; exit 1; }
grep -q 'Start clicking' "$work/resumed" || { echo 'Run did not finish' >&2; exit 1; }
echo 'Finite run stayed paused with zero completed cycles then resumed for exactly one click'
"$work/control" move "$appx" "$appy"
"$work/control" start "$app_pid"
sleep 6
"$work/control" dump "$app_pid" > "$work/paused-again"
grep -qi 'paused while the pointer' "$work/paused-again" || { cat "$work/paused-again"; echo 'Second run did not pause' >&2; exit 1; }
"$work/control" button "$app_pid" 'Stop clicking' 0
sleep 2
"$work/control" move "$x" "$y"
sleep 3
"$work/control" dump "$app_pid" > "$work/stopped"
cat "$work/stopped"
[[ "$(grep -c '^click ' "$work/events" || true)" == 1 ]] || { echo 'Unexpected click after stop' >&2; exit 1; }
grep -q 'Start clicking' "$work/stopped" || { echo 'Stop did not return to idle' >&2; exit 1; }
echo 'UI stop during pause prevented further clicks and returned to idle'
