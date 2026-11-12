#!/usr/bin/python3
"""Test target; receives input only inside a private headless compositor."""
import sys
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
from gi.repository import Gdk, Gtk

path = sys.argv[1]
window = Gtk.Window(title='Isolated Wayland target')
window.fullscreen()
window.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
window.connect('destroy', Gtk.main_quit)
last_event = None

def clicked(_window, event):
    global last_event
    print(f'target button={event.button} type={event.type.value_nick} time={event.time}', flush=True)
    # GTK can emit one Wayland event twice while propagating it through the
    # toplevel. Count the underlying timestamp+button once.
    identity = (event.time, event.button, event.type)
    if event.button == 1 and event.type == Gdk.EventType.BUTTON_PRESS and identity != last_event:
        last_event = identity
        with open(path, 'a', encoding='utf8') as out:
            out.write('click\n')
    return True

window.connect('button-press-event', clicked)
window.show_all()
print('TARGET_READY', flush=True)
Gtk.main()
