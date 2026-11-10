#!/usr/bin/python3
"""Activate a named control only in the target app on the isolated VM."""
import sys
import time
import pyatspi

pid = int(sys.argv[1])
name = sys.argv[2] if len(sys.argv) > 2 else 'Start clicking'
desired = int(sys.argv[3]) if len(sys.argv) > 3 else 0

def walk(node, matches, depth=0):
    if depth > 40:
        return False
    try:
        # aria-pressed mode selectors are exposed as toggle buttons by WebKit.
        if node.name == name and node.getRoleName() in ('push button', 'button', 'toggle button'):
            matches.append(node)
            if len(matches) - 1 != desired:
                return False
            action = node.queryAction()
            for i in range(action.nActions):
                if action.getName(i).lower() in ('click', 'press', 'activate') and action.doAction(i):
                    return True
        return any(walk(child, matches, depth + 1) for child in node)
    except (LookupError, RuntimeError, NotImplementedError, AttributeError):
        return False

end = time.monotonic() + 60
while time.monotonic() < end:
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() == pid and walk(app, []):
                sys.exit(0)
        except (LookupError, RuntimeError, AttributeError):
            continue
    time.sleep(1)
raise SystemExit(f'Unable to activate {name!r} occurrence {desired} in target application')
