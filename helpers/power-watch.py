#!/usr/bin/env python3
"""Print a JSON snapshot of power posture on start and after every change: the profile
and who is holding the machine awake. Signal-driven; nothing polls.

RequestedInhibitions is a(ssssu) = (type, who, why, mode, granted); granted 0 = blocked.
Blocks persist in powerdevilrc [Inhibitions] BlockedInhibitions, which also names apps
that are blocked but not asking right now, so those are listed too.
"""

import json
import os
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib      # noqa: E402

SERVICE = "org.kde.Solid.PowerManagement"
PROFILE_PATH = "/org/kde/Solid/PowerManagement/Actions/PowerProfile"
PROFILE_IFACE = "org.kde.Solid.PowerManagement.Actions.PowerProfile"
AGENT_PATH = "/org/kde/Solid/PowerManagement/PolicyAgent"
AGENT_IFACE = "org.kde.Solid.PowerManagement.PolicyAgent"
RC = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "powerdevilrc")

# PolicyAgent HasInhibition bits.
SLEEP_BIT = 1
SCREEN_BIT = 4

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
pending = 0
owned = True    # False only once PowerDevil has actually left the bus


def call(path, iface, method, args=None, reply=None):
    try:
        return bus.call_sync(SERVICE, path, iface, method, args,
                             GLib.VariantType(reply) if reply else None,
                             Gio.DBusCallFlags.NONE, 2000, None).unpack()
    except GLib.Error:
        return None


def prop(path, iface, name):
    r = call(path, "org.freedesktop.DBus.Properties", "Get",
             GLib.Variant("(ss)", (iface, name)), "(v)")
    return r[0] if r else None


def blocked_entries():
    section = None
    try:
        with open(RC, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("["):
                    section = line
                elif section == "[Inhibitions]" and line.startswith("BlockedInhibitions="):
                    return [e for e in line.split("=", 1)[1].split(",") if e]
    except OSError:
        pass
    return []


def has(bit):
    r = call(AGENT_PATH, AGENT_IFACE, "HasInhibition", GLib.Variant("(u)", (bit,)), "(b)")
    return bool(r and r[0])


def snapshot():
    profile = call(PROFILE_PATH, PROFILE_IFACE, "currentProfile", reply="(s)")
    if profile is None:
        # A timed-out call is not an empty machine: skip the snapshot unless PowerDevil is gone.
        return None if owned else {"available": False}

    requested = prop(AGENT_PATH, AGENT_IFACE, "RequestedInhibitions")
    if requested is None:
        return None

    choices = call(PROFILE_PATH, PROFILE_IFACE, "profileChoices", reply="(as)")
    holds = call(PROFILE_PATH, PROFILE_IFACE, "profileHolds", reply="(aa{sv})")
    degraded = call(PROFILE_PATH, PROFILE_IFACE, "performanceDegradedReason", reply="(s)")

    # One entry per app+reason; the same pair can be requested for several types.
    merged = {}
    order = []
    for _kind, who, why, _mode, granted in requested:
        key = (who, why)
        if key not in merged:
            merged[key] = {"who": who, "why": why, "granted": False, "asking": True}
            order.append(key)
        merged[key]["granted"] = merged[key]["granted"] or granted != 0
    for entry in blocked_entries():
        who, _, why = entry.partition(":")
        if (who, why) not in merged:
            merged[(who, why)] = {"who": who, "why": why, "granted": False, "asking": False}
            order.append((who, why))

    return {
        "available": True,
        "profile": profile[0],
        "choices": list(choices[0]) if choices else [],
        "holds": holds[0] if holds else [],
        "degraded": degraded[0] if degraded else "",
        "inhibitions": [merged[k] for k in order],
        "sleep": has(SLEEP_BIT),
        "screen": has(SCREEN_BIT),
    }


def emit():
    global pending
    pending = 0
    snap = snapshot()
    if snap is not None:
        print(json.dumps(snap, default=str), flush=True)
    return False


def appeared(*_):
    global owned
    owned = True
    schedule()


def vanished(*_):
    global owned
    owned = False
    schedule()


def schedule(*_):
    # Changes arrive in bursts (properties, then the file); one snapshot per burst.
    global pending
    if not pending:
        pending = GLib.timeout_add(120, emit)


def main():
    for path in (PROFILE_PATH, AGENT_PATH):
        bus.signal_subscribe(SERVICE, None, None, path, None, Gio.DBusSignalFlags.NONE, schedule)
    Gio.bus_watch_name_on_connection(bus, SERVICE, Gio.BusNameWatcherFlags.NONE, appeared, vanished)
    monitor = Gio.File.new_for_path(RC).monitor_file(Gio.FileMonitorFlags.NONE, None)
    monitor.connect("changed", schedule)

    emit()
    GLib.MainLoop().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
