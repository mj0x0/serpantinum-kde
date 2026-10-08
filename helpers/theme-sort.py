#!/usr/bin/env python3
"""The theme list for Settings -> Appearance, in serpantinum v2's order: user themes,
Matugen, neutral dark/light, then colourful dark/light grouped by hue, with
{"isDivider": true} between groups. One JSON array on stdout.

    theme-sort.py [system-dir] [user-dir] [cache-file]

Ported from v2's guide/theme/theme_sorter.py; the classification is theirs.
"""
import hashlib
import json
import math
import os
import re
import sys

ACCENT_KEYS = ["blue", "red", "green", "peach", "mauve",
               "teal", "sapphire", "pink", "yellow", "maroon"]
BACKGROUND_KEYS = ["base", "mantle", "crust"]
MIN_SATURATION_FOR_HUE = 0.12
LIGHT_THRESHOLD = 0.5
HUE_BUCKETS = [
    (0, (345, 360)), (0, (0, 15)), (1, (15, 45)), (2, (45, 70)), (3, (70, 160)),
    (4, (160, 200)), (5, (200, 255)), (6, (255, 290)), (7, (290, 345)),
]
NEUTRAL_BUCKET = -1

HOME = os.path.expanduser("~")
SYSTEM_DIR = os.path.join(HOME, ".config", "matugen", "themes")
USER_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local", "state")),
                        "quickshell", "themes")
CACHE_FILE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")),
                          "quickshell", "theme_sort_cache.json")


def hex_to_rgb(hex_str):
    h = str(hex_str).lstrip("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}", h):
        return None
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def rgb_to_hsl(r, g, b):
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2.0
    if mx == mn:
        return (0.0, 0.0, l)
    d = mx - mn
    s = d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
    if mx == r:
        h = (g - b) / d + (6 if g < b else 0)
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return (h * 60 % 360, s, l)


def hue_to_bucket(angle):
    if angle is None:
        return NEUTRAL_BUCKET
    for bucket, (lo, hi) in HUE_BUCKETS:
        if lo <= angle < hi:
            return bucket
    return NEUTRAL_BUCKET


def compute_lightness(colors):
    for key in BACKGROUND_KEYS:
        rgb = hex_to_rgb(colors.get(key, ""))
        if rgb:
            return rgb_to_hsl(*rgb)[2]
    return 0.5


def compute_dominant_hue(colors, is_color_focused):
    bg = [rgb_to_hsl(*rgb) for k in BACKGROUND_KEYS
          if (rgb := hex_to_rgb(colors.get(k, "")))]
    avg_sat = sum(x[1] for x in bg) / len(bg) if bg else 0.0
    avg_light = sum(x[2] for x in bg) / len(bg) if bg else 0.5
    if not is_color_focused and (avg_sat < 0.22 or avg_light < 0.12 or avg_light > 0.88):
        return None
    sum_x = sum_y = 0.0
    for key in BACKGROUND_KEYS + ACCENT_KEYS:
        rgb = hex_to_rgb(colors.get(key, ""))
        if not rgb:
            continue
        h, s, _ = rgb_to_hsl(*rgb)
        if s < MIN_SATURATION_FOR_HUE:
            continue
        weight = s * (3.0 if key in BACKGROUND_KEYS else 1.5 if is_color_focused else 1.0)
        sum_x += math.cos(math.radians(h)) * weight
        sum_y += math.sin(math.radians(h)) * weight
    if abs(sum_x) < 1e-6 and abs(sum_y) < 1e-6:
        return None
    return math.degrees(math.atan2(sum_y, sum_x)) % 360


def classify(colors, is_color_focused):
    lightness = compute_lightness(colors)
    hue = compute_dominant_hue(colors, is_color_focused)
    return {"lightness": lightness,
            "lightness_group": "dark" if lightness < LIGHT_THRESHOLD else "light",
            "hue_bucket": hue_to_bucket(hue),
            "hue_angle": hue if hue is not None else -1.0}


def load_cache(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_cache(path, cache):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(cache, fh, sort_keys=True)
        os.replace(tmp, path)
    except OSError:
        pass


def sort_themes(sys_dir, user_dir, cache_path):
    cache = load_cache(cache_path)
    entries = [((1, 0, 0, 0, ""), "matugen", {"id": "matugen", "name": "Matugen", "isMatugen": True})]

    def scan(directory, category):
        if not os.path.isdir(directory):
            return
        for filename in sorted(os.listdir(directory)):
            if not filename.endswith(".json"):
                continue
            try:
                with open(os.path.join(directory, filename), "rb") as fh:
                    raw = fh.read()
                data = json.loads(raw)
                colors = data["colors"]
            except (OSError, ValueError, KeyError, TypeError):
                continue
            if not isinstance(colors, dict) or "base" not in colors:
                continue
            stem = filename[:-5]
            focused = bool(data.get("isColorFocused"))
            key = "%s_%s" % (category, filename)
            fp = hashlib.sha1(raw).hexdigest()
            info = cache.get(key)
            if not info or info.get("fingerprint") != fp:
                info = classify(colors, focused)
                info["fingerprint"] = fp
                cache[key] = info
            entry = {"id": stem, "name": str(data.get("name") or stem), "colors": colors,
                     "category": category}
            name = entry["name"].lower()
            if category == "user":
                sort_key, group = (0, 0, 0, 0, name), "user"
            elif info["hue_bucket"] == NEUTRAL_BUCKET:
                sort_key = (2 if info["lightness_group"] == "dark" else 3, 0, info["lightness"], 0, name)
                group = "neutral_" + info["lightness_group"]
            else:
                sort_key = (4 if info["lightness_group"] == "dark" else 5, info["hue_bucket"],
                            info["lightness"], info["hue_angle"], name)
                group = "colorful_%s_%d" % (info["lightness_group"], info["hue_bucket"])
            entries.append((sort_key, group, entry))

    scan(sys_dir, "system")
    scan(user_dir, "user")
    save_cache(cache_path, cache)
    entries.sort(key=lambda e: e[0])

    out, prev = [], None
    for _, group, entry in entries:
        if prev is not None and group != prev:
            out.append({"isDivider": True})
        out.append(entry)
        prev = group
    return out


if __name__ == "__main__":
    args = sys.argv[1:] + [SYSTEM_DIR, USER_DIR, CACHE_FILE][len(sys.argv) - 1:]
    print(json.dumps(sort_themes(*args[:3])))
