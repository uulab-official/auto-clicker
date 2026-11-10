#!/usr/bin/python3
"""Start only the target app using its accessibility action on the isolated VM."""
import sys
import time
import pyatspi

pid = int(sys.argv[1])

def walk(node, depth=0):
    if depth > 40:
        return False
    try:
        if node.name == 'Start clicking' and node.getRoleName() in ('push button', 'button'):
            action = node.queryAction()
            for i in range(action.nActions):
                if action.getName(i).lower() in ('click', 'press', 'activate') and action.doAction(i):
                    return True
        return any(walk(child, depth + 1) for child in node)
    except (LookupError, RuntimeError, NotImplementedError, AttributeError):
        return False

end = time.monotonic() + 60
while time.monotonic() < end:
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() == pid and walk(app):
                sys.exit(0)
        except (LookupError, RuntimeError, AttributeError):
            continue
    time.sleep(1)
raise SystemExit('Unable to activate Start clicking in target application')
