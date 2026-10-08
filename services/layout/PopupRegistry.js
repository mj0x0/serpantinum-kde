.pragma library

// Every popup the shared window can show: base size (px before ui scale, or "fill"),
// the component to build, and an anchor per bar position. A popup may override the
// size with targetMasterWidth/Height on its root.
var table = {
    calendar:    { w: 1450, h: 510, comp: "../calendar/CalendarPopup.qml",
                   pos: { top: "top-center", bottom: "bottom-center", left: "left-center", right: "right-center" } },
    music:       { w: 700,  h: 650, comp: "../music/MusicPopup.qml",
                   pos: { top: "top-start", bottom: "bottom-start", left: "left-start", right: "right-start" } },
    network:     { w: 860,  h: 620, comp: "../network/NetworkPopup.qml",     pos: nearIcon() },
    bluetooth:   { w: 860,  h: 620, comp: "../bluetooth/BluetoothPopup.qml", pos: nearIcon() },
    power:       { w: 860,  h: 620, comp: "../power/PowerPopup.qml",         pos: nearIcon() },
    volume:      { w: 450,  h: 700, comp: "../volume/VolumePopup.qml",
                   pos: { top: "top-end", bottom: "bottom-end", left: "near-icon", right: "near-icon" } },
    // v2's System Panel: a full-height sheet on the right, or the left when the bar is there.
    notifcenter: { w: 500,  h: "fill", comp: "../notifcenter/SystemPanel.qml",
                   pos: { top: "right-edge", bottom: "right-edge", left: "right-edge", right: "left-edge" } },
    settings:    { w: 1200, h: 750, comp: "../settings/SettingsPopup.qml",     pos: centered() },
    wallpaper:   { w: "fill", h: 650, comp: "../wallpaper/WallpaperPicker.qml", pos: centered() },
    cheatsheet:  { w: 1240, h: 700, comp: "../cheatsheet/CheatsheetPopup.qml", pos: centered() },
    focustime:   { w: 900,  h: 700, comp: "../focustime/FocusTimePopup.qml",   pos: centered() }
};

function nearIcon() { return { top: "near-icon", bottom: "near-icon", left: "near-icon", right: "near-icon" }; }
function centered() { return { top: "center", bottom: "center", left: "center", right: "center" }; }
function get(name) { return table[name] || null; }
function names() { return Object.keys(table); }

// anchor + bar position -> x/y. g = clearance per screen edge (the bar's edge clears the bar),
// icon = the bar pill's centre for near-icon, s = the ui scaler.
function place(anchor, bar, w, h, W, H, g, icon, s) {
    var m = 12;
    var clampX = function (x) { return Math.max(m, Math.min(x, W - w - m)); };
    var clampY = function (y) { return Math.max(m, Math.min(y, H - h - m)); };
    var cx = Math.floor((W - w) / 2);
    var cy = Math.max(m, Math.floor((H - h) / 2));
    switch (anchor) {
    case "top-center":    return { x: cx, y: g.top };
    case "bottom-center": return { x: cx, y: H - h - g.bottom };
    case "left-center":   return { x: g.left, y: cy };
    case "right-center":  return { x: W - w - g.right, y: cy };
    case "top-start":     return { x: s(8), y: g.top };
    case "bottom-start":  return { x: s(8), y: H - h - g.bottom };
    case "left-start":    return { x: g.left, y: g.top };
    case "right-start":   return { x: W - w - g.right, y: g.top };
    case "top-end":       return { x: W - w - s(5), y: g.top };
    case "bottom-end":    return { x: W - w - s(5), y: H - h - g.bottom };
    case "right-edge":    return { x: W - w, y: 0 };
    case "left-edge":     return { x: 0, y: 0 };
    case "near-icon":
        if (bar === "left")  return { x: g.left, y: Math.round(icon[1] < 0 ? m : clampY(icon[1] - h / 2)) };
        if (bar === "right") return { x: W - w - g.right, y: Math.round(icon[1] < 0 ? m : clampY(icon[1] - h / 2)) };
        return { x: Math.round(icon[0] < 0 ? W - w - m : clampX(icon[0] - w / 2)),
                 y: bar === "bottom" ? H - h - g.bottom : g.top };
    }
    return { x: cx, y: Math.floor((H - h) / 2) };
}
