#!/usr/bin/python3
"""Test target; receives input only inside a private headless compositor."""
import sys
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gdk, Gtk

path = sys.argv[1]
window = Gtk.Window(title='Isolated Wayland target')
window.fullscreen()
window.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
window.connect('destroy', Gtk.main_quit)

def clicked(_window, event):
    print(f'target button={event.button} type={event.type.value_nick} time={event.time}', flush=True)
    if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS:
        with open(path, 'a', encoding='utf8') as out:
            out.write('click\n')
    return False

window.connect('button-press-event', clicked)
window.show_all()
print('TARGET_READY', flush=True)
Gtk.main()
