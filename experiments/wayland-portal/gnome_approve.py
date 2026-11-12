#!/usr/bin/python3
"""Activate a named portal button only in the disposable CI desktop."""
import os
import sys
import time
import pyatspi

assert os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('CI') == 'true'
assert os.environ.get('WAYLAND_DISPLAY') == 'wayland-ci'
app_name, frame_name, button_name = sys.argv[1:]
def walk(node):
    yield node
    for child in node:
        yield from walk(child)
deadline = time.monotonic() + 30
while time.monotonic() < deadline:
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.name != app_name:
                continue
            for frame in walk(app):
                if frame.getRoleName() != 'frame' or frame.name != frame_name:
                    continue
                for node in walk(frame):
                    if node.getRoleName() in ('button', 'push button') and node.name == button_name:
                        if not node.getState().contains(pyatspi.STATE_ENABLED):
                            continue
                        action = node.queryAction()
                        if any(action.doAction(i) for i in range(action.nActions)):
                            print(f'Activated isolated {app_name}/{frame_name}/{button_name}', flush=True)
                            sys.exit(0)
        except (AttributeError, LookupError, RuntimeError, NotImplementedError):
            continue
    time.sleep(.2)
raise RuntimeError(f'Could not activate {app_name}/{frame_name}/{button_name}')
