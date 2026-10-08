.pragma library

// bar.modules: the widget ids, their aliases, the migration default and the
// normalisation, shared by the bar's placement engine and the Settings arranger.

var KNOWN = ["actions", "workspaces", "media", "timedate", "weather", "tray",
             "kb", "network", "awake", "power", "bt", "vol", "notif",
             "focus", "info", "vis", "sysmon"];
var STATUS_GROUP = ["kb", "network", "awake", "power", "bt", "vol", "notif"];

var INFO = {
    actions:    { label: "Actions",    icon: "\u{f035c}" },
    workspaces: { label: "Workspaces", icon: "\u{f0baf}" },
    media:      { label: "Media",      icon: "\u{f0388}" },
    timedate:   { label: "Clock",      icon: "\u{f00f0}" },
    weather:    { label: "Weather",    icon: "\u{f0590}" },
    tray:       { label: "Tray",       icon: "\u{f129e}" },
    kb:         { label: "Keyboard",   icon: "\u{f030c}" },
    network:    { label: "Network",    icon: "\u{f0928}" },
    awake:      { label: "Awake",      icon: "\u{f0176}" },
    power:      { label: "Power",      icon: "\u{f04b3}" },
    bt:         { label: "Bluetooth",  icon: "\u{f00af}" },
    vol:        { label: "Volume",     icon: "\u{f057e}" },
    notif:      { label: "Bell",       icon: "\u{f009a}" },
    focus:      { label: "Focus",      icon: "\u{f0208}" },
    info:       { label: "Recording",  icon: "\u{f0c4c}" },
    vis:        { label: "Visualiser", icon: "\u{f075a}" },
    sysmon:     { label: "System",     icon: "\u{f035b}" }
};

function aliasOf(id) {
    switch ("" + id) {
    case "left": return "actions";
    case "time": case "clock": return "timedate";
    case "indicator": case "indicators": case "record": case "recording": return "info";
    case "wifi": return "network";
    case "volume": return "vol";
    case "notifications": case "bell": return "notif";
    }
    return "" + id;
}

function expand(id) {
    if (id === "status") return STATUS_GROUP.slice();
    if (id === "system") return ["sysmon", "kb", "network", "bt", "vol"];
    var a = aliasOf(id);
    return KNOWN.indexOf(a) !== -1 ? [a] : [];
}

// Aliases resolved, "status"/"system" expanded into groups, unknown ids dropped,
// an id placed twice keeps its first slot, single-member groups flattened.
function normalize(arr, seen) {
    var out = [];
    if (!Array.isArray(arr)) return out;
    for (var i = 0; i < arr.length; i++) {
        var src = Array.isArray(arr[i]) ? arr[i] : [arr[i]];
        var members = [];
        for (var j = 0; j < src.length; j++) {
            var ex = expand(src[j]);
            for (var k = 0; k < ex.length; k++) if (!seen[ex[k]]) { seen[ex[k]] = true; members.push(ex[k]); }
        }
        if (members.length === 1) out.push(members[0]);
        else if (members.length > 1) out.push(members);
    }
    return out;
}

// No bar.modules: today's layout, with the bar.widgets.* toggles honoured as "not placed".
// on(key) answers whether bar.widgets.<key> is on.
function defaultModules(on) {
    var left = [], center = [], right = [];
    if (on("actions")) left.push("actions");
    if (on("workspaces")) left.push("workspaces");
    if (on("media")) left.push("media");
    if (on("clock")) { center.push("timedate"); center.push("weather"); }
    if (on("tray")) right.push("tray");
    if (on("status")) right.push(STATUS_GROUP.slice());
    if (on("recording")) right.push("info");
    return { left: left, center: center, right: right };
}

function parse(raw, on) {
    if (!raw || typeof raw !== "object") return defaultModules(on);
    var seen = {};
    return { left: normalize(raw.left, seen), center: normalize(raw.center, seen), right: normalize(raw.right, seen) };
}

function flat(arr) {
    var r = [];
    for (var i = 0; i < arr.length; i++) { if (Array.isArray(arr[i])) r = r.concat(arr[i]); else r.push(arr[i]); }
    return r;
}
