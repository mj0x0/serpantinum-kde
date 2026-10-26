#!/usr/bin/env python3
"""Dump the user's global shortcuts as JSON for the cheat sheet.

Reads ~/.config/kglobalshortcutsrc, which stores three different shapes:

  [kwin]
  Window Quick Tile Left=Meta+Left,Meta+Left,Quick Tile Window to the Left
      name = active,default,description   (description is the friendly label)

  [services][firefox.desktop]
  _launch=Meta+F
      no description — the label comes from the .desktop file's Name=

  [services][org.serpantinum.shell.desktop]
  bluetooth=Meta+B
      no description — the key IS an action id, so the label and the command come
      from that file's [Desktop Action bluetooth] block

Entries bound to "none" are skipped: an unbound action is noise on a cheat sheet.
Output: [{"group": str, "chords": [str], "label": str}, ...]
"""

import configparser
import json
import os
import re
import shlex
import sys

RC = os.path.expanduser("~/.config/kglobalshortcutsrc")
KWINRC = os.path.expanduser("~/.config/kwinrc")
APP_DIRS = [
    os.path.expanduser("~/.local/share/applications"),
    os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                 "kglobalaccel"),
    "/usr/share/applications",
    "/usr/share/kglobalaccel",
]

# Only the user's own custom shortcuts and window management reach the cheat sheet.
# Plasma/Power/Volume/Session are stock bindings on dedicated keys - left out.
INCLUDE_GROUPS = {"Window Management", "Applications", "Shell", "Media", "Polonium"}

GROUP_NAMES = {
    "kwin": "Window Management",
    "plasmashell": "Plasma",
    "services": "Applications",
    "mediacontrol": "Media Keys",   # KDE's own; distinct from the user's binds
    "org_kde_powerdevil": "Power",
    "ksmserver": "Session",
    "kmix": "Volume",
    "KDE Keyboard Layout Switcher": "Keyboard",
    "ActivityManager": "Activities",
    "kaccess": "Accessibility",
}


def disabled_scripts():
    """KWin script names explicitly disabled in kwinrc [Plugins].

    Shortcuts for a disabled script stay registered in kglobalshortcutsrc, so a
    naive dump lists dozens of keys that do nothing (Karousel alone contributes
    75 while switched off). A cheat sheet showing dead keys is worse than useless.
    """
    off = set()
    try:
        with open(KWINRC, "r", encoding="utf-8", errors="replace") as fh:
            in_plugins = False
            for line in fh:
                line = line.strip()
                if line.startswith("["):
                    in_plugins = line == "[Plugins]"
                    continue
                if in_plugins and line.lower().endswith("enabled=false"):
                    off.add(line.split("Enabled=")[0].strip().lower())
    except OSError:
        pass
    return off


SHELL_CMDS = {"qs", "quickshell", "skwd", "screenshot.sh"}
MEDIA_CMDS = {"playerctl", "playerctld", "mpc", "cmus-remote", "player_control.sh"}


def _desktop_path(desktop_id):
    for d in APP_DIRS:
        p = os.path.join(d, desktop_id)
        if os.path.exists(p):
            return p
    return ""


def desktop_entry(desktop_id):
    """Name= and Exec= from a .desktop file; Name falls back to the filename."""
    name = exe = ""
    p = _desktop_path(desktop_id)
    if p:
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if line.startswith("Name=") and not name:
                        name = line.split("=", 1)[1].strip()
                    elif line.startswith("Exec=") and not exe:
                        exe = line.split("=", 1)[1].strip()
        except OSError:
            pass
    if not name:
        name = re.sub(r"\.desktop$", "", desktop_id).replace("_", " ")
    return name, exe


