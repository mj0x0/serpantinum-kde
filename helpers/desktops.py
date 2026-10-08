#!/usr/bin/env python3
"""KDE virtual desktops over D-Bus, for Settings -> Bar -> Workspaces.

    desktops.py count                  how many there are
    desktops.py set <n> [--dry-run]    create or remove desktops at the end until there are n

KWin persists the result in kwinrc; the ws-listener re-emits, so the bar follows.
"""
import sys

import dbus

IFACE = "org.kde.KWin.VirtualDesktopManager"


def vdm():
    obj = dbus.SessionBus().get_object("org.kde.KWin", "/VirtualDesktopManager")
    return dbus.Interface(obj, IFACE), dbus.Interface(obj, "org.freedesktop.DBus.Properties")


def desktops(props):
    return sorted(props.Get(IFACE, "desktops"), key=lambda d: int(d[0]))


def main():
    args = sys.argv[1:]
    if not args or args[0] == "count":
        _, props = vdm()
        print(len(desktops(props)))
        return 0
    if args[0] == "set" and len(args) >= 2:
        n = max(1, min(20, int(args[1])))
        dry = "--dry-run" in args
        mgr, props = vdm()
        cur = desktops(props)
        while len(cur) < n:
            pos = len(cur)
            name = "Desktop %d" % (pos + 1)
            print("create", pos, name)
            if not dry:
                mgr.createDesktop(dbus.UInt32(pos), name)
            cur.append((pos, "", name))
        while len(cur) > n:
            d = cur.pop()
            print("remove", d[2], d[1])
            if not dry:
                mgr.removeDesktop(str(d[1]))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
