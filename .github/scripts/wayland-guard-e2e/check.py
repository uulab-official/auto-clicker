#!/usr/bin/python3
"""Check the unmodified app's fail-closed state on a real Wayland compositor."""
import os
import sys
import time
import pyatspi

pid = int(sys.argv[1])
deadline = time.monotonic() + 45
while time.monotonic() < deadline:
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() != pid:
                continue
            stack = [app]
            disabled_start = False
            wayland_warning = False
            while stack:
                node = stack.pop()
                if 'Wayland global emergency shortcuts are not supported' in (node.name or ''):
                    wayland_warning = True
                if node.name == 'Start clicking' and node.getRoleName() in ('push button', 'button'):
                    if not node.getState().contains(pyatspi.STATE_ENABLED):
                        disabled_start = True
                stack.extend(list(node))
            if disabled_start and wayland_warning:
                print(f'Actual app {pid}: Wayland warning shown and Start clicking disabled', flush=True)
                sys.exit(0)
        except (LookupError, RuntimeError, NotImplementedError):
            continue
    try:
        os.kill(pid, 0)
    except OSError:
        raise SystemExit('App terminated before Wayland state could be checked')
    time.sleep(.2)
raise SystemExit('Wayland disabled control not found')