def desktop_action(desktop_id, action):
    """Name= and Exec= from one [Desktop Action <action>] block, or ("", "").

    A grouped component binds one key per action id, so the rc key is the action
    name and the only place its label and command live is that block. No filename
    fallback: an empty name is how the caller learns the block is missing and the
    row has to degrade.
    """
    p = _desktop_path(desktop_id)
    if not p:
        return "", ""
    want = "[Desktop Action %s]" % action
    name = exe = ""
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as fh:
            inside = False
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("["):
                    if inside:
                        break
                    inside = line.strip() == want
                    continue
                if not inside:
                    continue
                if line.startswith("Name=") and not name:
                    name = line.split("=", 1)[1].strip()
                elif line.startswith("Exec=") and not exe:
                    exe = line.split("=", 1)[1].strip()
    except OSError:
        return "", ""
    return name, exe


def classify_service(exe):
    """Split the [services] dumping ground by what the entry actually RUNS.

    Every global shortcut with a .desktop file lands in [services], so "launch
    Firefox", "playerctl next" and "qs ipc call music toggle" arrive in one heap
    labelled Applications. Only the first is an application. The command name is
    the honest signal — the labels are free text and the ids are meaningless.
    """
    try:
        parts = shlex.split(exe)
    except ValueError:
        parts = exe.split()
    cmd = os.path.basename(parts[0]) if parts else ""
    if cmd in MEDIA_CMDS:
        return "Media"
    if cmd in SHELL_CMDS:
        return "Shell"
    return "Applications"


def pretty_keys(seq):
    """All usable chords for one action, e.g. ['Alt + F4', 'Super + Q'].

    Alternates are separated by a LITERAL backslash-t in the file (not a real tab),
    e.g. `Alt+Tab\\tMeta+Tab`. Showing only the first hides the user's own binding
    behind KDE's default — Close Window is stored `Alt+F4\\tMeta+Q`, and Super+Q is
    the one actually used. Incomplete chords (trailing "+") are skipped; a lone
    modifier is kept, since bare Meta is a real binding here; names containing
    spaces are kept too, since media keys are legitimately called "Volume Down"
    / "Launch (C)".
    """
    raw = seq.replace("\\t", "\t")
    raw = re.sub(r"\\{2,}", "\\\\", raw)      # kglobalshortcutsrc doubles backslashes
    out = []
    for alt in raw.split("\t"):
        alt = alt.strip()
        if not alt or alt.endswith("+"):
            continue
        parts = [p.strip() for p in alt.split("+") if p.strip()]
        if not parts:
            continue
        chord = " + ".join({"Meta": "Super"}.get(p, p) for p in parts)
        if chord not in out:
            out.append(chord)
    return out


NUM_TAIL = re.compile(r"^(.*?)(\d+)$")


def collapse_numbered(rows):
    """Fold families like "Switch to Desktop 1..7" into a single "Super + #" row.

    Twelve near-identical rows push everything else off the screen and tell the
    reader nothing they can't infer. Only collapses when the labels share a stem,
    the numbers are consecutive from 1, and the chords differ solely in that digit.
    """
    by_stem = {}
    for r in rows:
        m = NUM_TAIL.match(r["label"].strip())
        if not m or len(r["chords"]) != 1:
            continue
        stem, num = m.group(1).strip(), int(m.group(2))
        chord = r["chords"][0]
        cm = NUM_TAIL.match(chord.replace(" ", ""))
        if not cm:
            continue
        by_stem.setdefault((r["group"], stem, cm.group(1)), []).append((num, r))

    collapsed, drop = [], set()
    for (group, stem, chord_stem), members in by_stem.items():
        if len(members) < 3:
            continue
        members.sort()
        nums = [n for n, _ in members]
        if nums != list(range(nums[0], nums[0] + len(nums))):
            continue
        for _, r in members:
            drop.add(id(r))
        pretty_stem = " + ".join(
            p for p in re.findall(r"[A-Z][a-z]+|Super|Ctrl|Alt|Shift", chord_stem)
        ) or chord_stem
        collapsed.append({
            "group": group,
            "chords": [pretty_stem + " + #"],
            "label": "%s %d\u2013%d" % (stem, nums[0], nums[-1]),
        })
    kept = [r for r in rows if id(r) not in drop]
    return kept + collapsed


