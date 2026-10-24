.pragma library

// Port of extra/matugen/theme-import.py: the same render data a static theme gets, in-process.

var ROLES = ["base", "mantle", "crust", "text", "subtext0", "subtext1",
             "surface0", "surface1", "surface2", "overlay0", "overlay1", "overlay2",
             "blue", "sapphire", "peach", "green", "red", "mauve", "pink", "yellow",
             "maroon", "teal"];
var TONES = [0, 5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 70, 80, 90, 95, 98, 99, 100];
var PALETTE_SEEDS = [["primary", "blue"], ["secondary", "green"], ["tertiary", "peach"],
                     ["error", "red"], ["neutral", "base"], ["neutral_variant", "surface1"]];
var BASE16_ORDER = ["base", "mantle", "surface0", "surface1", "surface2", "text", "text", "text",
                    "red", "peach", "yellow", "green", "teal", "blue", "mauve", "maroon"];
var CHROMA_STEPS = [1, .9, .8, .7, .6, .5, .4, .3, .2, .1, 0];

// Python's round(): half to even.
function pyRound(x) {
    var f = Math.floor(x), d = x - f;
    if (d < 0.5) return f;
    if (d > 0.5) return f + 1;
    return f % 2 === 0 ? f : f + 1;
}

function parse(h) {
    h = ("" + h).trim().replace(/^#+/, "");
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    if (!/^[0-9a-fA-F]{6}$/.test(h)) throw new Error("bad colour: " + h);
    return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
}

function hexs(rgb) {
    var out = "#";
    for (var i = 0; i < 3; i++) {
        var v = Math.max(0, Math.min(255, pyRound(rgb[i])));
        out += (v < 16 ? "0" : "") + v.toString(16);
    }
    return out;
}

function mix(a, b, wa) {
    return [a[0] * wa + b[0] * (1 - wa), a[1] * wa + b[1] * (1 - wa), a[2] * wa + b[2] * (1 - wa)];
}

function lin(c) {
    c /= 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function luminance(rgb) {
    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2]);
}

function contrast(a, b) {
    var la = luminance(a) + 0.05, lb = luminance(b) + 0.05;
    return la > lb ? la / lb : lb / la;
}

function labF(t) {
    return t > 0.008856 ? Math.pow(t, 1 / 3) : 7.787 * t + 16 / 116;
}

function rgbToLab(rgb) {
    var r = lin(rgb[0]), g = lin(rgb[1]), b = lin(rgb[2]);
    var x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
    var y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b);
    var z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
    var fx = labF(x), fy = labF(y), fz = labF(z);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

function labFinv(t) {
    return Math.pow(t, 3) > 0.008856 ? Math.pow(t, 3) : (t - 16 / 116) / 7.787;
}

function labToLinear(L, a, b) {
    var fy = (L + 16) / 116;
    var fx = fy + a / 500, fz = fy - b / 200;
    var x = labFinv(fx) * 0.95047, y = labFinv(fy), z = labFinv(fz) * 1.08883;
    return [3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
            -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
            0.0556434 * x - 0.2040259 * y + 1.0572252 * z];
}

function unlin(v) {
    return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
}

// The colour at CIELAB L* = t (Material's tone), chroma shrunk until in gamut.
function tone(rgb, t) {
    var lab = rgbToLab(rgb), a = lab[1], b = lab[2], out;
    for (var i = 0; i < CHROMA_STEPS.length; i++) {
        var k = CHROMA_STEPS[i];
        out = labToLinear(t, a * k, b * k);
        if (out[0] >= -0.002 && out[0] <= 1.002 && out[1] >= -0.002 && out[1] <= 1.002
            && out[2] >= -0.002 && out[2] <= 1.002) break;
    }
    return [unlin(Math.min(1, Math.max(0, out[0]))) * 255,
            unlin(Math.min(1, Math.max(0, out[1]))) * 255,
            unlin(Math.min(1, Math.max(0, out[2]))) * 255];
}

