#!/usr/bin/env python3
"""file-search.py <query> [limit] [baloo|fd]: name-matching files and folders as JSON.

Baloo's index when it is enabled (name-only via filename: terms), fd otherwise or
when Baloo has nothing, since Baloo only matches term prefixes. Icons come from Gio.
"""

import json
import os
import subprocess
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio  # noqa: E402

HOME = os.path.expanduser("~")


def baloo_enabled():
    try:
        with open(os.path.join(HOME, ".config", "baloofilerc")) as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k.strip() == "Indexing-Enabled":
                    return v.strip().lower() != "false"
    except OSError:
        pass
    return True


def run(argv):
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return out.stdout.splitlines()


def search_baloo(query, limit):
    words = [w.replace('"', "") for w in query.split()]
    words = [w for w in words if w]
    if not words:
        return None
    lines = run(["baloosearch6", "-l", str(limit), " ".join("filename:" + w for w in words)])
    if lines is None:
        return None
    return [l for l in lines if l.startswith("/")]


def search_fd(query, limit):
    lines = run(["fd", "-i", "-F", "--max-results", str(limit), query, HOME])
    if lines is None:
        return []
    return [l.rstrip("/") for l in lines if l.startswith("/")]


def rank(path, q):
    base = os.path.basename(path).lower()
    if base == q:
        return 0
    if base.startswith(q):
        return 1
    if q in base:
        return 2
    return 3


def describe(path):
    try:
        info = Gio.File.new_for_path(path).query_info(
            "standard::icon,standard::type", Gio.FileQueryInfoFlags.NONE, None)
    except Exception:
        return None
    is_dir = info.get_file_type() == Gio.FileType.DIRECTORY
    names = info.get_icon().get_names() if info.get_icon() else []
    parent = os.path.dirname(path)
    if parent == HOME or parent.startswith(HOME + "/"):
        parent = "~" + parent[len(HOME):]
    return {
        "name": os.path.basename(path),
        "desc": parent,
        "icon": names[0] if names else ("folder" if is_dir else "text-x-generic"),
        "path": path,
        "type": "dir" if is_dir else "file",
    }


def main():
    query = sys.argv[1].strip() if len(sys.argv) > 1 else ""
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    backend = sys.argv[3] if len(sys.argv) > 3 else ""
    results = []
    if len(query) >= 2:
        # Over-fetch so ranking, not index order, decides what survives the cut.
        fetch = max(limit * 4, 60)
        paths = None
        if backend != "fd" and baloo_enabled():
            paths = search_baloo(query, fetch)
        if not paths and backend != "baloo":
            paths = search_fd(query, fetch)
        q = query.lower()
        seen = set()
        for p in sorted(paths or [], key=lambda p: (rank(p, q), len(p))):
            if p in seen:
                continue
            seen.add(p)
            row = describe(p)
            if row:
                results.append(row)
    json.dump({"query": query, "results": results[:limit]}, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
