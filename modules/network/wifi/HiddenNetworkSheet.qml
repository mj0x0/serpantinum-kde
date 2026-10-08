// Hidden SSID join. A profile that already exists is an ordinary Quickshell.Networking
// connect; one that does not goes through the Profiles seam, which is the only call in
// the shell that leaves the module — and says so in plain words when it cannot.

import "../shared"
import "../../../services/network"
import "../../../services/layout"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts
import "../../../services/network/Profiles.js" as Profiles

NetworkSheet {
    id: sheet

    property bool autoConnect: true
    property int secIndex: 0
    property string message: ""
    property string waitingSsid: ""

    // Focus is claimed a tick after the sheet opens; the tab must lock the keys NOW.
    readonly property bool focused: ssidInput.activeFocus || pskInput.activeFocus || sheet.open
    readonly property bool needsPsk: sheet.secIndex !== 2
    readonly property string keyMgmt: sheet.secIndex === 1 ? "sae" : sheet.secIndex === 2 ? "none" : "wpa-psk"
    readonly property bool waiting: sheet.waitingSsid !== ""

    signal joined(string ssid, string psk, bool autoconnect)

    glyph: "\u{f0209}"
    title: "Hidden network"

    Timer {
        id: deferFocus
        interval: 50
        onTriggered: ssidInput.forceActiveFocus()
    }
    onVisibleChanged: {
        if (!sheet.visible) {
            sheet.cancelWait();
            return;
        }
        ssidInput.text = "";
        pskInput.text = "";
        sheet.message = "";
        deferFocus.start();
    }

    function cancelWait() {
        sheet.waitingSsid = "";
        waitPoll.stop();
        waitTimeout.stop();
    }

    function finish(ssid) {
        var psk = sheet.needsPsk ? pskInput.text : "";
        sheet.cancelWait();
        sheet.joined(ssid, psk, sheet.autoConnect);
    }

    function join() {
        var ssid = ("" + ssidInput.text).trim();
        if (ssid.length === 0) {
            sheet.message = "Enter a network name.";
            return;
        }
        // Already saved: it is in the model as `known`, so this is a plain connect.
        var net = Net.resolveNetwork(ssid);
        if (net) {
            Profiles.setHidden(net, true);
            sheet.finish(ssid);
            return;
        }
        if (!Profiles.ensureHiddenProfile(ssid, sheet.keyMgmt)) {
            sheet.message = "Quickshell can't create a profile for this network. Save it once with another tool and it will appear here.";
            return;
        }
        // Dispatched, not finished — wait for the Network to register.
        sheet.message = "Creating profile…";
        sheet.waitingSsid = ssid;
        waitPoll.restart();
        waitTimeout.restart();
    }

    Timer {
        id: waitPoll
        interval: 500
        repeat: true
        onTriggered: {
            if (!sheet.waiting)
                return;
            if (Net.resolveNetwork(sheet.waitingSsid))
                sheet.finish(sheet.waitingSsid);
        }
    }
    Timer {
        id: waitTimeout
        interval: 10000
        onTriggered: {
            sheet.cancelWait();
            sheet.message = "The profile never appeared. NetworkManager may have refused it.";
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        spacing: sheet.popup.s(5)

        NetworkSheet.Field {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - sheet.popup.s(30)
            pop: sheet.popup
            focused: ssidInput.activeFocus

            TextInput {
                id: ssidInput
                anchors.fill: parent
                anchors.leftMargin: sheet.popup.s(12)
                anchors.rightMargin: sheet.popup.s(12)
                verticalAlignment: TextInput.AlignVCenter
                font.family: Fonts.ui
                font.pixelSize: sheet.popup.s(12)
                color: sheet.popup.text
                clip: true
                onAccepted: sheet.join()

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ssidInput.text.length === 0
                    text: "Network name"
                    font.family: Fonts.ui
                    font.pixelSize: sheet.popup.s(12)
                    color: sheet.popup.overlay0
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: sheet.popup.s(4)

            Chip {
                pop: sheet.popup
                label: "WPA2"
                on: sheet.secIndex === 0
                onPicked: sheet.secIndex = 0
            }
            Chip {
                pop: sheet.popup
                label: "WPA3"
                on: sheet.secIndex === 1
                onPicked: sheet.secIndex = 1
            }
            Chip {
                pop: sheet.popup
                label: "Open"
                on: sheet.secIndex === 2
                onPicked: sheet.secIndex = 2
            }
        }

        NetworkSheet.Field {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - sheet.popup.s(30)
            visible: sheet.needsPsk
            pop: sheet.popup
            focused: pskInput.activeFocus

            TextInput {
                id: pskInput
                anchors.fill: parent
                anchors.leftMargin: sheet.popup.s(12)
                anchors.rightMargin: sheet.popup.s(12)
                verticalAlignment: TextInput.AlignVCenter
                font.family: Fonts.ui
                font.pixelSize: sheet.popup.s(12)
                color: sheet.popup.text
                echoMode: TextInput.Password
                clip: true
                onAccepted: sheet.join()

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pskInput.text.length === 0
                    text: "Password"
                    font.family: Fonts.ui
                    font.pixelSize: sheet.popup.s(12)
                    color: sheet.popup.overlay0
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
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
                    visible: sheet.autoConnect
                    text: "\u{f012c}"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: sheet.popup.s(9)
                    color: sheet.popup.surface0
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sheet.autoConnect = !sheet.autoConnect
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Connect automatically"
                font.family: Fonts.ui
                font.pixelSize: sheet.popup.s(10)
                color: sheet.popup.crust

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sheet.autoConnect = !sheet.autoConnect
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: sheet.popup.s(90)
            Layout.preferredHeight: sheet.popup.s(26)
            radius: Radius.outer(sheet.popup.s(9))
            color: joinMa.containsMouse ? Qt.alpha(sheet.popup.crust, 0.22) : Qt.alpha(sheet.popup.crust, 0.12)
            border.width: 1
            border.color: sheet.popup.crust
            opacity: sheet.waiting ? 0.5 : 1.0
            Behavior on color {
                ColorAnimation {
                    duration: 180
                }
            }

            Text {
                anchors.centerIn: parent
                text: sheet.waiting ? "Joining…" : "Join"
                font.family: Fonts.ui
                font.weight: Font.Bold
                font.pixelSize: sheet.popup.s(11)
                color: sheet.popup.crust
            }

            MouseArea {
                id: joinMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!sheet.waiting)
                    sheet.join()
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: parent.width - sheet.popup.s(24)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: sheet.message !== ""
            text: sheet.message
            font.family: Fonts.ui
            font.pixelSize: sheet.popup.s(9)
            color: sheet.popup.crust
        }
    }

    component Chip: Rectangle {
        id: chip
        property var pop: null
        property string label: ""
        property bool on: false
        signal picked

        width: chipText.implicitWidth + (chip.pop ? chip.pop.s(14) : 14)
        height: chip.pop ? chip.pop.s(20) : 20
        radius: Radius.outer(chip.pop ? chip.pop.s(7) : 7)
        color: (chip.on && chip.pop) ? Qt.alpha(chip.pop.crust, 0.25) : "transparent"
        border.width: 1
        border.color: !chip.pop ? "transparent" : (chip.on ? chip.pop.crust : Qt.alpha(chip.pop.crust, 0.4))
        Behavior on color {
            ColorAnimation {
                duration: 180
            }
        }

        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            font.family: Fonts.ui
            font.weight: chip.on ? Font.Bold : Font.Normal
            font.pixelSize: chip.pop ? chip.pop.s(9) : 9
            color: chip.pop ? chip.pop.crust : "white"
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }
}
