#!/usr/bin/python3
"""Exercise settings backup through the app and native GTK file choosers."""
import json
import pathlib
import subprocess
import sys
import time
import pyatspi

root = pathlib.Path(sys.argv[2])

def walk(node, depth=0):
    if node is None or depth > 50:
        return
    yield node
    try:
        for child in node:
            yield from walk(child, depth + 1)
    except (LookupError, RuntimeError, NotImplementedError):
        return

def nodes_for(pid):
    for app in pyatspi.Registry.getDesktop(0):
        try:
            if app.get_process_id() == pid:
                yield from walk(app)
        except (LookupError, RuntimeError):
            continue

def find(pid, predicate, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        for node in nodes_for(pid):
            try:
                if predicate(node):
                    return node
            except (AttributeError, LookupError, RuntimeError, NotImplementedError):
                continue
        time.sleep(.15)
    raise RuntimeError('Could not find a requested control in the app accessibility tree')

def press(pid, name):
    node = find(pid, lambda n: n.name == name and n.getRoleName() in ('push button', 'button'))
    action = node.queryAction()
    for index in range(action.nActions):
        if action.getName(index).lower() in ('click', 'press', 'activate') and action.doAction(index):
            return
    raise RuntimeError(f'Could not activate app button: {name}')

def has_text(node, expected):
    if expected in (node.name or ''):
        return True
    try:
        text = node.queryText().getText(0, -1)
        return expected in text
    except (LookupError, RuntimeError, NotImplementedError):
        return False

def number_field(pid):
    return find(pid, lambda n: 'start delay' in (n.name or '').lower()
                and n.getRoleName() in ('embedded', 'spin button', 'text'))

def set_delay(pid, value):
    node = number_field(pid)
    if not node.queryComponent().grabFocus():
        raise RuntimeError('Could not focus the start delay field')
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+a'], check=True)
    subprocess.run(['xdotool', 'type', '--clearmodifiers', str(value)], check=True)
    subprocess.run(['xdotool', 'key', 'Tab'], check=True)
    time.sleep(.2)

def focused_title():
    try:
        return subprocess.check_output(['xdotool', 'getwindowfocus', 'getwindowname'], text=True, timeout=2).strip()
    except subprocess.SubprocessError:
        return ''

def dump_windows():
    try:
        ids = subprocess.check_output(['xdotool', 'search', '--onlyvisible', '--name', '.*'], text=True, timeout=3).split()
    except subprocess.SubprocessError:
        ids = []
    print('Visible X11 windows:', flush=True)
    for window in ids:
        try:
            name = subprocess.check_output(['xdotool', 'getwindowname', window], text=True, timeout=2).strip()
            print(f'  {window}: {name!r}', flush=True)
        except subprocess.SubprocessError:
            continue

def dump_accessibility(pid):
    print('Application accessibility controls:', flush=True)
    for node in nodes_for(pid):
        try:
            if node.name:
                try:
                    enabled = node.getState().contains(pyatspi.STATE_ENABLED)
                except (LookupError, RuntimeError, NotImplementedError):
                    enabled = '?'
                print(f'  {node.getRoleName()}: {node.name!r} enabled={enabled}', flush=True)
        except (LookupError, RuntimeError, NotImplementedError):
            continue

def dump_desktop():
    print('Desktop accessibility applications:', flush=True)
    for app in pyatspi.Registry.getDesktop(0):
        try:
            app_pid = app.get_process_id()
            print(f'Application pid={app_pid} name={app.name!r}', flush=True)
            for node in walk(app):
                try:
                    role = node.getRoleName()
                    if node.name or role in ('file chooser', 'dialog', 'text', 'entry', 'push button'):
                        print(f'  {role}: {node.name!r}', flush=True)
                except (LookupError, RuntimeError, NotImplementedError):
                    continue
        except (LookupError, RuntimeError):
            continue

def wait_dialog(title, timeout=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        current = focused_title()
        if title.lower() in current.lower():
            return
        time.sleep(.1)
    dump_windows()
    app_pid = int(sys.argv[2]) if sys.argv[1] == 'test' else -1
    if app_pid > 0:
        dump_accessibility(app_pid)
    raise RuntimeError(f'Native file dialog {title!r} did not receive focus (active window: {focused_title()!r})')

def choose_path(title, path):
    wait_dialog(title)
    # GTK's native chooser exposes the location entry with Ctrl+L.
    subprocess.run(['xdotool', 'key', '--clearmodifiers', 'ctrl+l'], check=True)
    time.sleep(.25)
    subprocess.run(['xdotool', 'type', '--clearmodifiers', '--delay', '1', str(path)], check=True)
    subprocess.run(['xdotool', 'key', 'Return'], check=True)

def export(pid, path):
    press(pid, 'Export settings')
    choose_path('Export settings', path)
    end = time.monotonic() + 15
    while time.monotonic() < end and not path.is_file():
        time.sleep(.1)
    if not path.is_file():
        print(f'After save chooser: focused title={focused_title()!r}', flush=True)
        dump_windows()
        dump_accessibility(int(sys.argv[2]))
        dump_desktop()
        if len(sys.argv) > 4:
            portal_log = pathlib.Path(sys.argv[4])
            if portal_log.exists():
                print('File chooser portal D-Bus trace:', flush=True)
                print(portal_log.read_text(errors='replace'), flush=True)
        raise RuntimeError(f'Export did not create {path}')
    find(pid, lambda n: has_text(n, 'Settings exported.'), timeout=10)
    data = json.loads(path.read_text())
    if data.get('format') != 'auto-clicker-settings' or data.get('version') != 1:
        raise RuntimeError(f'Unexpected backup envelope: {data!r}')
    return data['settings']

def import_path(pid, path):
    press(pid, 'Import settings')
    choose_path('Import settings', path)

def main():
    if sys.argv[1] == 'prepare':
        root.mkdir(parents=True, exist_ok=True)
        (root / 'invalid.json').write_text('{"format":"auto-clicker-settings","version":99,"settings":{}}\n')
        return
    pid = int(sys.argv[2])
    files = pathlib.Path(sys.argv[3])
    valid = files / 'original.json'
    modified = files / 'modified.json'
    restored = files / 'restored.json'
    after_invalid = files / 'after-invalid.json'
    after_cancel = files / 'after-cancel.json'

    # Export settings with a non-default delay through the actual native save dialog.
    set_delay(pid, 3)
    original = export(pid, valid)
    if original['startDelayMs'] != 3000:
        raise RuntimeError(f'Expected exported 3000ms delay, got {original["startDelayMs"]}')

    # Change the live value, then import the earlier file through the native chooser.
    set_delay(pid, 7)
    changed = export(pid, modified)
    if changed['startDelayMs'] != 7000:
        raise RuntimeError(f'Expected changed 7000ms delay, got {changed["startDelayMs"]}')
    import_path(pid, valid)
    imported_notice = find(pid, lambda n: has_text(n, 'Settings imported.'), timeout=10)
    if not imported_notice:
        raise RuntimeError('Success confirmation for valid import was not shown')
    restored_settings = export(pid, restored)
    if restored_settings['startDelayMs'] != 3000:
        raise RuntimeError('Import did not restore the earlier exported settings')

    # Invalid input must surface an error without replacing the restored settings.
    import_path(pid, files / 'invalid.json')
    find(pid, lambda n: has_text(n, 'Could not import settings.'), timeout=10)
    preserved = export(pid, after_invalid)
    if preserved['startDelayMs'] != 3000:
        raise RuntimeError('Invalid import replaced the existing settings')

    # Cancel the open dialog with Escape and make sure the app remains usable.
    press(pid, 'Import settings')
    wait_dialog('Import settings')
    subprocess.run(['xdotool', 'key', 'Escape'], check=True)
    time.sleep(.5)
    preserved = export(pid, after_cancel)
    if preserved['startDelayMs'] != 3000:
        raise RuntimeError('Cancelling the import dialog changed settings')
    print('Exported 3000ms, changed to 7000ms, imported original, and preserved settings on invalid file and cancel')

if __name__ == '__main__':
    main()