function md3Roles(c) {
    function on(x) {
        var cands = [c.crust, c.base, c.text], best = cands[0], bestK = contrast(x, cands[0]);
        for (var i = 1; i < cands.length; i++) {
            var k = contrast(x, cands[i]);
            if (k > bestK) { best = cands[i]; bestK = k; }
        }
        return best;
    }
    function tint(x) { return mix(x, c.base, 0.3); }
    function onTint(x) { return mix(x, c.text, 0.4); }
    function dim(x) { return mix(x, c.base, 0.85); }
    var black = [0, 0, 0];
    var m = {
        background: c.base, on_background: c.text,
        surface: c.base, surface_dim: c.crust, surface_bright: c.surface2,
        surface_container_lowest: c.crust, surface_container_low: c.mantle,
        surface_container: c.surface0, surface_container_high: c.surface1,
        surface_container_highest: c.surface2,
        surface_variant: c.surface1, on_surface: c.text,
        on_surface_variant: c.subtext0,
        outline: c.overlay1, outline_variant: c.surface2,
        inverse_surface: c.text, inverse_on_surface: c.base,
        inverse_primary: mix(c.blue, c.base, 0.6),
        shadow: black, scrim: black,
        surface_tint: c.blue, source_color: c.blue
    };
    var pairs = [["primary", "blue"], ["secondary", "green"], ["tertiary", "peach"], ["error", "red"]];
    for (var i = 0; i < pairs.length; i++) {
        var role = pairs[i][0], x = c[pairs[i][1]];
        m[role] = x;
        m["on_" + role] = on(x);
        m[role + "_container"] = tint(x);
        m["on_" + role + "_container"] = onTint(x);
        if (role !== "error") {
            m[role + "_fixed"] = x;
            m[role + "_fixed_dim"] = dim(x);
            m["on_" + role + "_fixed"] = on(x);
            m["on_" + role + "_fixed_variant"] = on(x);
        }
    }
    return m;
}

function base16(c) {
    var out = {};
    for (var i = 0; i < BASE16_ORDER.length; i++)
        out["base" + (i < 16 ? "0" : "") + i.toString(16)] = c[BASE16_ORDER[i]];
    return out;
}

function mode(c) {
    var r = c.base[0] / 255, g = c.base[1] / 255, b = c.base[2] / 255;
    return (Math.max(r, g, b) + Math.min(r, g, b)) / 2 >= 0.5 ? "light" : "dark";
}

function parseRoles(colors) {
    var c = {};
    for (var i = 0; i < ROLES.length; i++) c[ROLES[i]] = parse(colors[ROLES[i]]);
    return c;
}

function hexAll(obj) {
    var out = {};
    for (var k in obj) out[k] = hexs(obj[k]);
    return out;
}

// Static theme → the shape Colors.preview* take. Throws on a malformed theme.
function fromTheme(id, colors) {
    var c = parseRoles(colors);
    var md3 = hexAll(md3Roles(c));
    delete md3.source_color;
    var palette = {};
    for (var i = 0; i < PALETTE_SEEDS.length; i++) {
        var seed = c[PALETTE_SEEDS[i][1]];
        for (var j = 0; j < TONES.length; j++)
            palette[PALETTE_SEEDS[i][0] + TONES[j]] = hexs(tone(seed, TONES[j]));
    }
    return {
        theme: { name: "" + id },
        named: hexAll(c),
        md3: md3,
        palette: palette,
        base16: hexAll(base16(c)),
        mode: mode(c)
    };
}

function copyHex(obj) {
    var out = {};
    if (obj) for (var k in obj) if (typeof obj[k] === "string") out[k] = obj[k];
    return out;
}

// A parsed colors.json / colors-matugen.json → the same shape.
function fromGenerated(json) {
    var j = json || {};
    var md3 = copyHex(j.md3);
    delete md3.source_color;
    return {
        theme: { name: j.theme && j.theme.name ? "" + j.theme.name : "matugen" },
        named: copyHex(j.named),
        md3: md3,
        palette: copyHex(j.palette),
        base16: copyHex(j.base16)
    };
}
