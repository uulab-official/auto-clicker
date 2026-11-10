#!/usr/bin/python3
"""Drive only the test app in the disposable Xvfb session."""
import pathlib
import subprocess
import sys
import time
import pyatspi

pid = int(sys.argv[1])
events = pathlib.Path(sys.argv[2])

def walk(node, depth=0):
    if node is None or depth > 40:
        return
    yield node
    try:
        for child in node:
            yield from walk(child, depth + 1)
    except (LookupError, RuntimeError, NotImplementedError):
        return

def find(predicate, timeout=30):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        for app in pyatspi.Registry.getDesktop(0):
            try:
                if app.get_process_id() != pid:
                    continue
                for node in walk(app):
                    try:
                        if predicate(node):
                            return node
                    except (AttributeError, LookupError, RuntimeError, NotImplementedError):
                        continue
            except (LookupError, RuntimeError):
                continue
        time.sleep(0.2)
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() == pid:
                print('Application accessibility tree:', flush=True)
                for node in walk(app):
                    try:
                        if node.name or node.getRoleName() in ('spin button', 'entry', 'text'):
                            print(f'  {node.getRoleName()}: {node.name!r}', flush=True)
                    except (LookupError, RuntimeError, NotImplementedError):
                        continue
        except (LookupError, RuntimeError):
            continue
    raise RuntimeError('Could not find the required application control')

def press(name):
    node = find(lambda n: n.name == name and n.getRoleName() in ('push button', 'button'))
    action = node.queryAction()
    for i in range(action.nActions):
        if action.getName(i).lower() in ('click', 'press', 'activate') and action.doAction(i):
            return
    raise RuntimeError(f'Could not activate {name}')

def delay_field(node):
    # WebKitGTK exposes HTML number inputs as "embedded" rather than as
    # EditableText; grabFocus still targets the actual input element.
    return 'start delay' in (node.name or '').lower() and node.getRoleName() in ('embedded', 'spin button', 'text')

field = find(delay_field)
if not field.queryComponent().grabFocus():
    raise RuntimeError('Could not focus start delay input')
subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+a'], check=True)
subprocess.run(['xdotool', 'type', '--clearmodifiers', '4'], check=True)
subprocess.run(['xdotool', 'key', 'Tab'], check=True)
subprocess.run(['xdotool', 'mousemove', '1150', '900'], check=True)
time.sleep(0.3)
started = time.monotonic()
press('Start clicking')
end = started + 10
while time.monotonic() < end and not events.read_text().strip():
    time.sleep(0.05)
clicks = [float(line) for line in events.read_text().splitlines()]
if not clicks or clicks[0] - started < 3.7:
    raise RuntimeError(f'Expected first actual click after four-second delay; received {clicks}, started {started}')
print(f'First target click delivered after {clicks[0] - started:.2f}s')
subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+shift+F8'], check=True)
find(lambda n: n.name == 'Start clicking' and n.getRoleName() in ('push button', 'button'))
events.write_text('')
subprocess.run(['xdotool', 'mousemove', '1150', '900'], check=True)
press('Start clicking')
time.sleep(0.5)
subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+shift+F8'], check=True)
find(lambda n: n.name == 'Start clicking' and n.getRoleName() in ('push button', 'button'))
time.sleep(5)
if events.read_text().strip():
    raise RuntimeError('Target received a click after cancellation during the start delay')
print('Emergency stop during start delay prevented all target clicks')
