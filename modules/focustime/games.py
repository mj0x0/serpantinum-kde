"""Game identity for FocusTime.

Windows games (Proton/Wine) are a mess to key on:

  * Launched through Steam they may report WM_CLASS `steam_app_<id>` or
    `steam_app_default`; launched through Heroic they report the raw executable,
    e.g. `control_dx12.exe`. The SAME game therefore lands under two different
    classes and shows up twice in the dashboard.
  * Keying Steam games by window *title* (needed because `steam_app_default` is
    shared by every game) makes each transient installer dialog its own row:
    "Checking ..\\data_packfiles\\ep101-000-pc.rmdp...", "Select Setup Language",
    "Browse For Folder", and so on.

Heroic's library is the fix: it maps each installed game's executable to a real
title, and caches art as `~/.config/heroic/icons/<app_name>.jpg`. So we resolve
an executable to its title, key everything as `game:<Title>`, and filter the
dialog noise.
"""

import glob
import json
import os
import re

import exeicon

HEROIC_DIR = os.path.expanduser("~/.config/heroic")
HEROIC_ICONS = os.path.join(HEROIC_DIR, "icons")
# Icons come from the executables themselves (exeicon.py); Heroic caches art for few.
EXE_ICON_CACHE = os.path.expanduser("~/.cache/quickshell/focustime/icons")
HEROIC_LIBRARIES = [
    os.path.join(HEROIC_DIR, "sideload_apps", "library.json"),
    os.path.join(HEROIC_DIR, "store_cache", "legendary_library.json"),
    os.path.join(HEROIC_DIR, "store_cache", "gog_library.json"),
    os.path.join(HEROIC_DIR, "store_cache", "nile_library.json"),
]

_EXE_MAP = {}          # "control_dx12.exe" -> {"title":…, "icon":…}
_TITLE_MAP = {}        # "control"          -> {"title":…, "icon":…}
_NORM_MAP = {}         # "warhammer40000roguetrader" -> entry (punctuation differs per source)
_LOADED_SIG = None     # (path, mtime) tuple so we reload when Heroic changes

# A row is stored as game:<Title>, so an icon found once must survive the game being closed.
KEY_CACHE = os.path.join(EXE_ICON_CACHE, "keys.json")
# Every .exe under a Heroic install, for games whose window is a different binary than
# the one Heroic launches (Clair Obscur launches Expedition33_Steam.exe, shows Sandfall.exe).
EXE_INDEX = os.path.join(EXE_ICON_CACHE, "exe-index.json")
STEAM_ROOTS = [os.path.expanduser("~/.steam/steam"),
               os.path.expanduser("~/.local/share/Steam")]


def _norm(s):
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())


def _read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default


def _write_json(path, obj):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(obj, fh)
        os.replace(tmp, path)
    except OSError:
        pass


def _library_signature():
    sig = []
    for p in HEROIC_LIBRARIES:
        try:
            sig.append((p, os.path.getmtime(p)))
        except OSError:
            pass
    return tuple(sig)


def _load():
    """(Re)build the exe/title maps if any Heroic library file changed."""
    global _LOADED_SIG, _EXE_MAP, _TITLE_MAP, _NORM_MAP
    sig = _library_signature()
    if sig == _LOADED_SIG:
        return
    _LOADED_SIG = sig
    exe_map, title_map = {}, {}

    for path in HEROIC_LIBRARIES:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception:
            continue
        games = data.get("games", data if isinstance(data, list) else [])
        if isinstance(games, dict):
            games = games.get("library", [])
        for g in games:
            if not isinstance(g, dict):
                continue
            title = (g.get("title") or "").strip()
            if not title:
                continue
            icon = ""
            app_name = g.get("app_name") or ""
            if app_name:
                cand = os.path.join(HEROIC_ICONS, app_name + ".jpg")
                if os.path.exists(cand):
                    icon = cand
            install = g.get("install") or {}
            exe = ""
            if isinstance(install, dict):
                exe = install.get("executable") or ""

            entry = {"title": title, "icon": icon, "exe": exe}
            if exe:
                exe_map[os.path.basename(exe).lower()] = entry
            title_map[title.lower()] = entry

    _EXE_MAP, _TITLE_MAP = exe_map, title_map
    _NORM_MAP = {_norm(t): e for t, e in title_map.items()}