DIR_TAIL = re.compile(r"\s+(?:to\s+the\s+|to\s+)?(Left|Right|Up|Down|Above|Below)$", re.I)
FAMILIES = [("Left", "Down", "Up", "Right"), ("H", "J", "K", "L")]


def collapse_directional(rows):
    """Fold a four-way family into one row with a combined key chip.

    "Switch to Window Above/Below/Left/Right" is four rows saying one thing, and
    five such families were eating twenty of the sixty-four lines. Only collapses
    a complete set: same modifiers, four distinct keys covering one family, and
    labels differing solely by the trailing direction word.
    """
    buckets = {}
    for r in rows:
        m = DIR_TAIL.search(r["label"].strip())
        if not m or len(r["chords"]) != 1:
            continue
        parts = r["chords"][0].split(" + ")
        if len(parts) < 2:
            continue
        key = parts[-1]
        fam = next((f for f in FAMILIES if key in f), None)
        if fam is None:
            continue
        stem = DIR_TAIL.sub("", r["label"].strip())
        buckets.setdefault((r["group"], stem, tuple(parts[:-1]), fam), []).append((key, r))

    collapsed, drop = [], set()
    for (group, stem, prefix, fam), members in buckets.items():
        if {k for k, _ in members} != set(fam):
            continue
        for _, r in members:
            drop.add(id(r))
        collapsed.append({
            "group": group,
            "chords": [" + ".join(list(prefix) + ["/".join(fam)])],
            "label": stem,
        })
    kept = [r for r in rows if id(r) not in drop]
    return kept + collapsed


def main():
    if not os.path.exists(RC):
        print("[]")
        return
    cp = configparser.RawConfigParser(strict=False, delimiters=("=",))
    cp.optionxform = str                      # keep key case
    try:
        cp.read(RC, encoding="utf-8")
    except Exception:
        print("[]")
        return

    off = disabled_scripts()
    rows = []
    for section in cp.sections():
        svc = re.match(r"^services\]\[(.+)$", section) or re.match(r"^services$", section)
        is_service = section.startswith("services][") or section == "services"
        group_key = "services" if is_service else section
        group_default = GROUP_NAMES.get(group_key, group_key)

        for name, raw in cp.items(section):
            if name.startswith("_k_"):
                continue
            fields = (raw or "").split(",")
            active = fields[0].strip() if fields else ""
            if not active or active.lower() == "none":
                continue

            group = group_default          # per key: one component can hold 30 actions
            did = section.split("][", 1)[1] if "][" in section else section
            if is_service and name == "_launch":
                label, exe = desktop_entry(did)
                group = classify_service(exe)
            elif is_service:
                label, exe = desktop_action(did, name)
                if label:
                    group = classify_service(exe)
                else:
                    label = fields[2].strip() if len(fields) > 2 and fields[2].strip() else name
            else:
                label = fields[2].strip() if len(fields) > 2 and fields[2].strip() else name

            if group == "Shell":
                label = re.sub(r"^Quickshell\s+", "", label)

            # KWin's section is a dumping ground; split tiling scripts out so it stays readable.
            g = group
            m = re.match(r"^([A-Za-z][\w ]{2,20}):\s*(.+)$", label)
            if g == "Window Management" and m:
                g = m.group(1).strip().title()
                label = m.group(2).strip()

            if g.lower() in off:          # script installed but switched off
                continue

            chords = pretty_keys(active)
            if not chords:
                continue

            rows.append({"group": g, "chords": chords, "label": label})

    rows = [r for r in rows if r["group"] in INCLUDE_GROUPS]
    rows = collapse_numbered(rows)
    rows = collapse_directional(rows)
    rows.sort(key=lambda r: (r["group"], r["label"].lower()))
    json.dump(rows, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
