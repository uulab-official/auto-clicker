#!/usr/bin/python3
"""Drive one Tauri app in a disposable headless Sway session only."""
import json
import pathlib
import subprocess
import sys
import time
import pyatspi

pid, target_file, mode = int(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]

def walk(node):
    if node is None:
        return
    yield node
    for child in node:
        yield from walk(child)

def button(name, enabled=True):
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() != pid:
                continue
            for node in walk(app):
                if node.getRoleName() in ('button', 'push button') and node.name == name:
                    if not enabled or node.getState().contains(pyatspi.STATE_ENABLED):
                        return node
        except (AttributeError, LookupError, RuntimeError, NotImplementedError):
            continue
    return None

def contains_pid(node):
    if node.get('pid') == pid:
        return True
    return any(contains_pid(child) for child in node.get('nodes', []) + node.get('floating_nodes', []))

def visible():
    tree = json.loads(subprocess.check_output(['swaymsg', '-r', '-t', 'get_tree'], text=True))
    return contains_pid(tree)

def until(predicate, seconds=50):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(.1)
    raise RuntimeError(f'Timed out waiting for {predicate}')

until(visible)
start = until(lambda: button('Start clicking'))
action = start.queryAction()
assert any(action.doAction(i) for i in range(action.nActions)), 'Start could not be invoked'
until(lambda: not visible())
print('Tauri window unmapped before clicking', flush=True)
until(visible)
until(lambda: button('Start clicking', enabled=mode not in ('shortcut_closed', 'service_loss')))
print('Tauri window restored after stop or portal loss', flush=True)
time.sleep(2)
events = target_file.read_text().splitlines()
if mode == 'loop_stop' and len(events) != 1:
    raise RuntimeError(f'Expected one click before stop; got {events}')
if mode in ('remote_closed', 'shortcut_closed', 'service_loss') and events:
    raise RuntimeError(f'Unexpected click after portal closure: {events}')
print(f'Isolated Tauri target observed {len(events)} clicks for {mode}', flush=True)
