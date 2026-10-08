#!/usr/bin/env python3
"""Create a hidden-SSID NetworkManager profile. Idempotent, and never sees a secret.

The exact call, on the SYSTEM bus:

    destination  org.freedesktop.NetworkManager
    object       /org/freedesktop/NetworkManager/Settings
    interface    org.freedesktop.NetworkManager.Settings
    method       AddConnection(a{sa{sv}} connection) -> (o path)

This is the same NetworkManager D-Bus API Quickshell itself drives, not nmcli and not
iwctl. The profile is written WITHOUT 802-11-wireless-security.psk, so no passphrase ever
reaches a command line, an argv or the process table -- Quickshell's connectWithPsk() fills
the secret in afterwards, over its own connection. Everything the shell does after this
point is ordinary Quickshell.Networking.

Usage: nm-add-hidden.py <ssid> [wpa-psk|sae|none] [--dry-run]
Prints the connection object path on success, or a message on stderr and exit 1.
"""

import sys
import uuid

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NM = "org.freedesktop.NetworkManager"
SETTINGS_PATH = "/org/freedesktop/NetworkManager/Settings"
SETTINGS_IFACE = "org.freedesktop.NetworkManager.Settings"
CONN_IFACE = "org.freedesktop.NetworkManager.Settings.Connection"
KEY_MGMT = ("wpa-psk", "sae", "none")


def build(ssid, key_mgmt):
    conn = {
        "connection": {
            "id": GLib.Variant("s", ssid),
            "uuid": GLib.Variant("s", str(uuid.uuid4())),
            "type": GLib.Variant("s", "802-11-wireless"),
            "autoconnect": GLib.Variant("b", True),
        },
        "802-11-wireless": {
            "ssid": GLib.Variant("ay", ssid.encode("utf-8")),
            "mode": GLib.Variant("s", "infrastructure"),
            "hidden": GLib.Variant("b", True),
        },
        "ipv4": {"method": GLib.Variant("s", "auto")},
        "ipv6": {"method": GLib.Variant("s", "auto")},
    }
    if key_mgmt != "none":
        conn["802-11-wireless-security"] = {"key-mgmt": GLib.Variant("s", key_mgmt)}
    return GLib.Variant("a{sa{sv}}", conn)


def existing(bus, ssid):
    paths = bus.call_sync(
        NM, SETTINGS_PATH, SETTINGS_IFACE, "ListConnections",
        None, GLib.VariantType("(ao)"), Gio.DBusCallFlags.NONE, 10000, None,
    ).unpack()[0]
    for path in paths:
        try:
            s = bus.call_sync(
                NM, path, CONN_IFACE, "GetSettings",
                None, GLib.VariantType("(a{sa{sv}})"), Gio.DBusCallFlags.NONE, 10000, None,
            ).unpack()[0]
        except GLib.Error:
            continue
        w = s.get("802-11-wireless")
        if not w:
            continue
        raw = w.get("ssid")
        if raw is not None and bytes(raw).decode("utf-8", "replace") == ssid:
            return path
    return None


def main():
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry = "--dry-run" in sys.argv[1:]
    if not args or not args[0]:
        print("usage: nm-add-hidden.py <ssid> [wpa-psk|sae|none]", file=sys.stderr)
        return 1
    ssid = args[0]
    key_mgmt = args[1] if len(args) > 1 else "wpa-psk"
    if key_mgmt not in KEY_MGMT:
        print("unsupported key-mgmt: %s" % key_mgmt, file=sys.stderr)
        return 1

    settings = build(ssid, key_mgmt)
    if dry:
        print(settings.print_(True))
        return 0

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        found = existing(bus, ssid)
        if found:
            print(found)
            return 0
        path = bus.call_sync(
            NM, SETTINGS_PATH, SETTINGS_IFACE, "AddConnection",
            GLib.Variant.new_tuple(settings),
            GLib.VariantType("(o)"), Gio.DBusCallFlags.NONE, 20000, None,
        ).unpack()[0]
    except GLib.Error as err:
        print("AddConnection failed: %s" % err.message, file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
