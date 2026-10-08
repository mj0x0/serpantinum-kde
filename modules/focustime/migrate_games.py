#!/usr/bin/env python3
"""One-shot: canonicalise historic game rows to `game:<Title>`.

Before this, the same game could occupy two rows (Steam's `steam:<title>` key and
Heroic's raw `<exe>` class), and every installer dialog Steam ever showed became a
row of its own. Rewrites both into the single canonical key games.resolve()
produces, summing durations, and deletes the dialog noise.

Idempotent: rows already keyed `game:` are left alone. Pass --apply to write;
without it, prints what would change.
"""
import os
import sqlite3
import sys

import games

DB = os.path.join(
    os.environ.get("QS_STATE_FOCUSTIME",
                   os.path.expanduser("~/.local/state/quickshell/focustime")),
    "focustime.db")

TABLES = {                       # table -> columns identifying a row besides class
    "focus_log":       ["log_date"],
    "focus_hourly":    ["log_date", "hour"],
    "focus_intervals": ["log_date", "interval_idx"],
    "focus_minutes":   ["log_date", "minute_idx"],
}


def canonical(app_class, app_title=""):
    """New key for an old row, or None to delete it."""
    if not app_class or app_class.startswith("game:"):
        return app_class
    cls = app_class.lower()

    if cls.startswith("steam:"):
        title = app_class[6:]
        if games.is_junk_title(title):
            return None
        g = games.resolve("steam_app_default", title)
        return g["key"] if g else None

    # steam_app_default is Steam's shared fallback class and its rows carry different
    # titles, so the whole class becomes one honest unidentified bucket.
    if cls == "steam_app_default":
        return "game:Steam Game"

    if cls.endswith(".exe") or cls.startswith("steam_app"):
        g = games.resolve(app_class, app_title or "")
        return g["key"] if g else None

    return app_class


def main():
    apply = "--apply" in sys.argv
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row

    # focus_log carries the title, so build the class->title map from it first.
    titles = {r["app_class"]: (r["app_title"] or "")
              for r in conn.execute("SELECT app_class, app_title FROM focus_log")}

    renames, drops = {}, set()
    for cls in titles:
        new = canonical(cls, titles.get(cls, ""))
        if new is None:
            drops.add(cls)
        elif new != cls:
            renames[cls] = new

    print(f"{'APPLYING' if apply else 'DRY RUN'} on {DB}")
    print(f"  {len(renames)} classes to merge, {len(drops)} to drop")
    for a, b in sorted(renames.items()):
        print(f"    {a!r:52} -> {b!r}")
    for d in sorted(drops):
        print(f"    DROP {d!r}")
    if not apply:
        print("\n  (re-run with --apply to write)")
        return

    cur = conn.cursor()
    for table, keys in TABLES.items():
        cur.execute(f"DELETE FROM {table} WHERE app_class IN ({','.join('?' * len(drops))})",
                    tuple(drops)) if drops else None
        for old, new in renames.items():
            group = ", ".join(keys)
            # Merge into any existing row with the new key, then remove the old.
            cur.execute(
                f"""INSERT INTO {table} ({group}, app_class, seconds)
                    SELECT {group}, ?, SUM(seconds) FROM {table}
                    WHERE app_class = ? GROUP BY {group}
                    ON CONFLICT({group}, app_class)
                    DO UPDATE SET seconds = seconds + excluded.seconds""",
                (new, old))
            cur.execute(f"DELETE FROM {table} WHERE app_class = ?", (old,))

    # focus_log also stores a display title — refresh it for the merged rows.
    for _, new in renames.items():
        cur.execute("UPDATE focus_log SET app_title = ? WHERE app_class = ?",
                    (new[5:] if new.startswith("game:") else new, new))
    conn.commit()
    print("  done.")


if __name__ == "__main__":
    main()
