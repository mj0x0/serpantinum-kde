#!/usr/bin/env python3
"""rice-bridge — the shell's one helper daemon: wm-bridge, ws-bridge, power-watch and the
keyboard-layout watcher on a single session bus and GLib loop (see services/bridge/Bridge.qml).

stdout, one record per line, a tab after the tag:
  wm     <json array>   the window list, as wm-bridge prints it
  power  <json object>  power-watch's snapshot
  kb     us | il | …    keyboard layout code, on start and on every layoutChanged
  osd    <json object>  {"m": member, "a": [args]} per org.kde.osdService method call
  bri    <json object>  primary display brightness {display, label, value, max, percent}
ws prints nothing; it keeps writing $XDG_RUNTIME_DIR/quickshell/workspaces/workspaces.json
and $XDG_RUNTIME_DIR/quickshell/fullscreen.

--namespace NAME keeps a test instance clear of the live shell: bus names
io.quickshell.wm.NAME / io.quickshell.ws.NAME, listener copies qs-mj0x0-NAME-listener.js /
qs-mj0x0-NAME-ws-listener.js, runtime dir quickshell-NAME. Losing either bus name
(a newer daemon replaced us) exits the process; the QML Process restarts it.
"""
import argparse
import importlib.util
import os
import sys

import dbus
import dbus.mainloop.glib
from gi.repository import GLib

HELPER_DIR = os.path.dirname(os.path.abspath(__file__))


def _load(name, filename):
    # The bridges keep their hyphenated file names, so import them by path.
    spec = importlib.util.spec_from_file_location(name, os.path.join(HELPER_DIR, filename))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def _emit(tag, text):
    sys.stdout.write(tag + "\t" + text + "\n")
    sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser(description="Quickshell helper daemon (wm, ws, power, kb).")
    ap.add_argument("--namespace", default="", metavar="NAME",
                    help="suffix bus names, listener copies and the runtime dir for a test instance")
    ns = ap.parse_args().namespace

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()

    def on_name_lost(name):
        print(f"# lost {name}, exiting", file=sys.stderr, flush=True)
        loop.quit()
    bus.add_signal_receiver(on_name_lost, signal_name="NameLost",
                            dbus_interface="org.freedesktop.DBus")

    modules = [
        _load("wm_bridge", "wm-bridge.py"),
        _load("ws_bridge", "ws-bridge.py"),
        _load("power_watch", "power-watch.py"),
        _load("kb_layout", "kb_layout.py"),
        _load("osd_watch", "osd_watch.py"),
    ]
    handles = [m.start(bus, loop, ns, _emit) for m in modules]  # noqa: F841  BusNames live here
    loop.run()
    return 1


if __name__ == "__main__":
    sys.exit(main())
