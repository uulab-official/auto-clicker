#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${CI:-}" == true && "${DISPLAY:-}" =~ ^:[0-9]+$ ]]
ps -eo args= | grep -F -- "Xvfb $DISPLAY " | grep -qv grep
work=$(mktemp -d)
app_pid='' target_pid=''
cleanup() { [[ -z "$app_pid" ]] || kill "$app_pid" 2>/dev/null || true; [[ -z "$target_pid" ]] || kill "$target_pid" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$work/config" "$work/data" "$work/cache"
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" LANG=C.UTF-8 WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11 NO_AT_BRIDGE=0 GTK_MODULES=atk-bridge
/usr/bin/python3 .github/scripts/linux-click-e2e/target.py "$work/count" "$work/events" >"$work/target.log" 2>&1 & target_pid=$!
"${APP_BINARY:-src-tauri/target/release/auto-clicker}" >"$work/app.log" 2>&1 & app_pid=$!
for _ in $(seq 1 60); do
  if [[ -f "$work/count" ]] && xdotool search --onlyvisible --name '^Auto Clicker$' >/dev/null 2>&1; then break; fi
  kill -0 "$app_pid" && kill -0 "$target_pid" || { cat "$work/app.log" "$work/target.log"; exit 1; }
  sleep 1
done
app=$(xdotool search --onlyvisible --name '^Auto Clicker$' | head -1)
target=$(xdotool search --onlyvisible --name '^Auto Clicker isolated test target$' | head -1)
eval "$(xdotool getwindowgeometry --shell "$app" | grep -E '^(X|Y|WIDTH|HEIGHT)=')"
x=$((X+60)); y=$((Y+90))
echo "App $app: $X,$Y ${WIDTH}x${HEIGHT}; overlapping target point $x,$y"
xdotool windowmove "$target" "$((x-30))" "$((y-30))"
/usr/bin/python3 .github/scripts/linux-click-e2e/start.py "$app_pid"
xdotool windowraise "$target" mousemove "$x" "$y"
for _ in $(seq 1 15); do (( $(cat "$work/count") >= 2 )) && break; sleep 1; done
count=$(cat "$work/count")
((count >= 2)) || { echo "No clicks on foreground overlapping target ($count)"; cat "$work/app.log"; exit 1; }
xdotool key --clearmodifiers ctrl+shift+F8
sleep 2
before=$(cat "$work/count"); sleep 2; [[ $(cat "$work/count") == "$before" ]]
echo "Actual foreground overlapping target received $count clicks; F8 stopped the run"

# Raise the app and park on it: a finite run must stay paused until stopped.
/usr/bin/python3 - "$app_pid" <<'PY'
import sys, time, pyatspi
pid = int(sys.argv[1])
def walk(node, depth=0):
    if depth > 40:
        return
    yield node
    try:
        for child in node:
            yield from walk(child, depth + 1)
    except (LookupError, RuntimeError, NotImplementedError):
        return
for _ in range(60):
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() != pid:
                continue
            for node in walk(app):
                if node.getRoleName() == 'radio button' and 'times' in (node.name or ''):
                    action = node.queryAction()
                    if any(action.doAction(i) for i in range(action.nActions)):
                        print('Selected a single finite repetition for self-window protection')
                        sys.exit(0)
        except (LookupError, RuntimeError, NotImplementedError):
            continue
    time.sleep(.2)
raise SystemExit('Could not select a finite repetition')
PY
xdotool windowraise "$app" mousemove "$x" "$y"
old=$(cat "$work/count")
/usr/bin/python3 .github/scripts/linux-click-e2e/start.py "$app_pid"
sleep 5
[[ $(cat "$work/count") == "$old" ]] || { echo 'Unexpected click while app was topmost'; exit 1; }
/usr/bin/python3 .github/scripts/linux-click-e2e/start.py "$app_pid" 'Stop clicking'
xdotool windowraise "$target" mousemove "$x" "$y"
sleep 2
[[ $(cat "$work/count") == "$old" ]] || { echo 'Unexpected click after stopping'; exit 1; }
echo 'Topmost app window protected; stop while paused prevented clicks'
