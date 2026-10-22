#!/usr/bin/env python3
"""osd module for helpers/rice-bridge.py: every org.kde.osdService method call Plasma would
have drawn (eavesdropped on a private monitor connection) and the primary display's
brightness from org.kde.ScreenBrightness.
"""
import json
import sys

import dbus
import dbus.bus
import dbus.lowlevel
import dbus.mainloop.glib
from gi.repository import GLib

OSD_PATH = "/org/kde/osdService"
OSD_IFACE = "org.kde.osdService"
OSD_RULE = f"type='method_call',path='{OSD_PATH}',interface='{OSD_IFACE}'"

BRI_SERVICE = "org.kde.ScreenBrightness"
BRI_PATH = "/org/kde/ScreenBrightness"
BRI_IFACE = "org.kde.ScreenBrightness"
DISPLAY_IFACE = "org.kde.ScreenBrightness.Display"
PROPS = "org.freedesktop.DBus.Properties"


def plain(v):
    if isinstance(v, (dbus.Struct, dbus.Array, list, tuple)):
        return [plain(x) for x in v]
    if isinstance(v, (dbus.Dictionary, dict)):
        return {str(k): plain(x) for k, x in v.items()}
    if isinstance(v, bool):
        return bool(v)
    if isinstance(v, (dbus.Double, float)):
        return float(v)
    if isinstance(v, (dbus.Byte, dbus.Int16, dbus.Int32, dbus.Int64,
                      dbus.UInt16, dbus.UInt32, dbus.UInt64, int)):
        return int(v)
    if isinstance(v, (dbus.ByteArray, bytes)):
        return v.decode("utf-8", "replace")
    return str(v)


def _print(tag, text):
    print(text, flush=True)


def _warn(msg):
    print(f"# osd_watch: {msg}", file=sys.stderr, flush=True)


def _start_osd(emit):
    conn = dbus.bus.BusConnection(dbus.bus.BusConnection.TYPE_SESSION)
    conn.call_blocking("org.freedesktop.DBus", "/org/freedesktop/DBus",
                       "org.freedesktop.DBus.Monitoring", "BecomeMonitor", "asu",
                       ([OSD_RULE], dbus.UInt32(0)))

    def flt(c, msg):
        if isinstance(msg, dbus.lowlevel.MethodCallMessage):
            try:
                emit("osd", json.dumps({"m": str(msg.get_member() or ""),
                                        "a": plain(msg.get_args_list())}))
            except Exception as e:  # noqa: BLE001
                _warn(f"osd emit failed: {e}")
        return dbus.lowlevel.HANDLER_RESULT_HANDLED
    conn.add_message_filter(flt)
    return conn


class _Brightness:
    def __init__(self, bus, emit):
        self.bus = bus
        self.emit = emit
        self.primary = ""

    def _props(self, path):
        return dbus.Interface(self.bus.get_object(BRI_SERVICE, path), PROPS)

    def _payload(self, name, value, maximum):
        label = ""
        try:
            label = str(self._props(f"{BRI_PATH}/{name}").Get(DISPLAY_IFACE, "Label"))
        except dbus.DBusException:
            pass
        value, maximum = int(value), int(maximum)
        pct = round(value * 100 / maximum) if maximum > 0 else 0
        return {"display": name, "label": label, "value": value, "max": maximum, "percent": pct}

    def refresh(self, *_):
        try:
            names = self._props(BRI_PATH).Get(BRI_IFACE, "DisplaysDBusNames")
            self.primary = str(names[0]) if len(names) else ""
            if not self.primary:
                self.emit("bri", json.dumps({"display": ""}))
                return
            props = self._props(f"{BRI_PATH}/{self.primary}")
            value = props.Get(DISPLAY_IFACE, "Brightness")
            maximum = props.Get(DISPLAY_IFACE, "MaxBrightness")
            self.emit("bri", json.dumps(self._payload(self.primary, value, maximum)))
        except Exception as e:  # noqa: BLE001
            _warn(f"brightness refresh failed: {e}")
            self.primary = ""
            self.emit("bri", json.dumps({"display": ""}))

    def changed(self, display, brightness, *_):
        if str(display) != self.primary or not self.primary:
            return
        try:
            maximum = self._props(f"{BRI_PATH}/{self.primary}").Get(DISPLAY_IFACE, "MaxBrightness")
            self.emit("bri", json.dumps(self._payload(self.primary, brightness, maximum)))
        except Exception as e:  # noqa: BLE001
            _warn(f"brightness changed failed: {e}")

    def range_changed(self, display, maximum, brightness, *_):
        if str(display) != self.primary or not self.primary:
            return
        try:
            self.emit("bri", json.dumps(self._payload(self.primary, brightness, maximum)))
        except Exception as e:  # noqa: BLE001
            _warn(f"brightness range failed: {e}")

    def connect(self):
        kw = dict(dbus_interface=BRI_IFACE, path=BRI_PATH)
        self.bus.add_signal_receiver(self.changed, signal_name="BrightnessChanged", **kw)
        self.bus.add_signal_receiver(self.range_changed, signal_name="BrightnessRangeChanged", **kw)
        self.bus.add_signal_receiver(self.refresh, signal_name="DisplayAdded", **kw)
        self.bus.add_signal_receiver(self.refresh, signal_name="DisplayRemoved", **kw)
        self.refresh()


def start(bus, loop, ns="", emit=_print):
    handles = []
    try:
        handles.append(_start_osd(emit))
    except Exception as e:  # noqa: BLE001
        _warn(f"osd monitor unavailable: {e}")
    bri = _Brightness(bus, emit)
    try:
        bri.connect()
    except Exception as e:  # noqa: BLE001
        _warn(f"brightness unavailable: {e}")
        emit("bri", json.dumps({"display": ""}))
    handles.append(bri)
    return handles


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    handles = start(bus, loop, emit=lambda tag, text: print(tag + "\t" + text, flush=True))  # noqa: F841
    loop.run()


if __name__ == "__main__":
    main()
