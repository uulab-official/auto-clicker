#!/usr/bin/python3
"""Invoke the public app's install button through the target process's AT-SPI tree."""
import sys
import time
import pyatspi

pid = int(sys.argv[1])
probe = len(sys.argv) > 2 and sys.argv[2] == 'probe'
names = ({'Start clicking', '클릭 시작', 'クリックを開始'} if probe else
         {'Install update', '업데이트 설치', 'アップデートをインストール'})
seen = set()
more_names = {'More options', '추가 옵션', 'その他のオプション'}
opened_more = False

def walk(node, depth=0):
    global opened_more
    if depth > 40:
        return False
    try:
        name = node.name or ''
        role = node.getRoleName()
        if not probe and not opened_more and any(name.endswith(label) for label in more_names):
            action = node.queryAction()
            for index in range(action.nActions):
                if action.getName(index).lower() in ('click', 'press', 'activate') and action.doAction(index):
                    opened_more = True
                    print('Opened target application More options:', name, flush=True)
                    return False
        if role in ('push button', 'button'):
            seen.add(name)
            if name in names and node.getState().contains(pyatspi.STATE_SENSITIVE):
                if probe:
                    print('Target application button accessible:', name, flush=True)
                    return True
                action = node.queryAction()
                for index in range(action.nActions):
                    if action.getName(index).lower() in ('click', 'press', 'activate'):
                        if action.doAction(index):
                            print('Invoked target application update button:', name, flush=True)
                            return True
        for child in node:
            if walk(child, depth + 1):
                return True
    except (LookupError, RuntimeError, NotImplementedError, AttributeError):
        pass
    return False

end = time.monotonic() + 90
while time.monotonic() < end:
    desktop = pyatspi.Registry.getDesktop(0)
    for app in desktop:
        try:
            if app.get_process_id() == pid and walk(app):
                sys.exit(0)
        except (LookupError, RuntimeError, AttributeError):
            continue
    time.sleep(1)
print('Unable to invoke update button for PID', pid, 'buttons observed:', sorted(seen), file=sys.stderr)
sys.exit(1)
