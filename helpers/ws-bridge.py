#!/usr/bin/env python3
"""ws-bridge — KDE virtual-desktop bridge for the ported TopBar.

The serpantinum TopBar reads its workspace pills from a JSON file written by an
external daemon (on Hyprland: workspaces.sh) and switches via another script.
This is the KDE replacement, mirroring wm-bridge:

  * owns the D-Bus name io.quickshell.ws
  * loads a persistent KWin listener (kwin/ws-listener.js) that pushes the
    workspace array here on every desktop/window change
  * writes it atomically to $XDG_RUNTIME_DIR/quickshell/workspaces/workspaces.json
    (atomic replace → inotify close_write → TopBar re-reads)
  * switch(n): jump to the n-th virtual desktop (1-based), via a transient
    KWin script

Launched by the TopBar as a child Process (see TopBar.qml wsDaemon).
"""
import os
import sys
import json
import shutil
import subprocess

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = "io.quickshell.ws"
OBJ_PATH = "/ws"
IFACE = "io.quickshell.ws"

HELPER_DIR = os.path.dirname(os.path.abspath(__file__))
LISTENER_SRC = os.path.normpath(os.path.join(HELPER_DIR, "..", "kwin", "ws-listener.js"))
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
LISTENER_DST = os.path.join(RUNTIME, "qs-mj0x0-ws-listener.js")
WS_FILE = os.path.join(RUNTIME, "quickshell", "workspaces", "workspaces.json")
FS_FILE = os.path.join(RUNTIME, "quickshell", "fullscreen")


# ── KWin scripting plumbing (same as wm-bridge) ──────────────────────────────
def _busctl(*args):
    return subprocess.run(["busctl", "--user", *args], capture_output=True, text=True)


def _load_kwin_script(path):
    # Never address /Scripting/Script<id>: KWin ids are scripts.size() and get reused,
    # so that path can belong to another live script. start() runs whatever is loaded.
    _busctl("call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
            "unloadScript", "s", path)
    res = _busctl("call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
                  "loadScript", "s", path)
    if res.returncode != 0 or res.stdout.strip().endswith("-1"):
        return
    _busctl("call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", "start")


def _desktop_id(n):
    vdm = dbus.SessionBus().get_object("org.kde.KWin", "/VirtualDesktopManager")
    desks = dbus.Interface(vdm, "org.freedesktop.DBus.Properties").Get(
        "org.kde.KWin.VirtualDesktopManager", "desktops")
    desks = sorted(desks, key=lambda d: int(d[0]))
    i = int(n) - 1
    return str(desks[i][1]) if 0 <= i < len(desks) else None


def _setup_listener():
    try:
        shutil.copyfile(LISTENER_SRC, LISTENER_DST)
    except OSError as e:
        print(f"# ws-listener copy failed: {e}", file=sys.stderr, flush=True)
        return
    _load_kwin_script(LISTENER_DST)


def _script_loaded(path):
    res = _busctl("call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
                  "isScriptLoaded", "s", path)
    return res.returncode == 0 and res.stdout.strip().endswith("true")


# Anything that runs KWin scripts BY ID (kdotool does, every call) can stop ours
# instead of its own, since KWin hands out ids as scripts.size(). Reload when gone.
def _ensure_listener():
    if not _script_loaded(LISTENER_DST):
        print("# listener gone, reloading", file=sys.stderr, flush=True)
        _setup_listener()
    return True


# In-place write so inotify's close_write fires for the TopBar's watchers; an
# atomic rename-replace would not, since the watch follows the old inode.
def _write(path, text):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)
    except OSError as e:
        print(f"# write {path} failed: {e}", file=sys.stderr, flush=True)


# ── D-Bus object ─────────────────────────────────────────────────────────────
class WS(dbus.service.Object):
    def __init__(self, bus_name):
        super().__init__(bus_name, OBJ_PATH)

    # inbound: called by the KWin listener on every change
    @dbus.service.method(IFACE, in_signature="s")
    def update(self, state_json):
        _write(WS_FILE, str(state_json))
        return True

    # inbound: fullscreen state of the active window ("0"/"1")
    @dbus.service.method(IFACE, in_signature="s")
    def fullscreen(self, val):
        _write(FS_FILE, str(val))
        return True

    # outbound: fired by the TopBar on pill click (busctl … switch i N)
    # A property set, not a transient KWin script, so there is nothing to collide with.
    @dbus.service.method(IFACE, in_signature="i")
    def switch(self, n):
        try:
            did = _desktop_id(n)
            if did:
                vdm = dbus.SessionBus().get_object("org.kde.KWin", "/VirtualDesktopManager")
                dbus.Interface(vdm, "org.freedesktop.DBus.Properties").Set(
                    "org.kde.KWin.VirtualDesktopManager", "current", dbus.String(did))
        except dbus.DBusException as e:
            print(f"# switch {n} failed: {e}", file=sys.stderr, flush=True)
        return True


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()

    # Replaced by a newer bridge (shell reload or restart): exit instead of lingering.
    def on_name_lost(name):
        if str(name) == BUS_NAME:
            loop.quit()
    bus.add_signal_receiver(on_name_lost, signal_name="NameLost",
                            dbus_interface="org.freedesktop.DBus")

    bus_name = dbus.service.BusName(
        BUS_NAME, bus=bus,
        allow_replacement=True, replace_existing=True, do_not_queue=True,
    )
    WS(bus_name)
    _setup_listener()
    GLib.timeout_add_seconds(10, _ensure_listener)
    loop.run()


if __name__ == "__main__":
    main()
