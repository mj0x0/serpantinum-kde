// Which popup the shared window shows. Every <Feature>State is a facade over this,
// so the bar and the IPC targets did not have to change.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // current: what is on screen (set by PopupHost). target: what was last asked for.
    property string current: "hidden"
    property string target: "hidden"
    property string arg: ""
    signal requested(string name, string arg)

    function show(name, arg)   { target = name; requested(name, arg === undefined || arg === null ? "" : "" + arg) }
    function hide()            { if (target !== "hidden") { target = "hidden"; requested("hidden", "") } }
    function hideIf(name)      { if (target === name) hide() }
    function toggle(name, arg) { if (target === name) hide(); else show(name, arg) }
}
