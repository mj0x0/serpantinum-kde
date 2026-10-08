#!/usr/bin/env python3
# Atomically replace a JSON config under ~/.config/quickshell. Refuses anything that
# is not a JSON object, so a bad caller can never leave the file unparseable.
#
#   settings-write.py <json>                 -> settings.json
#   settings-write.py <json> --file <name>   -> that file instead
import json
import os
import subprocess
import sys
import tempfile

CONF_DIR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "quickshell")
DEFAULT_NAME = "settings.json"
HOOK = os.path.expanduser("~/.config/matugen/matugen-plasma-hook.sh")


def read_current(dest):
    try:
        with open(dest, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def retheme():
    """Re-run theming, detached. Fired only when appearance.* actually changed."""
    if not os.access(HOOK, os.X_OK):
        return
    try:
        subprocess.Popen([HOOK], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as exc:
        print("warning: could not start %s: %s" % (HOOK, exc), file=sys.stderr)


def main():
    args = sys.argv[1:]
    name = DEFAULT_NAME
    if "--file" in args:
        i = args.index("--file")
        name = os.path.basename(args[i + 1])
        del args[i:i + 2]
    dest = os.path.join(CONF_DIR, name)

    raw = args[0] if args else sys.stdin.read()

    try:
        obj = json.loads(raw)
    except ValueError as exc:
        print("refusing to write invalid JSON: %s" % exc, file=sys.stderr)
        return 1
    if not isinstance(obj, dict):
        print("refusing to write: top level must be an object", file=sys.stderr)
        return 1

    was = read_current(dest).get("appearance")

    os.makedirs(CONF_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CONF_DIR, prefix=".settings-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(obj, fh, indent=2, ensure_ascii=False, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, dest)          # atomic: a watcher never sees a partial file
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise

    if name == DEFAULT_NAME and obj.get("appearance") != was:
        retheme()
    return 0


if __name__ == "__main__":
    sys.exit(main())
