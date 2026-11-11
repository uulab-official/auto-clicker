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
"$work/control" move "$x" "$y"
for _ in $(seq 1 30); do
  if "$work/control" assert-target-overlap "$app_pid" "$target_pid" "$x" "$y"; then break; fi
  sleep 1
done
"$work/control" diagnose "$app_pid"
"$work/control" assert-target-overlap "$app_pid" "$target_pid" "$x" "$y"
"$work/control" start "$app_pid"
count=0
for _ in $(seq 1 20); do count=$(grep -c '^click ' "$work/events" || true); (( count >= 2 )) && break; sleep 1; done
(( count >= 2 )) || { cat "$work/events" "$work/app.log"; echo 'No clicks delivered to foreground overlapping target' >&2; exit 1; }
"$work/control" button "$app_pid" 'Stop clicking' 0
sleep 2
stopped=$(grep -c '^click ' "$work/events" || true)
sleep 2
[[ "$stopped" == "$(grep -c '^click ' "$work/events" || true)" ]] || { echo 'Clicks continued after stop' >&2; exit 1; }
echo "Foreground overlapping target received $stopped clicks; UI stop succeeded"
