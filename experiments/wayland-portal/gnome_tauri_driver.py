#!/usr/bin/python3
"""Drive a test app inside a disposable, private GNOME CI desktop."""
import os
import pathlib
import subprocess
import sys
import time
import pyatspi

assert os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('WAYLAND_DISPLAY') == 'wayland-ci'
pid, received, marker = int(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
assert str(marker).startswith(os.environ['XDG_RUNTIME_DIR'] + '/')
def walk(node):
    yield node
    for child in node:
        yield from walk(child)
def start_button():
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() != pid:
                continue
            for node in walk(app):
                if node.getRoleName() in ('button', 'push button') and node.name == 'Start clicking' and node.getState().contains(pyatspi.STATE_ENABLED):
                    return node
        except (AttributeError, LookupError, RuntimeError, NotImplementedError):
            continue
    return None
def until(predicate, seconds=30):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        found = predicate()
        if found:
            return found
        time.sleep(.01)
    raise RuntimeError('Timed out waiting for test state')

start = until(start_button)
action = start.queryAction()
assert any(action.doAction(i) for i in range(action.nActions)), 'Could not start the app'
subprocess.run(['/usr/bin/python3', 'experiments/wayland-portal/gnome_approve.py', 'xdg-desktop-portal-gnome', 'Remote Desktop', '--enable-remote'], check=True)
subprocess.run(['/usr/bin/python3', 'experiments/wayland-portal/gnome_approve.py', 'xdg-desktop-portal-gnome', 'Remote Desktop', 'Share'], check=True)
until(lambda: received.exists() and received.stat().st_size > 0)
marker.touch()
print('First actual GNOME target click received; sending test emergency shortcut', flush=True)
until(start_button, 10)
time.sleep(2)
clicks = received.read_text().splitlines()
assert len(clicks) == 1, f'Expected one click before emergency stop, got {clicks}'
print('One target click and stopped app verified', flush=True)