# Installer / launcher / crash-handler windows that must never become rows.
_JUNK_EXACT = {
    "setup", "finished", "browse for folder", "select setup language",
    "about quicksfv", "installing", "extracting", "please wait",
    "error", "warning", "explorer.exe", "steam", "wine",
}
# Windows binaries that are never the game itself.
_JUNK_EXES = {
    "explorer.exe", "steam.exe", "steamwebhelper.exe", "winecfg.exe",
    "conhost.exe", "cmd.exe", "rundll32.exe", "quicksfv.exe",
    "unitycrashhandler64.exe", "unitycrashhandler32.exe",
    "crashreportclient.exe", "epicgameslauncher.exe", "gog galaxy.exe",
}

_JUNK_PATTERNS = [
    re.compile(r"^checking\s", re.I),      # "Checking ..\data_packfiles\..."
    re.compile(r"^setup\s*[-–]\s", re.I),  # "Setup - CONTROL: Ultimate Edition"
    re.compile(r"\.\.\.$"),                # any progress dialog
    re.compile(r"-\s*Unity\s+\d", re.I),   # Unity crash handler window
    re.compile(r"\.(exe|dll|pak|ucas|obj|rmdp)\b", re.I),
    re.compile(r"^\s*$"),
]


def is_junk_title(title):
    """True for transient installer/dialog windows that shouldn't be tracked."""
    if not title:
        return True
    t = title.strip()
    if t.lower() in _JUNK_EXACT:
        return True
    return any(p.search(t) for p in _JUNK_PATTERNS)


def _clean_exe_name(exe):
    """Fallback title for an exe Heroic doesn't know (e.g. UE5 shipping binaries)."""
    n = re.sub(r"\.exe$", "", exe, flags=re.I)
    n = re.sub(r"[-_](win64|win32|x64|x86)[-_]?shipping$", "", n, flags=re.I)
    n = re.sub(r"[-_](dx11|dx12|vk|vulkan)$", "", n, flags=re.I)
    n = re.sub(r"[-_]+", " ", n).strip()
    return n.title() if n else exe


def _icon_for(entry):
    """Heroic's cached art if present, else the icon inside the game's own exe."""
    if not entry:
        return ""
    if entry.get("icon") and os.path.exists(entry["icon"]):
        return entry["icon"]
    exe = entry.get("exe") or ""
    if not exe or not os.path.exists(exe):
        return ""
    out = os.path.join(EXE_ICON_CACHE,
                       os.path.basename(exe).lower().replace(".exe", "") + ".png")
    if os.path.exists(out):
        return out
    return exeicon.extract(exe, out) or ""


def _exe_index():
    """{cleaned exe name: heroic title} for every .exe under a Heroic install."""
    _load()
    roots = {}
    for entry in _TITLE_MAP.values():
        exe = entry.get("exe") or ""
        if exe and os.path.isdir(os.path.dirname(exe)):
            roots[os.path.dirname(exe)] = entry["title"]
    cached = _read_json(EXE_INDEX, {})
    if cached.get("roots") == sorted(roots):
        return cached.get("exes", {})

    exes = {}
    for root, title in roots.items():
        base_depth = root.rstrip("/").count("/")
        for dirpath, dirnames, filenames in os.walk(root):
            if dirpath.count("/") - base_depth >= 5:
                dirnames[:] = []
                continue
            for fn in filenames:
                if not fn.lower().endswith(".exe") or fn.lower() in _JUNK_EXES:
                    continue
                exes.setdefault(_norm(_clean_exe_name(fn)), title)
                exes.setdefault(_norm(fn[:-4]), title)
    _write_json(EXE_INDEX, {"roots": sorted(roots), "exes": exes})
    return exes


