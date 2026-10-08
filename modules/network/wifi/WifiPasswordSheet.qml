// PSK prompt drawn inside the core. connectWithPsk() refuses SILENTLY outside
// SAE/WPA2-PSK/WPA-PSK, so anything else gets an explanation instead of a dead field.

import "../shared"
import "../../../services/network"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking

NetworkSheet {
    id: sheet

    property string ssid: ""
    property int security: WifiSecurityType.Unknown
    property bool wrongPassword: false
    property bool autoConnect: true

    readonly property bool supported: Net.pskSecurity(sheet.security)
    // Focus is claimed a tick after the sheet opens; the tab must lock the keys NOW.
    readonly property bool focused: input.activeFocus || sheet.open

    signal submitted(string psk, bool autoconnect)

    glyph: "\u{f0928}"
    title: sheet.ssid

    // The host focuses the popup root only, so the field claims focus a tick later.
    Timer {
        id: deferFocus
        interval: 50
        onTriggered: input.forceActiveFocus()
    }
    onVisibleChanged: {
        if (sheet.visible) {
            input.text = "";
            deferFocus.start();
        }
    }
    // A rejected password re-opens on the same field rather than closing.
    onWrongPasswordChanged: {
        if (sheet.wrongPassword && sheet.visible)
            deferFocus.restart();
    }

    function send() {
        if (!sheet.supported || input.text.length === 0)
            return;
        sheet.submitted(input.text, sheet.autoConnect);
        input.text = "";
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        spacing: sheet.popup.s(5)

        NetworkSheet.Field {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - sheet.popup.s(30)
            visible: sheet.supported
            pop: sheet.popup
            focused: input.activeFocus

            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: sheet.popup.s(12)
                anchors.rightMargin: sheet.popup.s(12)
                verticalAlignment: TextInput.AlignVCenter
                font.family: Fonts.ui
                font.pixelSize: sheet.popup.s(12)
                color: sheet.popup.text
                echoMode: TextInput.Password
                clip: true
                onAccepted: sheet.send()
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - sheet.popup.s(30)
            horizontalAlignment: Text.AlignHCenter
            visible: sheet.supported && sheet.wrongPassword
            text: "Wrong password"
            font.family: Fonts.ui
            font.pixelSize: sheet.popup.s(10)
            color: sheet.popup.red
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - sheet.popup.s(30)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: !sheet.supported
            text: WifiSecurityType.toString(sheet.security) + " is not supported by Quickshell.Networking"
            font.family: Fonts.ui
            font.pixelSize: sheet.popup.s(10)
            color: sheet.popup.crust
        }

        // The profile is created by this connect, so it is the moment to set the flag.
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: autoRow.implicitWidth
            Layout.preferredHeight: sheet.popup.s(20)
            visible: sheet.supported

            Row {
                id: autoRow
                anchors.centerIn: parent
                spacing: sheet.popup.s(6)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: sheet.popup.s(14)
                    height: width
                    radius: width / 2
                    color: sheet.autoConnect ? sheet.popup.crust : "transparent"
                    border.width: 1
                    border.color: sheet.popup.crust
                    Behavior on color {
                        ColorAnimation {
                            duration: 180
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\u{f012c}"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: sheet.popup.s(9)
                        color: sheet.popup.surface0
                        visible: sheet.autoConnect
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Connect automatically"
                    font.family: Fonts.ui
                    font.pixelSize: sheet.popup.s(10)
                    color: sheet.popup.crust
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sheet.autoConnect = !sheet.autoConnect
            }
        }
    }
}
