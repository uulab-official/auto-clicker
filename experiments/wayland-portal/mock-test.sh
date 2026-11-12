#!/usr/bin/env bash
# Runs only on a disposable GitHub runner.  The mock records events and never
# delivers them to the compositor or to physical input devices.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && -n "${RUNNER_TEMP:-}" ]] || exit 1
mode=${1:?mock mode}
work=$(mktemp -d "$RUNNER_TEMP/wayland-portal.XXXXXX")
weston_pid='' mock_pid=''
cleanup() {
  [[ -z "$mock_pid" ]] || kill "$mock_pid" 2>/dev/null || true
  [[ -z "$weston_pid" ]] || kill "$weston_pid" 2>/dev/null || true
  rm -rf "$work" || true
}
trap cleanup EXIT
mkdir -m 700 "$work/runtime"
export XDG_RUNTIME_DIR="$work/runtime" WAYLAND_DISPLAY=wayland-ci XDG_SESSION_TYPE=wayland
unset DISPLAY
weston --backend=headless-backend.so --use-pixman --socket="$WAYLAND_DISPLAY" --idle-time=0 >"$work/weston.log" 2>&1 & weston_pid=$!
for _ in $(seq 1 30); do [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break; kill -0 "$weston_pid"; sleep 1; done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || { cat "$work/weston.log"; exit 1; }
: > "$work/events"
/usr/bin/python3 experiments/wayland-portal/mock_portal.py "$mode" "$work/events" >"$work/mock.log" 2>&1 & mock_pid=$!
for _ in $(seq 1 30); do grep -q MOCK_PORTAL_READY "$work/mock.log" && break; kill -0 "$mock_pid"; sleep 1; done
grep -q MOCK_PORTAL_READY "$work/mock.log" || { cat "$work/mock.log"; exit 1; }
set +e
WAYLAND_PROTOTYPE_ALLOW_SINGLE_CLICK=1 experiments/wayland-portal/target/debug/wayland-portal-prototype >"$work/probe.log" 2>&1
status=$?
set -e
cat "$work/probe.log"
cat "$work/mock.log"
case "$mode" in
  click) [[ $status == 0 ]] && diff -u <(printf '272 1\n272 0\n') "$work/events" ;;
  stop) [[ $status == 0 ]] && grep -q 'Emergency stop received; no click sent' "$work/probe.log" && [[ ! -s "$work/events" ]] ;;
  revoked) [[ $status != 0 ]] && grep -q 'Shortcut session closed' "$work/probe.log" && [[ ! -s "$work/events" ]] ;;
  denied) [[ $status != 0 ]] && grep -q 'did not bind a usable emergency shortcut' "$work/probe.log" && [[ ! -s "$work/events" ]] ;;
  *) exit 1 ;;
esac
printf 'Mock portal scenario %s passed; no real input was delivered\n' "$mode"
