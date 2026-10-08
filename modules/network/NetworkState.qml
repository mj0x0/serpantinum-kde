// NetworkState — open/closed state for the Network panel (VPN, Wi-Fi, Ethernet and
// Servers tabs), opened from the TopBar network pill or via IPC.
pragma Singleton
import "../popups"
import "../../services/audio"

import QtQuick
import Quickshell

Singleton {
    readonly property bool open: Popups.current === "network"

    // Screen x of the TopBar network pill's centre, published by TopBar so the
    // panel opens beneath its icon. -1 until reported (falls back right-aligned).
    property real iconCenterX: -1
    property real iconCenterY: -1

    // "vpn" | "wifi" | "ethernet" | "servers" — lives here because PopupHost rebuilds on every
    // open. Every entry point states the tab it wants on the way in, so a tab left over from
    // last time can never decide where the panel opens.
    readonly property string defaultTab: "vpn"
    property string tab: defaultTab

    // Popups.target, not `open`: `current` lags behind while the panel animates.
    readonly property bool wanted: Popups.target === "network"
    function isTab(t) { return t === "vpn" || t === "wifi" || t === "ethernet" || t === "servers" }

    function toggle() { if (wanted) hide(); else openTab(defaultTab) }
    function show()   { openTab(defaultTab) }
    function hide()   { Popups.hideIf("network") }

    // Open on `t`, or switch to it if the panel is already up.
    function openTab(t) {
        if (!isTab(t)) return;
        var switching = wanted && tab !== t;
        tab = t;
        if (switching) Sounds.playSfx("network/switch.wav");
        else if (!wanted) Popups.show("network");
    }
    // For a keybind: same, except pressing it again on its own tab closes the panel.
    function toggleTab(t) {
        if (isTab(t) && wanted && tab === t) { hide(); return; }
        openTab(t);
    }
}
