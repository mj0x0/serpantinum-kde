// serpantinum v2's ClickButton, without the sound hooks.
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property int horizontalPadding: root.s(12)
    property int cornerRadius: root.s(10)
    property string buttonText: ""
    property string subText: ""
    property string buttonIcon: ""
    property int iconFontSize: root.s(15)
    property int textFontSize: root.s(12)
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int contentAlignment: Qt.AlignHCenter
    property int maxTextWidth: 0
    property real sf: 1.0
    function s(v) { return Math.round(v * sf) }

    property color accentColor: Qt.rgba(1, 1, 1, 0.08)
    property color textColor: "white"
    property color iconColor: root.textColor
    property color subTextColor: root.textColor
    property bool action_highlight: false

    signal clicked()
    signal triggered()

    readonly property real rawTextWidth: Math.max(mainLabel.visible ? mainLabel.implicitWidth : 0, subLabel.visible ? subLabel.implicitWidth : 0)
    readonly property real boundedTextWidth: root.maxTextWidth > 0 ? Math.min(rawTextWidth, root.maxTextWidth) : rawTextWidth
    readonly property real contentWidth: (iconLabel.visible ? iconLabel.implicitWidth : 0)
                                         + (iconLabel.visible && textCol.visible ? mainRow.spacing : 0)
                                         + (textCol.visible ? boundedTextWidth : 0)
    implicitWidth: contentWidth + horizontalPadding * 2
    implicitHeight: root.s(30)
    readonly property real availableTextWidth: Math.max(0, root.width - root.horizontalPadding * 2 - (iconLabel.visible ? iconLabel.implicitWidth + mainRow.spacing : 0))

    property real flashOpacity: 0.0
    property real popScale: 1.0
    readonly property bool isHoveredOrHighlighted: btnMa.containsMouse || root.action_highlight

    Rectangle {
        id: btnShape
        anchors.fill: parent
        radius: root.cornerRadius
        clip: true
        color: (btnMa.pressed && root.enabled) ? Qt.darker(root.accentColor, 1.28)
             : (root.isHoveredOrHighlighted ? Qt.darker(root.accentColor, 1.14) : root.accentColor)
        Behavior on color { ColorAnimation { duration: 180 } }

        scale: ((btnMa.pressed && root.enabled) ? 0.985 : (root.isHoveredOrHighlighted ? 1.015 : 1.0)) * root.popScale
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: root; property: "popScale"; to: 1.015; duration: 100; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "popScale"; to: 1.0; duration: 350; easing.type: Easing.OutQuint }
        }

        RowLayout {
            id: mainRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: root.contentAlignment === Qt.AlignHCenter ? parent.horizontalCenter : undefined
            anchors.left: root.contentAlignment === Qt.AlignLeft ? parent.left : undefined
            anchors.leftMargin: root.contentAlignment === Qt.AlignLeft ? root.horizontalPadding : 0
            anchors.right: root.contentAlignment === Qt.AlignRight ? parent.right : undefined
            anchors.rightMargin: root.contentAlignment === Qt.AlignRight ? root.horizontalPadding : 0
            spacing: root.s(8)

            Text {
                id: iconLabel
                visible: root.buttonIcon !== ""
                text: root.buttonIcon
                font.family: "Iosevka Nerd Font"
                font.pixelSize: root.iconFontSize
                color: root.iconColor
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                id: textCol
                visible: root.buttonText !== "" || root.subText !== ""
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                Text {
                    id: mainLabel
                    visible: root.buttonText !== ""
                    text: root.buttonText
                    font.family: root.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: root.textFontSize
                    color: root.textColor
                    elide: Text.ElideRight
                    Layout.maximumWidth: Math.ceil(root.maxTextWidth > 0 ? Math.min(root.maxTextWidth, root.availableTextWidth) : root.availableTextWidth) + 2
                }

                Text {
                    id: subLabel
                    visible: root.subText !== ""
                    text: root.subText
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(10, root.textFontSize - 6)
                    color: root.subTextColor
                    opacity: 0.75
                    elide: Text.ElideRight
                    Layout.maximumWidth: mainLabel.Layout.maximumWidth
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: "white"
            opacity: root.flashOpacity
            PropertyAnimation on opacity { id: flashAnim; to: 0; duration: 350; easing.type: Easing.OutExpo }
        }
    }

    MouseArea {
        id: btnMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (!root.enabled) return;
            popAnim.start();
            root.flashOpacity = 0.15;
            flashAnim.start();
            root.clicked();
            root.triggered();
        }
    }
}
