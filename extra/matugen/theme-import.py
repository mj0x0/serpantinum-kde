#!/usr/bin/env python3
"""Build matugen's render data for a static theme, so `matugen json` can render every
template from 22 Catppuccin roles instead of a wallpaper.

    theme-import.py <theme> <out.json>      prints "dark" or "light"

Looks for <theme>.json in $XDG_STATE_HOME/quickshell/themes, then themes/ beside this
script. Exit 2 when the theme is missing or malformed.

With the `json` source the file IS the render data, verbatim: no palettes, base16 or
colour formats are generated and --mode is not consulted (verified on matugen 4.2.0).
"""
import json
import os
import sys

ROLES = ["base", "mantle", "crust", "text", "subtext0", "subtext1",
         "surface0", "surface1", "surface2", "overlay0", "overlay1", "overlay2",
         "blue", "sapphire", "peach", "green", "red", "mauve", "pink", "yellow",
         "maroon", "teal"]
TONES = [0, 5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 70, 80, 90, 95, 98, 99, 100]


def parse(h):
    h = h.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        raise ValueError(h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexs(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in rgb)


def mix(a, b, wa):
    return tuple(a[i] * wa + b[i] * (1 - wa) for i in range(3))


def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a) + 0.05, luminance(b) + 0.05
    return la / lb if la > lb else lb / la


def rgb_to_lab(rgb):
    r, g, b = (lin(c) for c in rgb)
    x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
    y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
    z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def lab_to_linear(L, a, b):
    fy = (L + 16) / 116
    fx, fz = fy + a / 500, fy - b / 200
    finv = lambda t: t ** 3 if t ** 3 > 0.008856 else (t - 16 / 116) / 7.787
    x, y, z = finv(fx) * 0.95047, finv(fy), finv(fz) * 1.08883
    return (3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
            -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
            0.0556434 * x - 0.2040259 * y + 1.0572252 * z)


def tone(rgb, t):
    """The colour at CIELAB L* = t (Material's tone), chroma shrunk until in gamut."""
    _, a, b = rgb_to_lab(rgb)
    for k in (1, .9, .8, .7, .6, .5, .4, .3, .2, .1, 0):
        out = lab_to_linear(t, a * k, b * k)
        if all(-0.002 <= v <= 1.002 for v in out):
            break
    unlin = lambda v: 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return tuple(unlin(min(1, max(0, v))) * 255 for v in out)


def find_theme(name):
    state = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (os.path.join(state, "quickshell", "themes"), os.path.join(here, "themes")):
        p = os.path.join(d, name + ".json")
        if os.path.isfile(p):
            return p
    return None


def md3_roles(c):
    on = lambda x: max((c["crust"], c["base"], c["text"]), key=lambda y: contrast(x, y))
    tint = lambda x: mix(x, c["base"], 0.3)          # M3 "container": a tinted surface
    on_tint = lambda x: mix(x, c["text"], 0.4)
    dim = lambda x: mix(x, c["base"], 0.85)
    black = (0, 0, 0)
    m = {
        "background": c["base"], "on_background": c["text"],
        "surface": c["base"], "surface_dim": c["crust"], "surface_bright": c["surface2"],
        "surface_container_lowest": c["crust"], "surface_container_low": c["mantle"],
        "surface_container": c["surface0"], "surface_container_high": c["surface1"],
        "surface_container_highest": c["surface2"],
        "surface_variant": c["surface1"], "on_surface": c["text"],
        "on_surface_variant": c["subtext0"],
        "outline": c["overlay1"], "outline_variant": c["surface2"],
        "inverse_surface": c["text"], "inverse_on_surface": c["base"],
        "inverse_primary": mix(c["blue"], c["base"], 0.6),
        "shadow": black, "scrim": black,
        "surface_tint": c["blue"], "source_color": c["blue"],
    }
    for role, key in (("primary", "blue"), ("secondary", "green"),
                      ("tertiary", "peach"), ("error", "red")):
        x = c[key]
        m[role] = x
        m["on_" + role] = on(x)
        m[role + "_container"] = tint(x)
        m["on_" + role + "_container"] = on_tint(x)
        if role != "error":
            m[role + "_fixed"] = x
            m[role + "_fixed_dim"] = dim(x)
            m["on_" + role + "_fixed"] = on(x)
            m["on_" + role + "_fixed_variant"] = on(x)
    return m


def base16(c):
    order = ["base", "mantle", "surface0", "surface1", "surface2", "text", "text", "text",
             "red", "peach", "yellow", "green", "teal", "blue", "mauve", "maroon"]
    return {"base%02x" % i: c[k] for i, k in enumerate(order)}


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    name, out = sys.argv[1], sys.argv[2]
    path = find_theme(name)
    if not path:
        print("theme-import: no theme named %r" % name, file=sys.stderr)
        return 2
    try:
        with open(path, encoding="utf-8") as fh:
            raw = json.load(fh)["colors"]
        c = {k: parse(raw[k]) for k in ROLES}
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print("theme-import: %s is not a theme: %s" % (path, exc), file=sys.stderr)
        return 2

    r, g, b = (v / 255 for v in c["base"])
    mode = "light" if (max(r, g, b) + min(r, g, b)) / 2 >= 0.5 else "dark"
    modes = lambda rgb: {m: {"color": hexs(rgb)} for m in ("default", "dark", "light")}
    seeds = {"primary": c["blue"], "secondary": c["green"], "tertiary": c["peach"],
             "error": c["red"], "neutral": c["base"], "neutral_variant": c["surface1"]}
    data = {
        "colors": {k: modes(v) for k, v in md3_roles(c).items()},
        "palettes": {p: {str(t): {"color": hexs(tone(s, t))} for t in TONES}
                     for p, s in seeds.items()},
        "base16": {k: modes(v) for k, v in base16(c).items()},
        "named": {k: {"color": hexs(v)} for k, v in c.items()},
        "theme": {"name": name, "static": True},
        "mode": mode,
        "is_dark_mode": mode == "dark",
    }
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, out)
    print(mode)
    return 0


if __name__ == "__main__":
    sys.exit(main())
