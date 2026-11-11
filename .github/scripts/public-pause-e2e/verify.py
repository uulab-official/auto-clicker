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
    end = time.monotonic() + 30
    while time.monotonic() < end:
        try:
            node = find(lambda n: n.name == name and n.getRoleName() in ('push button', 'button'), 2)
            action = node.queryAction()
            for i in range(action.nActions):
                if action.getName(i).lower() in ('click', 'press', 'activate') and action.doAction(i):
                    return
        except (LookupError, RuntimeError, NotImplementedError):
            pass
        time.sleep(.3)
    raise RuntimeError(f'Could not activate {name}')

# Use the finite count already set to one, then leave the pointer inside the app.
radio = find(lambda n: n.getRoleName() == 'radio button' and 'times' in (n.name or ''))
actions = radio.queryAction()
if not any(actions.doAction(i) for i in range(actions.nActions)):
    raise RuntimeError('Could not select finite repetition')
app_window = subprocess.check_output(['xdotool', 'search', '--onlyvisible', '--name', '^Auto Clicker$'], text=True).splitlines()[0]
geometry = subprocess.check_output(['xdotool', 'getwindowgeometry', '--shell', app_window], text=True)
coords = dict(line.split('=', 1) for line in geometry.splitlines() if '=' in line)
x = int(coords['X']) + 30
y = int(coords['Y']) + 100
print(f'App target location {x},{y}', flush=True)
def over_app():
    subprocess.run(['xdotool', 'mousemove', str(x), str(y)], check=True)
def on_target():
    subprocess.run(['xdotool', 'mousemove', '1150', '900'], check=True)
def text(value):
    return find(lambda n: value in (n.name or ''), 15)
def count():
    return len(events.read_text().splitlines())

over_app()
press('Start clicking')
time.sleep(6) # past the three-second default delay
text('Stop clicking')
if count() != 0:
    raise RuntimeError('Target received a click while paused')
text('Stop clicking')
on_target()
end = time.monotonic() + 15
while time.monotonic() < end and count() < 1:
    time.sleep(.2)
text('Start clicking')
time.sleep(2)
if count() != 1:
    raise RuntimeError(f'Finite paused run should produce exactly one click after resuming; got {count()}')
print('Finite paused run resumed and delivered exactly one click', flush=True)
events.write_text('')
over_app()
press('Start clicking')
time.sleep(6) # past the three-second default delay
text('Stop clicking')
press('Stop clicking')
text('Start clicking')
on_target()
time.sleep(4)
if count() != 0:
    raise RuntimeError('Click was delivered after stopping during pause')
print('UI Stop during pause prevented the pending click', flush=True)
