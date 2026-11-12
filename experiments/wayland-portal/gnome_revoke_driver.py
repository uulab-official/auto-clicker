#!/usr/bin/python3
"""Revoke only a test session in the private GNOME desktop."""
import os
import pathlib
import subprocess
import sys
import time
import pyatspi

assert os.environ.get('GITHUB_ACTIONS') == 'true' and os.environ.get('WAYLAND_DISPLAY') == 'wayland-ci'
pid, received, app_log = int(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
def walk(node):
    yield node
    for child in node:
        yield from walk(child)
def start_button():
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() == pid:
                for node in walk(app):
                    if node.getRoleName() in ('button', 'push button') and node.name == 'Start clicking' and node.getState().contains(pyatspi.STATE_ENABLED):
                        return node
        except (AttributeError, LookupError, RuntimeError, NotImplementedError):
            continue
def until(predicate, seconds=30):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = predicate()
        if value:
            return value
        time.sleep(.01)
    raise RuntimeError('Timed out waiting for isolated revoke test state')
node = until(start_button)
action = node.queryAction()
assert any(action.doAction(i) for i in range(action.nActions))
subprocess.run(['/usr/bin/python3', 'experiments/wayland-portal/gnome_approve.py', 'xdg-desktop-portal-gnome', 'Remote Desktop', '--enable-remote'], check=True)
subprocess.run(['/usr/bin/python3', 'experiments/wayland-portal/gnome_approve.py', 'xdg-desktop-portal-gnome', 'Remote Desktop', 'Share'], check=True)
until(lambda: 'CI Wayland app window hidden' in app_log.read_text())
subprocess.run(['/usr/bin/python3', 'experiments/wayland-portal/gnome_approve.py', 'gnome-shell', '--shell', 'Stop Screen Sharing'], check=True)
until(lambda: 'CI Wayland window restore requested' in app_log.read_text())
time.sleep(1)
assert not received.exists() or not received.read_text(), 'Target received a click after revoke'
assert 'CI observed remote session close' in app_log.read_text(), 'Remote session close was not observed'
print('GNOME Shell revoked remote control; app restored with no target click', flush=True)
