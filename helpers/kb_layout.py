#!/usr/bin/env python3
"""kb module for helpers/rice-bridge.py: the KDE keyboard layout short code (us / il / …)
on start and on every org.kde.KeyboardLayouts.layoutChanged — what kb-fetch.sh and
kb-wait.sh did between them, resolved the same way (getLayout index into getLayoutsList).
"""
import dbus
import dbus.mainloop.glib
from gi.repository import GLib

SERVICE = "org.kde.KWin"
OBJ_PATH = "/Layouts"
IFACE = "org.kde.KeyboardLayouts"


def current(bus):
    try:
        layouts = dbus.Interface(bus.get_object(SERVICE, OBJ_PATH), IFACE)
        try:
            idx = int(layouts.getLayout())
        except dbus.DBusException:
            idx = 0
        names = layouts.getLayoutsList()
    except dbus.DBusException:
        return ""
    return str(names[idx][0]) if 0 <= idx < len(names) else ""


def _print(tag, text):
    print(text, flush=True)


def start(bus, loop, ns="", emit=_print):
    def changed(*_):
        code = current(bus)
        if code:
            emit("kb", code)
    bus.add_signal_receiver(changed, signal_name="layoutChanged", dbus_interface=IFACE)
    changed()


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    start(bus, loop)
    loop.run()


if __name__ == "__main__":
    main()
