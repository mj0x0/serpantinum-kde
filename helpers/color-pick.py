#!/usr/bin/env python3
"""Screen colour eyedropper via xdg-desktop-portal.

Uses org.freedesktop.portal.Screenshot.PickColor — the same native picker Qt's
"pick screen color" and Plasma's colour widget use. On KDE this shows the
magnifier eyedropper; click a pixel and it returns the colour over D-Bus. No
wlr-screencopy / grim / spectacle / ImageMagick needed.

Prints "#rrggbb" (lowercase) on success; prints nothing and exits 1 on cancel.
"""
import os
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()

# Subscribe to the Response BEFORE calling, on the predictable handle path
# (portal spec: options.handle_token → /request/<sender>/<token>) to avoid a race.
token = "qscolorpick%d" % os.getpid()
sender = bus.get_unique_name()[1:].replace(".", "_")
handle = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)

loop = GLib.MainLoop()
out = {}


def on_response(response, results):
    # response: 0 = success, 1 = cancelled, 2 = ended some other way
    if response == 0 and "color" in results:
        r, g, b = (float(c) for c in results["color"])
        out["hex"] = "#%02x%02x%02x" % (
            max(0, min(255, round(r * 255))),
            max(0, min(255, round(g * 255))),
            max(0, min(255, round(b * 255))),
        )
    loop.quit()


bus.add_signal_receiver(
    on_response,
    signal_name="Response",
    dbus_interface="org.freedesktop.portal.Request",
    path=handle,
)

portal = bus.get_object("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop")
screenshot = dbus.Interface(portal, "org.freedesktop.portal.Screenshot")
try:
    screenshot.PickColor("", {"handle_token": token})
except dbus.DBusException as e:
    print("PickColor failed: %s" % e, file=sys.stderr)
    sys.exit(2)

GLib.timeout_add_seconds(120, loop.quit)  # safety net
loop.run()

if "hex" in out:
    print(out["hex"])
    # Also persist to a state file so the ColorPicker tab picks it up even if the
    # Floating panel collapsed while the portal eyedropper had the screen.
    try:
        state_dir = os.path.join(
            os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
            "quickshell", "colorpicker",
        )
        os.makedirs(state_dir, exist_ok=True)
        with open(os.path.join(state_dir, "last_pick"), "w") as f:
            f.write(out["hex"] + "\n")
    except OSError:
        pass
    sys.exit(0)
sys.exit(1)
