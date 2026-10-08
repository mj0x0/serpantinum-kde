#!/usr/bin/env python3
# render-config.py <out.toml>: builds matugen's config from apps.json + the apps ticked in Settings.
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
EXTRAS = "user.toml"


def quote(v):
    if isinstance(v, bool) or not isinstance(v, (str, int)):
        raise ValueError(f"unsupported value {v!r}")
    if isinstance(v, int):
        return str(v)
    return json.dumps(v, ensure_ascii=False)


def table(t, path=None):
    name = t["name"]
    bare = name and all(c.isascii() and (c.isalnum() or c in "_-") for c in name)
    lines = [f"[templates.{name if bare else quote(name)}]"]
    for k, v in t.items():
        if k == "name":
            continue
        if path is not None and isinstance(v, str) and k != "input_path":
            v = v.replace("{path}", path)
        lines.append(f"{k} = {quote(v)}")
    return "\n".join(lines) + "\n"


def settings():
    try:
        with open(os.path.join(CONFIG_HOME, "quickshell", "settings.json"), encoding="utf-8") as f:
            app = json.load(f).get("appearance", {})
    except (OSError, ValueError, AttributeError):
        return set(), {}, EXTRAS
    if not isinstance(app, dict):
        return set(), {}, EXTRAS
    apps = app.get("apps")
    paths = app.get("appPaths")
    extras = app.get("userToml")
    apps = {a for a in apps if isinstance(a, str)} if isinstance(apps, list) else set()
    # A name, not a path: it always sits beside this script.
    extras = os.path.basename(extras.strip()) if isinstance(extras, str) else ""
    return apps, paths if isinstance(paths, dict) else {}, extras or EXTRAS


def render(catalog):
    ticked, paths, extras = settings()
    out = ["[config]\n"]
    out += [table(t) for t in catalog["core"]]
    for app in catalog["apps"]:
        if app["key"] not in ticked:
            continue
        path = None
        if app.get("path"):
            path = paths.get(app["key"])
            path = path.strip().rstrip("/") if isinstance(path, str) else ""
            if not path:
                continue
        out += [table(t, path) for t in app["templates"]]
    user = os.path.join(HERE, extras)
    if os.path.isfile(user):
        with open(user, encoding="utf-8") as f:
            out.append(f.read())
    return "\n".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: render-config.py <out.toml>")
    dest = sys.argv[1]
    try:
        with open(os.path.join(HERE, "apps.json"), encoding="utf-8") as f:
            text = render(json.load(f))
    except (OSError, ValueError, KeyError, TypeError) as e:
        sys.exit(f"render-config: broken catalog: {e}")
    d = os.path.dirname(os.path.abspath(dest))
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".config.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, dest)
    except BaseException:
        os.unlink(tmp)
        raise


if __name__ == "__main__":
    main()
