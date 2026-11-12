#!/usr/bin/python3
"""Activate a named portal button only in the disposable CI desktop."""
import os
import subprocess
import sys
import time

assert os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('CI') == 'true'
assert os.environ.get('WAYLAND_DISPLAY') == 'wayland-ci'
if '--once' not in sys.argv:
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        attempt = subprocess.run([sys.executable, __file__, '--once', *sys.argv[1:]], capture_output=True, text=True)
        if attempt.returncode == 0:
            print(attempt.stdout, flush=True)
            sys.exit(0)
        time.sleep(.3)
    print(attempt.stdout + attempt.stderr, file=sys.stderr)
    raise RuntimeError('Could not activate isolated portal dialog')

import pyatspi
app_name, frame_name, button_name = sys.argv[2:]
def walk(node):
    try:
        yield node
        for child in node:
            yield from walk(child)
    except (AttributeError, LookupError, RuntimeError, NotImplementedError):
        return
for app in pyatspi.Registry.getDesktop(0):
    try:
        if app.name != app_name:
            continue
        if frame_name == '--shell':
            for node in walk(app):
                if node.getRoleName() in ('button', 'push button') and node.name == button_name:
                    action = node.queryAction()
                    print(f'Found shell {button_name}: showing={node.getState().contains(pyatspi.STATE_SHOWING)}, enabled={node.getState().contains(pyatspi.STATE_ENABLED)}, actions={action.nActions}', flush=True)
                    if any(action.doAction(i) for i in range(action.nActions)):
                        print(f'Activated isolated GNOME Shell {button_name}', flush=True)
                        sys.exit(0)
            continue
        for frame in walk(app):
            if frame.getRoleName() != 'frame' or frame.name != frame_name:
                continue
            if button_name == '--enable-remote':
                switches = [node for node in walk(frame) if node.getRoleName() == 'switch' and node.name == 'Allow Remote Interaction']
                for switch in reversed(switches):
                    try:
                        if switch.getState().contains(pyatspi.STATE_CHECKED):
                            print('Isolated remote interaction is already enabled', flush=True)
                            sys.exit(0)
                        action = switch.queryAction()
                        if any(action.doAction(i) for i in range(action.nActions)):
                            print('Enabled isolated remote interaction', flush=True)
                            sys.exit(0)
                    except (AttributeError, LookupError, RuntimeError, NotImplementedError):
                        continue
            for node in walk(frame):
                if node.getRoleName() in ('button', 'push button') and node.name == button_name:
                    action = node.queryAction()
                    print(f'Found isolated {app_name}/{frame_name}/{button_name}, enabled={node.getState().contains(pyatspi.STATE_ENABLED)}, actions={action.nActions}', flush=True)
                    if any(action.doAction(i) for i in range(action.nActions)):
                        print('Portal action dispatched', flush=True)
                        sys.exit(0)
    except (AttributeError, LookupError, RuntimeError, NotImplementedError):
        continue
sys.exit(1)
