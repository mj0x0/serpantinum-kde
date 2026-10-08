// One orbiting device in the Bluetooth panel, styled after serpantinum's network
// float cards: a rounded pill that fills with accent as it connects.

import "../../services/layout"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts

Item {
    id: card

    property var device: null
    property var popup: null

    // Local optimism: `connecting` covers the gap between the click and BlueZ
    // reporting the new state, so the card reacts immediately.
    property bool busy: false
    readonly property bool isPaired: device !== null && device.paired
    readonly property bool isPairing: device !== null && device.pairing

    width: popup ? popup.s(170) : 170
    height: popup ? popup.s(60) : 60

    Rectangle {
        id: bg
        anchors.fill: parent
        // Squared corners (s(14)) like the original's float cards — a pill shape
        // read as a different design language next to them.
        radius: Radius.outer(popup.s(14))
        color: Qt.alpha(popup.surface0, 0.9)
        border.width: 1
        border.color: cardMa.containsMouse ? popup.accent
                    : (card.isPaired ? Qt.alpha(popup.accent, 0.45) : Qt.alpha(popup.overlay0, 0.5))
        Behavior on border.color { ColorAnimation { duration: 200 } }
        clip: true

        // Fill sweep while connecting/pairing.
        Rectangle {
            height: parent.height
            width: (card.busy || card.isPairing) ? parent.width : 0
            radius: parent.radius
            color: Qt.alpha(popup.accent, 0.28)
            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.InOutQuad } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: popup.s(14)
            anchors.rightMargin: popup.s(14)
            spacing: popup.s(10)

            Text {
                text: card.device ? popup.iconGlyph(card.device) : ""
                font.family: "Iosevka Nerd Font"
                font.pixelSize: popup.s(20)
                color: card.isPaired ? popup.accent : popup.subtext0
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: card.device ? (card.device.deviceName || card.device.address || "Unknown") : ""
                    font.family: Fonts.ui
                    font.weight: Font.Bold
                    font.pixelSize: popup.s(13)
                    color: popup.text
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: card.isPairing ? "pairing..."
                        : card.busy ? "connecting..."
                        : card.isPaired ? "paired" : "available"
                    font.family: Fonts.ui
                    font.pixelSize: popup.s(10)
                    color: popup.overlay0
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (!card.device) return;
                if (mouse.button === Qt.RightButton) {
                    // Right-click forgets a paired device.
                    if (card.isPaired) card.device.forget();
                    return;
                }
                card.busy = true;
                busyTimeout.restart();
                // Trust on first use: without Trusted, BlueZ will not auto-reconnect
                // the device later (it stays paired but silently never comes back).
                if (!card.device.trusted) card.device.trusted = true;
                // Unpaired devices must pair first; BlueZ connects as part of it.
                if (card.isPaired) card.device.connect();
                else card.device.pair();
            }
        }

        // Don't leave the card stuck "connecting" if BlueZ never reports back.
        Timer { id: busyTimeout; interval: 12000; onTriggered: card.busy = false }
    }

    // Clear the optimistic state once the real state catches up.
    Connections {
        target: card.device
        ignoreUnknownSignals: true
        function onConnectedChanged() { card.busy = false }
        function onPairedChanged()    { card.busy = false }
    }

    scale: cardMa.containsMouse ? 1.06 : 1.0
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
}
