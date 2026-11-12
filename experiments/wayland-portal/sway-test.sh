#!/usr/bin/env bash
# Real target + virtual pointer inside private headless Sway. The portal and
# shortcut events remain mocks. This script refuses to run outside CI.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && -n "${RUNNER_TEMP:-}" ]] || exit 1
mode=${1:?click or stop}
[[ "$mode" == click || "$mode" == stop ]] || exit 1
work=$(mktemp -d "$RUNNER_TEMP/sway-portal.XXXXXX")
sway_pid='' mock_pid='' target_pid=''
trap 'cat "$work/probe.log" "$work/mock.log" "$work/target.log" "$work/sway.log" 2>/dev/null || true' ERR
cleanup() {
  [[ -z "$mock_pid" ]] || kill "$mock_pid" 2>/dev/null || true
  [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true
  [[ -z "$sway_pid" ]] || kill "$sway_pid" 2>/dev/null || true
  rm -rf "$work" || true
}
trap cleanup EXIT
mkdir -m 700 "$work/runtime"
export XDG_RUNTIME_DIR="$work/runtime" WAYLAND_DISPLAY=wayland-ci XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway
export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman GDK_BACKEND=wayland
unset DISPLAY
printf 'output HEADLESS-1 resolution 800x600\nxwayland disable\n' >"$work/sway.conf"
sway -c "$work/sway.conf" >"$work/sway.log" 2>&1 & sway_pid=$!
# Sway chooses its own socket name; create a known alias only inside this
# isolated runtime directory so the probe's guard can verify its target.
for _ in $(seq 1 30); do
  [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break
  for socket in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
    if [[ -S "$socket" ]]; then ln -s "${socket##*/}" "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"; break; fi
  done
  kill -0 "$sway_pid" || { cat "$work/sway.log"; exit 1; }
  sleep 1
done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || { cat "$work/sway.log"; exit 1; }
: > "$work/events"
: > "$work/received"
/usr/bin/python3 experiments/wayland-portal/sway_target.py "$work/received" >"$work/target.log" 2>&1 & target_pid=$!
for _ in $(seq 1 30); do grep -q TARGET_READY "$work/target.log" && break; kill -0 "$target_pid" || { cat "$work/target.log"; exit 1; }; sleep 1; done
grep -q TARGET_READY "$work/target.log" || { cat "$work/target.log"; exit 1; }
sleep 2
MOCK_REAL_WAYLAND_POINTER=1 /usr/bin/python3 experiments/wayland-portal/mock_portal.py "$mode" "$work/events" >"$work/mock.log" 2>&1 & mock_pid=$!
for _ in $(seq 1 30); do grep -q MOCK_PORTAL_READY "$work/mock.log" && break; kill -0 "$mock_pid" || { cat "$work/mock.log"; exit 1; }; sleep 1; done
grep -q MOCK_PORTAL_READY "$work/mock.log" || { cat "$work/mock.log"; exit 1; }
WAYLAND_PROTOTYPE_ALLOW_SINGLE_CLICK=1 experiments/wayland-portal/target/debug/wayland-portal-prototype >"$work/probe.log" 2>&1 || { cat "$work/probe.log" "$work/mock.log"; exit 1; }
sleep 2
cat "$work/probe.log"
if [[ "$mode" == click ]]; then
  diff -u <(printf '272 1\n272 0\n') "$work/events"
  diff -u <(printf 'click\n') "$work/received"
else
  grep -q 'Emergency stop received; no click sent' "$work/probe.log"
  [[ ! -s "$work/events" && ! -s "$work/received" ]]
fi
printf 'Sway %s scenario: actual isolated GTK target observed expected input\n' "$mode"
