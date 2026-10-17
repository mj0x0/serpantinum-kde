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

Standalone (main) it is launched by the TopBar as a child Process (see
TopBar.qml wsDaemon). start(bus, loop, ns, emit) runs the same thing inside
helpers/rice-bridge.py; it prints nothing, so emit is unused.
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


def bus_name(ns=""):
    return BUS_NAME + ("." + ns if ns else "")


def listener_dst(ns=""):
    return os.path.join(RUNTIME, "qs-mj0x0-" + (ns + "-" if ns else "") + "ws-listener.js")


def run_dir(ns=""):
    return os.path.join(RUNTIME, "quickshell" + ("-" + ns if ns else ""))


def ws_file(ns=""):
    return os.path.join(run_dir(ns), "workspaces", "workspaces.json")


def fs_file(ns=""):
    return os.path.join(run_dir(ns), "fullscreen")


LISTENER_DST = listener_dst()
WS_FILE = ws_file()
FS_FILE = fs_file()


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


def _setup_listener(ns=""):
    dst = listener_dst(ns)
    try:
        if ns:
            with open(LISTENER_SRC) as f:
                js = f.read()
            # Only the destination is namespaced; the exported interface stays io.quickshell.ws.
            js = js.replace('callDBus("%s"' % BUS_NAME, 'callDBus("%s"' % bus_name(ns))
            with open(dst, "w") as f:
                f.write(js)
        else:
            shutil.copyfile(LISTENER_SRC, dst)
    except OSError as e:
        print(f"# ws-listener copy failed: {e}", file=sys.stderr, flush=True)
        return
    _load_kwin_script(dst)


def _script_loaded(path):
    res = _busctl("call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
                  "isScriptLoaded", "s", path)
    return res.returncode == 0 and res.stdout.strip().endswith("true")


# Anything that runs KWin scripts BY ID (kdotool does, every call) can stop ours
# instead of its own, since KWin hands out ids as scripts.size(). Reload when gone.
def _ensure_listener(ns=""):
    if not _script_loaded(listener_dst(ns)):
        print("# listener gone, reloading", file=sys.stderr, flush=True)
        _setup_listener(ns)
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
    def __init__(self, bus_name, ns=""):
        super().__init__(bus_name, OBJ_PATH)
        self._ws_file = ws_file(ns)
        self._fs_file = fs_file(ns)

    # inbound: called by the KWin listener on every change
    @dbus.service.method(IFACE, in_signature="s")
    def update(self, state_json):
        _write(self._ws_file, str(state_json))
        return True

    # inbound: fullscreen state of the active window ("0"/"1")
    @dbus.service.method(IFACE, in_signature="s")
    def fullscreen(self, val):
        _write(self._fs_file, str(val))
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


def start(bus, loop, ns="", emit=None):
    name = bus_name(ns)

    # Replaced by a newer bridge (shell reload or restart): exit instead of lingering.
    def on_name_lost(lost):
        if str(lost) == name:
            loop.quit()
    bus.add_signal_receiver(on_name_lost, signal_name="NameLost",
                            dbus_interface="org.freedesktop.DBus")

    owner = dbus.service.BusName(
        name, bus=bus,
        allow_replacement=True, replace_existing=True, do_not_queue=True,
    )
    ws = WS(owner, ns)
    _setup_listener(ns)
    GLib.timeout_add_seconds(10, _ensure_listener, ns)
    return ws


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    ws = start(bus, loop)  # noqa: F841  keeps the BusName alive for the loop's lifetime
    loop.run()


if __name__ == "__main__":
    main()
