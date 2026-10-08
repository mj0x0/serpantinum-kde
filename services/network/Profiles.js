.pragma library

// The only NMSettings surface in the shell; NMSettings is not an exported QML type here.
// write() is a partial merge and fire-and-forget: NEVER round-trip a read() map back through it.

// Net registers this; a pragma library cannot import Quickshell to run a process itself.
var _runner = null;

function setRunner(fn) {
    _runner = fn;
}

function profiles(net) {
    if (!net || !net.nmSettings)
        return [];
    // A QV4 sequence: Array.isArray is false but length and indexing work.
    var src = net.nmSettings;
    var out = [];
    for (var i = 0; i < src.length; i++)
        if (src[i])
            out.push(src[i]);
    return out;
}

function profileId(net, i) {
    var p = profiles(net);
    var idx = i === undefined ? 0 : i;
    return (idx >= 0 && idx < p.length) ? p[idx].id : "";
}

// NM omits keys sitting at their default, so an absent autoconnect means TRUE.
function autoconnect(net) {
    var p = profiles(net);
    if (p.length === 0)
        return true;
    var m = p[0].read();
    if (!m || !m.connection || m.connection.autoconnect === undefined)
        return true;
    return m.connection.autoconnect === true;
}

// Written across every profile: forget() is all-profiles too, and QML cannot tell them apart.
function setAutoconnect(net, on) {
    var p = profiles(net);
    for (var i = 0; i < p.length; i++)
        p[i].write({
            connection: {
                autoconnect: on === true
            }
        });
    return p.length > 0;
}

function hidden(net) {
    var p = profiles(net);
    if (p.length === 0)
        return false;
    var m = p[0].read();
    if (!m || !m["802-11-wireless"])
        return false;
    return m["802-11-wireless"].hidden === true;
}

function setHidden(net, on) {
    var p = profiles(net);
    for (var i = 0; i < p.length; i++)
        p[i].write({
            "802-11-wireless": {
                hidden: on === true
            }
        });
    return p.length > 0;
}

function forgetProfile(s) {
    if (s)
        s.forget();
}

function clearSecrets(s) {
    if (s)
        s.clearSecrets();
}

// Quickshell 0.3.1 cannot create a profile, so this is the one call that leaves the module.
// Dispatched, not finished, and never carries a secret — connectWithPsk supplies that later.
function ensureHiddenProfile(ssid, keyMgmt) {
    if (!ssid || ("" + ssid).length === 0 || !_runner)
        return false;
    var km = keyMgmt ? ("" + keyMgmt) : "wpa-psk";
    if (km !== "wpa-psk" && km !== "sae" && km !== "none")
        return false;
    return _runner("nm-add-hidden.py", ["" + ssid, km]) === true;
}
