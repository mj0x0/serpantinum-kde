#!/usr/bin/env bash
# Block until any MPRIS player changes state, then exit. Python D-Bus one-shot -
# `dbus-monitor | grep -m1` is block-buffered when piped.
exec python3 -c '
import dbus, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
loop = GLib.MainLoop()
def done(*a): loop.quit()
bus.add_signal_receiver(done, signal_name="PropertiesChanged",
                        dbus_interface="org.freedesktop.DBus.Properties",
                        arg0="org.mpris.MediaPlayer2.Player")
bus.add_signal_receiver(done, signal_name="Seeked",
                        dbus_interface="org.mpris.MediaPlayer2.Player")
loop.run()
'
