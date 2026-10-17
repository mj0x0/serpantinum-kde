#!/usr/bin/env python3
"""wm-bridge — the one unavoidable helper on KWin.

Quickshell can't own a D-Bus name and KWin won't expose a window-management
Wayland protocol to us, so this small daemon is the bridge:

  * owns the D-Bus name io.quickshell.wm
  * loads a persistent KWin listener that pushes window state here
  * re-emits each update as ONE JSON line on stdout — Quickshell reads it via
    Process + SplitParser (event-driven, no polling, no /tmp state files)
  * performs window actions (activate / close / minimize+genie) on demand by
    running transient KWin scripts

Standalone (main) it is launched by Quickshell as a child Process (see
WindowService.qml). start(bus, loop, ns, emit) runs the same thing inside
helpers/rice-bridge.py, which owns the bus and the loop.
"""
import os
import sys
import json
import shutil
import tempfile
import subprocess

import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = "io.quickshell.wm"
OBJ_PATH = "/wm"
IFACE = "io.quickshell.wm"

HELPER_DIR = os.path.dirname(os.path.abspath(__file__))
LISTENER_SRC = os.path.normpath(os.path.join(HELPER_DIR, "..", "kwin", "listener.js"))
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")


def bus_name(ns=""):
    return BUS_NAME + ("." + ns if ns else "")


def listener_dst(ns=""):
    return os.path.join(RUNTIME, "qs-mj0x0-" + (ns + "-" if ns else "") + "listener.js")


LISTENER_DST = listener_dst()


def _print(tag, text):
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


# ── KWin scripting plumbing ──────────────────────────────────────────────────
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


def _run_transient_js(js_text):
    fd, path = tempfile.mkstemp(prefix="qs-mj0x0-act-", suffix=".js", dir=RUNTIME)
    with os.fdopen(fd, "w") as f:
        f.write(js_text)
    _load_kwin_script(path)
    # start() returns before KWin has read the file, so unload and delete later.
    GLib.timeout_add(1500, _drop_transient, path)


def _drop_transient(path):
    _busctl("call", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting",
            "unloadScript", "s", path)
    try:
        os.unlink(path)
    except OSError:
        pass
    return False


def _setup_listener(ns=""):
    dst = listener_dst(ns)
    try:
        if ns:
            with open(LISTENER_SRC) as f:
                js = f.read()
            # Only the destination is namespaced; the exported interface stays io.quickshell.wm.
            js = js.replace('callDBus("%s"' % BUS_NAME, 'callDBus("%s"' % bus_name(ns))
            with open(dst, "w") as f:
                f.write(js)
        else:
            shutil.copyfile(LISTENER_SRC, dst)
    except OSError as e:
        print(f"# listener copy failed: {e}", file=sys.stderr, flush=True)
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


# ── action script templates ──────────────────────────────────────────────────
def _iter_windows(body):
    # `body` runs with `w` (KWin window) and `id` (stringified internalId).
    return (
        "var ws = workspace.windowList ? workspace.windowList() : workspace.stackingOrder;"
        "for (var i = 0; i < ws.length; i++) {"
        "  var w = ws[i]; var id = String(w.internalId);"
        + body +
        "}"
    )


def _js_activate(win_id):
    return _iter_windows(
        f"if (id === {json.dumps(win_id)}) {{ w.minimized = false; workspace.activeWindow = w; break; }}"
    )


def _js_close(win_id):
    return _iter_windows(
        f"if (id === {json.dumps(win_id)}) {{ w.closeWindow(); break; }}"
    )


def _js_minimize(ids, rect):
    return (
        f"var IDS = {json.dumps(list(ids))}; var R = {json.dumps(rect)};"
        + _iter_windows(
            "if (IDS.indexOf(id) !== -1) {"
            "  try { w.setMinimizeIconGeometry(Qt.rect(R.x, R.y, R.w, R.h)); } catch (e) {}"
            "  w.minimized = true;"
            "}"
        )
    )


# ── D-Bus object ─────────────────────────────────────────────────────────────
class WM(dbus.service.Object):
    def __init__(self, bus_name, emit=_print):
        super().__init__(bus_name, OBJ_PATH)
        self._emit = emit

    # inbound: called by the KWin listener on every change
    @dbus.service.method(IFACE, in_signature="s")
    def update(self, state_json):
        line = str(state_json).replace("\r", " ").replace("\n", " ").strip()
        self._emit("wm", line)
        return True

    # inbound: the focused window, every window at all (dialogs, the greeter),
    # not just the dock's. Raw resourceClass + caption, what kdotool used to report.
    _active = ("", "")

    @dbus.service.method(IFACE, in_signature="ss")
    def active(self, cls, title):
        WM._active = (str(cls), str(title))
        return True

    # outbound: polled by the FocusTime daemon instead of spawning kdotool.
    @dbus.service.method(IFACE, out_signature="ss")
    def activeWindow(self):
        return WM._active

    # outbound: fired by Quickshell via busctl
    @dbus.service.method(IFACE, in_signature="s")
    def activate(self, win_id):
        _run_transient_js(_js_activate(str(win_id)))
        return True

    @dbus.service.method(IFACE, in_signature="s")
    def closeWindow(self, win_id):
        _run_transient_js(_js_close(str(win_id)))
        return True

    @dbus.service.method(IFACE, in_signature="ss")
    def minimize(self, ids_json, rect_json):
        try:
            ids = json.loads(ids_json)
            rect = json.loads(rect_json)
        except ValueError:
            return False
        _run_transient_js(_js_minimize(ids, rect))
        return True


def start(bus, loop, ns="", emit=_print):
    name = bus_name(ns)

    # Replaced by a newer bridge (shell reload or restart): exit instead of lingering.
    def on_name_lost(lost):
        if str(lost) == name:
            loop.quit()
    bus.add_signal_receiver(on_name_lost, signal_name="NameLost",
                            dbus_interface="org.freedesktop.DBus")

    # Replace any stale instance so a Quickshell restart doesn't deadlock on the name.
    owner = dbus.service.BusName(
        name, bus=bus,
        allow_replacement=True, replace_existing=True, do_not_queue=True,
    )
    wm = WM(owner, emit)
    _setup_listener(ns)
    GLib.timeout_add_seconds(10, _ensure_listener, ns)
    return wm


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    wm = start(bus, loop)  # noqa: F841  keeps the BusName alive for the loop's lifetime
    loop.run()


if __name__ == "__main__":
    main()
