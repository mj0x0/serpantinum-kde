// One Wi-Fi network in the orbit. Security is always named, never an ordinal table:
// in 0.3.1 Open is 10, so v2's `1=WEP, 2=WPA…` table prompts open networks for a password.

import "../shared"
import "../../../services/network"
import QtQuick
import Quickshell.Networking
import "../../../services/network/Profiles.js" as Profiles

NetworkCard {
    id: wcard

    // Never cached: the tab re-resolves this from the model on every commit.
    property var network: null
    property bool savedView: false

    readonly property real signalPct: wcard.network ? Net.normSignal(wcard.network.signalStrength) : 0
    readonly property string securityLabel: wcard.network ? WifiSecurityType.toString(wcard.network.security) : ""
    readonly property bool isKnown: wcard.network !== null && wcard.network.known === true
    readonly property bool isConnected: wcard.network !== null && wcard.network.connected === true

    // Four steps off one bucket, so a 1% drift can never flip the glyph.
    readonly property int signalBucket: Math.max(0, Math.min(3, Math.floor(wcard.signalPct / 25)))

    // Bound, never animated — the sweep below owns `busy` and nothing else.
    readonly property real connectedFill: wcard.isConnected ? 1.0 : 0.0

    signal forgotten

    glyph: Net.signalGlyph(wcard.signalBucket * 25)
    title: wcard.network ? ("" + wcard.network.name) : ""
    subtitle: !wcard.network ? ""
        : wcard.network.connected ? "connected"
        : wcard.network.stateChanging ? "connecting…"
        : (wcard.isKnown ? "saved · " : "") + wcard.securityLabel
    emphasised: wcard.isKnown || wcard.isConnected
    forgettable: wcard.isKnown
    pip: wcard.isKnown ? "A" : ""
    pipOn: wcard.autoConnect

    // Every mutating call in this API is fire-and-forget, so the card guesses and times out.
    property bool localBusy: false
    busy: (wcard.network !== null && wcard.network.stateChanging === true) || wcard.localBusy

    Timer {
        id: busyTimeout
        interval: 15000
        onTriggered: wcard.localBusy = false
    }

    function clearBusy() {
        wcard.localBusy = false;
        busyTimeout.stop();
    }

    Connections {
        target: wcard.network
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            wcard.clearBusy();
        }
        function onStateChangingChanged() {
            if (wcard.network && !wcard.network.stateChanging)
                wcard.clearBusy();
        }
        function onConnectionFailed(reason) {
            wcard.clearBusy();
        }
    }

    onTriggered: {
        if (!wcard.network)
            return;
        Net.connectWifi(wcard.network.name, "");
        if (Net.attemptPhase === "connecting") {
            wcard.localBusy = true;
            busyTimeout.restart();
        }
    }
    // The tab drops the delegate on the next commit; forget() deletes every saved profile.
    onForgetRequested: {
        if (!wcard.network)
            return;
        Net.forgetNetwork(wcard.network);
        wcard.forgotten();
    }

    // --- connect automatically ---------------------------------------------
    // NM omits keys at their default, so an absent autoconnect reads TRUE.
    property bool autoConnect: true
    function refreshAuto() {
        wcard.autoConnect = Profiles.autoconnect(wcard.network);
    }
    onNetworkChanged: wcard.refreshAuto()
    Component.onCompleted: wcard.refreshAuto()

    onPipToggled: {
        if (!wcard.network)
            return;
        var next = !wcard.autoConnect;
        if (Profiles.setAutoconnect(wcard.network, next))
            wcard.autoConnect = next;
    }

    // read() is synchronous against a cache that may not be loaded yet; re-read on change.
    Instantiator {
        model: Profiles.profiles(wcard.network)
        delegate: Connections {
            required property var modelData
            target: modelData
            ignoreUnknownSignals: true
            Component.onCompleted: wcard.refreshAuto()
            function onSettingsChanged() {
                wcard.refreshAuto();
            }
        }
    }

    // The connected mark: its own bound property, never the one the sweep animates.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: wcard.popup ? wcard.popup.s(3) : 3
        radius: width / 2
        color: wcard.popup ? wcard.popup.accent : "transparent"
        opacity: wcard.connectedFill
        Behavior on opacity {
            NumberAnimation {
                duration: 300
            }
        }
    }
}
