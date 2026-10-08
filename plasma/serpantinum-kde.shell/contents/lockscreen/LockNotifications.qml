// v2's notification box over the running shell's notifcenter IPC.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

LockCard {
    id: box

    property int tick: 0
    property bool clearing: false
    ListModel { id: notifModel }

    // Selected by PID: the greeter has no WAYLAND_DISPLAY, so `qs -p` sees no instance.
    readonly property string qsPrefix: "p=$(pgrep -f \"(quickshel[l]|q[s]) (-[nd] )*-p .*/shell[.]qml$\" | head -1); [ -n \"$p\" ] && "

    Plasma5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: (src, d) => {
            source.disconnectSource(src);
            var out = ("" + (d["stdout"] || "")).trim();
            if (out === "" || box.clearing) return;
            try {
                var arr = JSON.parse(out);
                notifModel.clear();
                for (var i = 0; i < arr.length; i++) notifModel.append(arr[i]);
            } catch (e) {}
        }
        // The engine caches on the command string; the tick keeps every poll distinct.
        function poll() {
            box.tick++;
            var cmd = "sh -c '" + box.qsPrefix + "qs ipc --pid \"$p\" call notifcenter list' # " + box.tick;
            disconnectSource(cmd);
            connectSource(cmd);
        }
        function clearAll() {
            box.tick++;
            connectSource("sh -c '" + box.qsPrefix + "qs ipc --pid \"$p\" call notifcenter clearAll' # " + box.tick);
        }
        Component.onCompleted: poll()
    }
    Timer { interval: 45000; running: true; repeat: true; onTriggered: source.poll() }

    function timeText(ms) {
        if (!ms) return "";
        var now = new Date(), d = new Date(ms);
        var sec = Math.floor((now.getTime() - d.getTime()) / 1000);
        if (sec < 60) return "Just now";
        var min = Math.floor(sec / 60);
        if (min < 60) return min + " min ago";
        var t = Qt.formatDateTime(d, box.lock.is12Hour ? "hh:mm AP" : "HH:mm");
        var sameDay = now.getFullYear() === d.getFullYear() && now.getMonth() === d.getMonth() && now.getDate() === d.getDate();
        if (sameDay) return t;
        var y = new Date(now); y.setDate(y.getDate() - 1);
        if (y.getFullYear() === d.getFullYear() && y.getMonth() === d.getMonth() && y.getDate() === d.getDate()) return "Yesterday " + t;
        if (sec < 7 * 86400) return Qt.formatDateTime(d, "dddd") + " " + t;
        return Qt.formatDateTime(d, "yyyy-MM-dd ") + t;
    }

    // Slide the visible cards out one by one, then ask the shell to forget them.
    function animateClear() {
        if (box.clearing || notifModel.count === 0) return;
        box.clearing = true;
        var delay = 0, n = 0;
        for (var i = 0; i < list.contentItem.children.length; i++) {
            var c = list.contentItem.children[i];
            if (c && typeof c.slideOut === "function" && c.y + c.height >= list.contentY && c.y <= list.contentY + list.height) {
                c.slideOut(n * 50);
                delay = n * 50 + 220;
                n++;
            }
        }
        clearTimer.interval = delay + 40;
        clearTimer.start();
    }
    Timer {
        id: clearTimer
        onTriggered: {
            source.clearAll();
            notifModel.clear();
            box.clearing = false;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: box.lock.s(12)
        spacing: box.lock.s(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: box.lock.s(8)
            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: box.lock.s(4)
                text: "Notifications"
                font.family: box.lock.uiFont
                font.weight: Font.Bold
                font.pixelSize: box.lock.s(12)
                color: box.lock.subtext0
            }
            Item { Layout.fillWidth: true }
            ClickButton {
                Layout.preferredWidth: box.lock.s(80)
                Layout.preferredHeight: box.lock.s(32)
                horizontalPadding: box.lock.s(10)
                cornerRadius: box.lock.r(10)
                buttonText: "Clear"
                textFontSize: box.lock.s(11)
                buttonIcon: "󰅖"
                iconFontSize: box.lock.s(14)
                fontFamily: box.lock.uiFont
                sf: box.lock.sf
                accentColor: box.lock.surface1
                textColor: box.lock.text
                visible: notifModel.count > 0
                enabled: !box.clearing
                onTriggered: box.animateClear()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: box.lock.s(8)
                visible: notifModel.count === 0
                AnimatedImage {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: box.lock.s(110)
                    Layout.preferredHeight: box.lock.s(110)
                    source: Qt.resolvedUrl("pushy.gif")
                    fillMode: Image.PreserveAspectFit
                    playing: visible
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "You're all caught up."
                    font.family: box.lock.uiFont
                    font.weight: Font.Medium
                    font.pixelSize: box.lock.s(12)
                    color: box.lock.overlay0
                }
            }

            ListView {
                id: list
                anchors.fill: parent
                model: notifModel
                spacing: box.lock.s(12)
                clip: true
                interactive: !box.clearing && contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    active: list.moving
                    width: box.lock.s(4)
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: box.lock.s(4); radius: box.lock.s(2); color: box.lock.surface2 }
                }
                add: Transition {
                    NumberAnimation { property: "scale"; from: 0.96; to: 1.0; duration: 250; easing.type: Easing.OutQuint }
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutQuint }
                }

                delegate: Item {
                    id: card
                    required property int index
                    required property string app
                    required property string summary
                    required property string body
                    required property string icon
                    required property double time

                    width: list.width
                    height: visual.implicitHeight
                    property bool expanded: false
                    property real dragX: 0
                    readonly property bool longBody: card.body.length > 50 || card.body.indexOf("\n") !== -1
                    transform: Translate { x: card.dragX }
                    opacity: Math.max(0, 1 - Math.abs(card.dragX) / (card.width * 0.75))

                    function slideOut(delayMs) { slideTimer.interval = delayMs; slideTimer.start(); }
                    Timer { id: slideTimer; onTriggered: slideAnim.start() }
                    NumberAnimation { id: slideAnim; target: card; property: "dragX"; to: list.width * 1.2; duration: 220; easing.type: Easing.OutQuad }

                    Rectangle {
                        anchors.fill: visual
                        anchors.topMargin: box.lock.s(1.5)
                        anchors.bottomMargin: box.lock.s(-1.5)
                        radius: visual.radius
                        color: Qt.rgba(0, 0, 0, 0.12)
                    }
                    Rectangle {
                        id: visual
                        width: parent.width
                        implicitHeight: content.implicitHeight + box.lock.s(20)
                        radius: box.lock.radius
                        color: cardMa.pressed ? Qt.darker(box.lock.surface1, 1.1) : (cardMa.containsMouse ? Qt.lighter(box.lock.surface1, 1.05) : box.lock.surface1)
                        scale: cardMa.pressed ? 0.98 : 1.0
                        clip: true
                        Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: card.longBody ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (card.longBody) card.expanded = !card.expanded
                        }

                        RowLayout {
                            id: content
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: box.lock.s(10)
                            spacing: box.lock.s(10)

                            Item {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: box.lock.s(40)
                                Layout.preferredHeight: box.lock.s(40)
                                Rectangle { anchors.fill: parent; anchors.topMargin: box.lock.s(1.5); anchors.bottomMargin: box.lock.s(-1.5); radius: box.lock.r(10); color: Qt.rgba(0, 0, 0, 0.12) }
                                Rectangle { anchors.fill: parent; radius: box.lock.r(10); color: box.lock.surface2 }
                                Kirigami.Icon {
                                    id: appIcon
                                    anchors.fill: parent
                                    anchors.margins: box.lock.s(5)
                                    source: card.icon !== "" ? card.icon : ""
                                    visible: card.icon !== "" && valid
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.horizontalCenterOffset: box.lock.s(1)
                                    anchors.verticalCenterOffset: box.lock.s(-1)
                                    visible: !appIcon.visible
                                    text: "󰋽"
                                    font.family: box.lock.iconFont
                                    font.pixelSize: box.lock.s(22)
                                    color: box.lock.subtext0
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: box.lock.s(-3)
                                spacing: 0

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: box.lock.s(28)
                                    Text {
                                        id: appLabel
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: card.app !== "" ? card.app : "System"
                                        font.family: box.lock.uiFont
                                        font.weight: Font.Bold
                                        font.pixelSize: box.lock.s(11)
                                        color: box.lock.subtext0
                                        visible: card.expanded
                                    }
                                    Text {
                                        id: summaryLabel
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(0, Math.min(implicitWidth, parent.width - timeLabel.implicitWidth - box.lock.s(18)))
                                        text: card.summary !== "" ? card.summary : "Notification"
                                        font.family: box.lock.uiFont
                                        font.weight: Font.Bold
                                        font.pixelSize: box.lock.s(12)
                                        color: box.lock.text
                                        elide: Text.ElideRight
                                        visible: !card.expanded
                                    }
                                    Text {
                                        anchors.left: summaryLabel.right
                                        anchors.leftMargin: box.lock.s(6)
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "•"
                                        font.family: box.lock.uiFont
                                        font.pixelSize: box.lock.s(10)
                                        color: box.lock.subtext1
                                        visible: !card.expanded
                                    }
                                    Text {
                                        id: timeLabel
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: box.timeText(card.time)
                                        font.family: box.lock.uiFont
                                        font.pixelSize: box.lock.s(11)
                                        color: box.lock.subtext1
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: card.expanded
                                    text: card.summary
                                    font.family: box.lock.uiFont
                                    font.weight: Font.Bold
                                    font.pixelSize: box.lock.s(12)
                                    color: box.lock.text
                                    wrapMode: Text.Wrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.topMargin: box.lock.s(-1)
                                    visible: card.body !== ""
                                    text: card.body
                                    font.family: box.lock.uiFont
                                    font.pixelSize: box.lock.s(11)
                                    color: box.lock.subtext0
                                    elide: card.expanded ? Text.ElideNone : Text.ElideRight
                                    maximumLineCount: card.expanded ? 40 : 1
                                    wrapMode: card.expanded ? Text.Wrap : Text.NoWrap
                                    textFormat: Text.StyledText
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
