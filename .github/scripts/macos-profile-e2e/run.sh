#!/usr/bin/env bash
# Uses keyboard and Accessibility input only inside a disposable GitHub VM.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || { echo 'Requires disposable GitHub-hosted runner' >&2; exit 1; }
work=$(mktemp -d)
app_pid=''
cleanup() {
  [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/first" "$work/after-invalid" "$work/after-cancel"
python3 - "$work" <<'PY'
import json, pathlib, sys
work = pathlib.Path(sys.argv[1])
click = {'kind':'click','button':'right','clicks':2,'position':{'x':-250,'y':300},'interval_ms':125}
settings = {'mode':'sequence','simple':click,'steps':[click,{'kind':'wait','duration_ms':550}], 'repeat':3, 'startDelayMs':4000}
profile = {'format':'auto-clicker-settings','version':1,'settings':settings}
(work/'valid.json').write_text(json.dumps(profile))
(work/'invalid.json').write_text('{"format":"auto-clicker-settings","version":1,"settings":{"steps":null}}')
PY
swiftc .github/scripts/macos-profile-e2e/control.swift -o "$work/control"
src-tauri/target/release/auto-clicker >"$work/app.log" 2>&1 & app_pid=$!
control() { "$work/control" "$1" "$app_pid" "${@:2}"; }
fail() { control dump || true; cat "$work/app.log" >&2; echo "$*" >&2; exit 1; }
wait_notice() {
  local expected="$1"
  for _ in $(seq 1 40); do
    control dump >"$work/accessibility.log" 2>&1 || true
    grep -Fq "$expected" "$work/accessibility.log" && return 0
    kill -0 "$app_pid" || break
    sleep 0.25
  done
  cat "$work/accessibility.log" >&2; fail "Notice not shown: $expected"
}
import_file() {
  control press 'Import settings'
  sleep 2
  control path "$1"
}
export_to() {
  control press 'Export settings'
  sleep 2
  control path "$1"
  for _ in $(seq 1 50); do [[ -f "$1/auto-clicker-settings.json" ]] && return 0; sleep 0.2; done
  fail "Export did not create a file in $1"
}
import_file "$work/valid.json"
wait_notice 'Settings imported.'
export_to "$work/first"
wait_notice 'Settings exported.'
python3 - "$work/valid.json" "$work/first/auto-clicker-settings.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == json.load(open(sys.argv[2])), 'Valid imported settings differ from exported settings'
print('Native import and export preserved all settings')
PY
import_file "$work/invalid.json"
wait_notice 'Could not import settings. Check the file and try again.'
export_to "$work/after-invalid"
wait_notice 'Settings exported.'
control press 'Import settings'
sleep 2
control cancel
sleep 2
export_to "$work/after-cancel"
wait_notice 'Settings exported.'
python3 - "$work/first/auto-clicker-settings.json" "$work/after-invalid/auto-clicker-settings.json" "$work/after-cancel/auto-clicker-settings.json" <<'PY'
import json, sys
baseline = json.load(open(sys.argv[1]))
for path in sys.argv[2:]:
    assert json.load(open(path)) == baseline, f'Settings changed after invalid import or cancel: {path}'
print('Invalid import and cancelled dialog preserved the existing settings')
PY
