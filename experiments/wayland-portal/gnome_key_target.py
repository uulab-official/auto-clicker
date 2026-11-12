#!/usr/bin/python3
"""Record keys received by one disposable GNOME test window."""
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0')
from gi.repository import Gtk, Gdk

window = Gtk.Window(title='Isolated key delivery target')
window.set_default_size(500, 300)
entry = Gtk.Entry()
entry.set_placeholder_text('Isolated keyboard target')
window.add(entry)
window.add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK)
def on_key(_window, event):
    print(f'TARGET_KEY type={event.type.value_nick} key={Gdk.keyval_name(event.keyval)} code={event.hardware_keycode}', flush=True)
    return False
window.connect('key-press-event', on_key)
window.connect('key-release-event', on_key)
entry.connect('key-press-event', on_key)
entry.connect('key-release-event', on_key)
window.connect('focus-in-event', lambda *_: print('TARGET_FOCUS_IN', flush=True))
window.connect('focus-out-event', lambda *_: print('TARGET_FOCUS_OUT', flush=True))
window.connect('destroy', Gtk.main_quit)
window.show_all()
entry.grab_focus()
window.present()
print('KEY_TARGET_READY', flush=True)
Gtk.main()
