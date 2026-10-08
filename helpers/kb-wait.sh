#!/usr/bin/env bash
# Block until the keyboard layout changes, then exit (TopBar re-fetches).
# Python D-Bus one-shot — reliable, unlike `gdbus monitor` (GLib-buffered when piped).
exec python3 -c '
import dbus, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
loop = GLib.MainLoop()
bus.add_signal_receiver(lambda *a: loop.quit(),
                        signal_name="layoutChanged",
                        dbus_interface="org.kde.KeyboardLayouts")
loop.run()
'