def _steam_apps():
    """{normalised store name: appid} from every Steam library's appmanifests."""
    libs = set()
    for root in STEAM_ROOTS:
        steamapps = os.path.join(root, "steamapps")
        if os.path.isdir(steamapps):
            libs.add(steamapps)
        vdf = os.path.join(steamapps, "libraryfolders.vdf")
        try:
            with open(vdf, "r", encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    m = re.search(r'"path"\s+"([^"]+)"', line)
                    if m and os.path.isdir(os.path.join(m.group(1), "steamapps")):
                        libs.add(os.path.join(m.group(1), "steamapps"))
        except OSError:
            pass

    apps = {}
    for lib in libs:
        for acf in glob.glob(os.path.join(lib, "appmanifest_*.acf")):
            name = appid = ""
            try:
                with open(acf, "r", encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        m = re.search(r'"(appid|name)"\s+"([^"]*)"', line)
                        if not m:
                            continue
                        if m.group(1) == "appid" and not appid:
                            appid = m.group(2)
                        elif m.group(1) == "name" and not name:
                            name = m.group(2)
                        if appid and name:
                            break
            except OSError:
                continue
            if appid and name:
                apps.setdefault(_norm(name), appid)
    return apps


def _steam_icon(appid):
    """Square crop of Steam's cached library art; it ships no square icon."""
    out = os.path.join(EXE_ICON_CACHE, "steam_" + appid + ".png")
    if os.path.exists(out):
        return out
    art = []
    for root in STEAM_ROOTS:
        cache = os.path.join(root, "appcache", "librarycache")
        art += [os.path.join(cache, appid, "*", "library_600x900.jpg"),
                os.path.join(cache, appid, "*", "library_header.jpg"),
                os.path.join(cache, appid, "*", "logo.png"),
                os.path.join(cache, appid + "_library_600x900.jpg"),
                os.path.join(cache, appid + "_header.jpg")]
    src = next((hit for pat in art for hit in sorted(glob.glob(pat))), "")
    if not src:
        return ""
    try:
        from PIL import Image
        img = Image.open(src).convert("RGBA")
        side = min(img.size)
        left, top = (img.width - side) // 2, (img.height - side) // 2
        os.makedirs(EXE_ICON_CACHE, exist_ok=True)
        img.crop((left, top, left + side, top + side)).save(out, "PNG")
        return out
    except Exception:
        return ""


def _icon_for_title(title):
    """Heroic art, the exe's own icon, or Steam's library art — whichever answers first."""
    if not title:
        return ""
    _load()
    key = "game:" + title
    remembered = _read_json(KEY_CACHE, {}).get(key, "")
    if remembered and os.path.exists(remembered):
        return remembered

    n = _norm(title)
    icon = _icon_for(_TITLE_MAP.get(title.lower()) or _NORM_MAP.get(n))
    if not icon:
        hit = _exe_index().get(n)
        if hit:
            icon = _icon_for(_TITLE_MAP.get(hit.lower()))
    if not icon:
        appid = _steam_apps().get(n)
        if appid:
            icon = _steam_icon(appid)
    if icon:
        cache = _read_json(KEY_CACHE, {})
        cache[key] = icon
        _write_json(KEY_CACHE, cache)
    return icon


def resolve(app_class, raw_title=""):
    """Resolve a window to a game.

    Returns {"key", "title", "icon"} or None when this isn't a game window.
    `key` is the canonical DB class — the same for a game however it was
    launched, which is what stops it appearing twice.
    """
    if not app_class:
        return None
    _load()
    cls = app_class.lower().strip()

    # 1. A raw Windows executable (Heroic, or Steam reporting the real class).
    if cls.endswith(".exe"):
        hit = _EXE_MAP.get(cls)
        if hit:
            return {"key": "game:" + hit["title"], "title": hit["title"], "icon": _icon_for(hit)}
        # Do NOT run is_junk_title() on the class - its .exe pattern rejects every executable.
        if cls in _JUNK_EXES:
            return None

        # Heroic does not know renamed shipping exes, and the window title is usually the real
        # name, so prefer it when it looks like a title rather than a repeat of the filename.
        title = ""
        t = (raw_title or "").strip()
        # Only reject a title that IS the filename ("control_dx12.exe"); a spaced,
        # properly-cased version of it ("DOOM The Dark Ages") is exactly what we want.
        if t and not is_junk_title(t) and len(t) <= 60 and t.lower() != cls:
            title = t
        if not title:
            title = _clean_exe_name(cls)

        return {"key": "game:" + title, "title": title, "icon": _icon_for_title(title)}

    # 2. Steam's shared class — the title is the only identity available, so it
    #    has to be filtered hard or every installer dialog becomes a row.
    if cls.startswith("steam_app"):
        t = re.sub(r"^\(\d+\)\s*|^\[\d+\]\s*", "", raw_title or "").strip()
        t = re.sub(r"\s*\(\d+\)$", "", t).strip()
        if not t or is_junk_title(t):
            return None
        return {"key": "game:" + t, "title": t, "icon": _icon_for_title(t)}

    return None


def icon_for_key(key):
    """Icon path for a canonical `game:<Title>` key, or ""."""
    if not key or not key.startswith("game:"):
        return ""
    return _icon_for_title(key[5:])
