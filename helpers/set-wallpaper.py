#!/usr/bin/env python3
"""Set the Plasma desktop wallpaper (images and videos) and fire the theming hook.

Both go to our own wallpaper plugin, which does the transition itself.
Service name is lowercase `org.kde.plasmashell`, interface is CamelCase
`org.kde.PlasmaShell`; swapping them gives a bare "Cannot find ... evaluateScript".

Usage:
    set-wallpaper.py <path>                     # image or video
    set-wallpaper.py <path> --screen 0          # one screen only (default: all)
    set-wallpaper.py <path> --transition wind   # a name from the plugin, or random
    set-wallpaper.py <path> --duration 900      # transition length in ms
    set-wallpaper.py <path> --no-theme          # set it, but do not re-theme
    set-wallpaper.py --current                  # print what is set now, change nothing
"""

import argparse
import json
import os
import subprocess
import sys

VIDEO_EXTS = {".mp4", ".mkv", ".mov", ".webm"}
PLUGIN = "org.serpantinum.wallpaper"


def evaluate(script):
    """Run a script through plasmashell. Returns (ok, output)."""
    try:
        r = subprocess.run(
            ["qdbus6", "org.kde.plasmashell", "/PlasmaShell",
             "org.kde.PlasmaShell.evaluateScript", script],
            capture_output=True, text=True, timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, str(e)
    if r.returncode != 0:
        return False, (r.stderr or r.stdout).strip()
    return True, r.stdout.strip()


def is_video(path):
    return os.path.splitext(path)[1].lower() in VIDEO_EXTS


def js_string(s):
    """Quote for embedding in the JS we hand plasmashell."""
    return json.dumps(str(s))


def screen_guard(screen):
    if screen is None:
        return "true"
    return "d.screen === %d" % int(screen)


def apply(path, screen, transition=None, duration=None):
    url = "file://" + os.path.abspath(path)
    writes = []
    if transition:
        writes.append("d.writeConfig('Transition', %s);" % js_string(transition))
    if duration is not None:
        writes.append("d.writeConfig('Duration', %d);" % int(duration))
    # Image last: the plugin starts the transition when it changes.
    writes.append("d.writeConfig('Image', %s);" % js_string(url))
    return """
var ds = desktops();
for (var i = 0; i < ds.length; i++) {
    var d = ds[i];
    if (d.screen === -1) continue;
    if (!(%s)) continue;
    d.wallpaperPlugin = %s;
    d.currentConfigGroup = ['Wallpaper', %s, 'General'];
    %s
}
""" % (screen_guard(screen), js_string(PLUGIN), js_string(PLUGIN),
       "\n    ".join(writes))


def read_current():
    ok, out = evaluate("""
var ds = desktops();
var out = [];
for (var i = 0; i < ds.length; i++) {
    var d = ds[i];
    if (d.screen === -1) continue;
    d.currentConfigGroup = ['Wallpaper', d.wallpaperPlugin, 'General'];
    out.push(d.screen + '\\t' + d.wallpaperPlugin + '\\t'
             + (d.readConfig('Image') || ''));
}
print(out.join('\\n'));
""")
    return ok, out


STATE_FILE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "quickshell", "wallpaper", "current")


def write_state(path):
    """One absolute path, plain text. Read by our own renderer, and the same
    shape matugen/KMY's `file=` option consumes, so theming needs no second
    source of truth."""
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(os.path.abspath(path) + "\n")
        os.replace(tmp, STATE_FILE)          # atomic: a watcher never sees a partial line
    except OSError as exc:
        print("warning: could not write %s: %s" % (STATE_FILE, exc), file=sys.stderr)


HOOK = os.path.expanduser("~/.config/matugen/matugen-plasma-hook.sh")


def run_hook(path):
    """Detached: a full matugen run takes seconds and must not stall the picker."""
    if not os.access(HOOK, os.X_OK):
        print("warning: theming hook missing: %s" % HOOK, file=sys.stderr)
        return
    try:
        subprocess.Popen(
            [HOOK, os.path.abspath(path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,          # survives this process exiting
        )
    except OSError as exc:
        print("warning: could not start %s: %s" % (HOOK, exc), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("path", nargs="?")
    ap.add_argument("--screen", type=int, default=None)
    ap.add_argument("--transition", default=None,
                    help="a transition name from the plugin, or random")
    ap.add_argument("--duration", type=int, default=None,
                    help="transition length in milliseconds")
    ap.add_argument("--current", action="store_true")
    ap.add_argument("--no-theme", action="store_true",
                    help="set the wallpaper without re-running theming")
    ap.add_argument("--dry-run", action="store_true",
                    help="print the script that would run, change nothing")
    args = ap.parse_args()

    if args.current:
        ok, out = read_current()
        print(out if ok else "error: " + out)
        return 0 if ok else 1

    if not args.path:
        ap.error("a wallpaper path is required")
    if not os.path.isfile(args.path):
        print("no such file: %s" % args.path, file=sys.stderr)
        return 1

    script = apply(args.path, args.screen, args.transition, args.duration)

    if args.dry_run:
        print(script.strip())
        return 0

    ok, out = evaluate(script)
    if not ok:
        print("failed: %s" % out, file=sys.stderr)
        return 1
    write_state(args.path)
    if not args.no_theme:
        run_hook(args.path)
    print("set %s (%s)" % (args.path, "video" if is_video(args.path) else "image"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
