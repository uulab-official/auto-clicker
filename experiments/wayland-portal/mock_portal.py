#!/usr/bin/python3
"""Mock D-Bus portal on a private CI bus; never emits real desktop input."""
import os
import sys
from gi.repository import Gio, GLib

mode, output = sys.argv[1:]
assert mode in ('click', 'stop', 'revoked', 'denied')
assert os.environ.get('GITHUB_ACTIONS') == 'true'
ROOT = '/org/freedesktop/portal/desktop'
XML = '''<node>
<interface name="org.freedesktop.portal.GlobalShortcuts">
 <method name="CreateSession"><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
 <method name="BindShortcuts"><arg type="o" direction="in"/><arg type="a(sa{sv})" direction="in"/><arg type="s" direction="in"/><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
 <property name="version" type="u" access="read"/>
 <signal name="Activated"><arg type="o"/><arg type="s"/><arg type="t"/><arg type="a{sv}"/></signal>
 <signal name="ShortcutsChanged"><arg type="o"/><arg type="a(sa{sv})"/></signal>
</interface>
<interface name="org.freedesktop.portal.RemoteDesktop">
 <method name="CreateSession"><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
 <method name="SelectDevices"><arg type="o" direction="in"/><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
 <method name="Start"><arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="a{sv}" direction="in"/><arg type="o" direction="out"/></method>
 <method name="NotifyPointerButton"><arg type="o" direction="in"/><arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="in"/></method>
 <property name="version" type="u" access="read"/>
</interface>
<interface name="org.freedesktop.portal.Session"><method name="Close"/><signal name="Closed"><arg type="a{sv}"/></signal></interface>
</node>'''
interfaces = Gio.DBusNodeInfo.new_for_xml(XML).interfaces
session_info = interfaces[2]
connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
connection.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'RequestName', GLib.Variant('(su)', ('org.freedesktop.portal.Desktop', 0)), GLib.VariantType.new('(u)'), Gio.DBusCallFlags.NONE, -1, None)
state = {'shortcut': None, 'remote': None, 'sender': None}

def text(value):
    return value.unpack() if isinstance(value, GLib.Variant) else value

def req(sender, opts):
    return ROOT + '/request/' + sender[1:].replace('.', '_') + '/' + text(opts['handle_token'])

def session(sender, opts):
    return ROOT + '/session/' + sender[1:].replace('.', '_') + '/' + text(opts['session_handle_token'])

def reply_later(sender, path, code, data):
    def fire():
        connection.emit_signal(sender, path, 'org.freedesktop.portal.Request', 'Response', GLib.Variant('(ua{sv})', (code, data)))
        return False
    GLib.timeout_add(60, fire)

def stop_later(sender):
    def fire():
        if mode == 'stop':
            connection.emit_signal(sender, ROOT, 'org.freedesktop.portal.GlobalShortcuts', 'Activated', GLib.Variant('(osta{sv})', (state['shortcut'], 'emergency-stop', 1, {})))
        elif mode == 'revoked':
            connection.emit_signal(sender, state['shortcut'], 'org.freedesktop.portal.Session', 'Closed', GLib.Variant('(a{sv})', ({},)))
        return False
    GLib.timeout_add(300, fire)

def method(_conn, sender, path, iface, method_name, params, invocation):
    args = params.unpack()
    if iface == 'org.freedesktop.portal.Session':
        invocation.return_value(None)
        return
    if method_name == 'NotifyPointerButton':
        with open(output, 'a', encoding='utf8') as out:
            out.write(f'{args[2]} {args[3]}\n')
        invocation.return_value(None)
        return
    opts = args[-1]
    request = req(sender, opts)
    values = {}
    code = 0
    if method_name == 'CreateSession':
        selected = session(sender, opts)
        state['shortcut' if iface.endswith('GlobalShortcuts') else 'remote'] = selected
        state['sender'] = sender
        connection.register_object(selected, session_info, method, None, None)
        values = {'session_handle': GLib.Variant('s', selected)}
    elif method_name == 'BindShortcuts':
        shortcuts = [] if mode == 'denied' else [('emergency-stop', {'description': GLib.Variant('s', 'Emergency stop'), 'trigger_description': GLib.Variant('s', 'Ctrl+Shift+F8')})]
        values = {'shortcuts': GLib.Variant('a(sa{sv})', shortcuts)}
    elif method_name == 'Start':
        values = {'devices': GLib.Variant('u', 2)}
        if mode in ('stop', 'revoked'):
            stop_later(sender)
    invocation.return_value(GLib.Variant('(o)', (request,)))
    reply_later(sender, request, code, values)

def prop(_conn, _sender, _path, _iface, name):
    return GLib.Variant('u', 1) if name == 'version' else None

connection.register_object(ROOT, interfaces[0], method, prop, None)
connection.register_object(ROOT, interfaces[1], method, prop, None)
print('MOCK_PORTAL_READY', flush=True)
GLib.MainLoop().run()
