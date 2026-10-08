#!/usr/bin/env python3
"""Hold screen-blanking and sleep inhibitions until killed. No timeout.

An inhibition is tied to the D-Bus *connection*, so a one-shot `qdbus`/`busctl`
call is useless — it releases the moment the tool exits. This keeps a connection
open and does nothing else, so the lifetime is exactly the lifetime of this
process, which is what a toggle wants.

Both channels are the ones KDE's own battery applet uses, read from powerdevil's
source (applets/batterymonitor/plugin/inhibitmonitor_p.cpp), where its inhibit
button calls beginSuppressingSleep() and beginSuppressingScreenPowerManagement():

    screen: org.freedesktop.ScreenSaver  /ScreenSaver
            Inhibit(app, reason) -> cookie   /  UnInhibit(cookie)

    sleep:  org.freedesktop.PowerManagement.Inhibit
            /org/freedesktop/PowerManagement/Inhibit
            Inhibit(app, reason) -> cookie   /  UnInhibit(cookie)

Note the SHORT path for the screensaver one. /org/freedesktop/ScreenSaver exists
as a bus name but is not where the object lives, and calling it grants a cookie
that does nothing.

PolicyAgent's ListInhibitions/HasInhibition do NOT report either of these when
held by an external process, so do not use them to check whether it worked —
they only track PowerDevil's own clients. Verify behaviourally instead.

The caller pairs this with `systemd-inhibit --what=idle:sleep` for the logind
half, since we have not isolated which layer actually carries it.
"""

import signal
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib      # noqa: E402

APP = "quickshell-rice"
REASON = "Keep awake"

TARGETS = [
    ("screen", "org.freedesktop.ScreenSaver", "/ScreenSaver",
     "org.freedesktop.ScreenSaver"),
    ("sleep", "org.freedesktop.PowerManagement.Inhibit",
     "/org/freedesktop/PowerManagement/Inhibit",
     "org.freedesktop.PowerManagement.Inhibit"),
]


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    held = []

    for name, service, path, iface in TARGETS:
        try:
            cookie = bus.call_sync(
                service, path, iface, "Inhibit",
                GLib.Variant("(ss)", (APP, REASON)),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, -1, None,
            ).unpack()[0]
            held.append((name, service, path, iface, cookie))
        except GLib.Error as e:
            # One channel failing is not fatal: the other may still hold.
            print("%s inhibit failed: %s" % (name, e), file=sys.stderr)

    if not held:
        return 1

    print("held " + " ".join("%s=%d" % (n, c) for n, _, _, _, c in held), flush=True)

    loop = GLib.MainLoop()

    def stop(*_):
        # Explicit release as well as connection teardown, so a killed process
        # never leaves the machine pinned awake.
        for _name, service, path, iface, cookie in held:
            try:
                bus.call_sync(
                    service, path, iface, "UnInhibit",
                    GLib.Variant("(u)", (cookie,)), None,
                    Gio.DBusCallFlags.NONE, 2000, None,
                )
            except GLib.Error:
                pass
        loop.quit()
        return False

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, stop)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, stop)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
