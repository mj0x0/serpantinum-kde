#!/usr/bin/env python3
"""file-search.py <query> [limit]: name-matching files and folders as JSON.

fd walks $HOME live -- ~80 ms on a 1.2 TB home, under the launcher's debounce, so no
index daemon is worth its memory. Icons come from Gio.
"""

import json
import os
import subprocess
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio  # noqa: E402

HOME = os.path.expanduser("~")


def run(argv):
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return out.stdout.splitlines()


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
    results = []
    if len(query) >= 2:
        # Over-fetch so ranking, not walk order, decides what survives the cut.
        paths = search_fd(query, max(limit * 4, 60))
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
