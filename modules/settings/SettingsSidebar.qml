// The guide's nav column, upstream's guide/GuideSidebar.qml: title and search button,
// one highlight gliding between tabs, subtabs folding out under their parent.

import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: sidebar
    required property var popup
    property alias tabsView: tabsFlickable
    property alias tabsItems: tabsRepeater

    readonly property int curTab: popup ? popup.currentTab : -1
    readonly property int expTab: popup ? popup.expandedTab : -1
    readonly property int curSub: popup ? popup.currentSubTab : -1
    readonly property real headerH: popup.s(38)
    readonly property real subH: popup.s(32)
    readonly property real gap: popup.s(2)
    readonly property real borderRadius: Radius.outer(popup.s(8))

    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: popup.s(232)
    color: Qt.alpha(popup.surface0, 0.4)

    topLeftRadius: popup.radiusTL
    bottomLeftRadius: popup.radiusBL

    opacity: popup.introSidebar
    transform: Translate { x: popup.s(-30) * (1.0 - popup.introSidebar) }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: popup.s(12)
        spacing: popup.s(8)

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: popup.s(40)
            spacing: popup.s(8)

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: popup.s(10)
                text: "Settings"
                font.family: popup.fontFamily
                font.pixelSize: popup.s(15)
                font.bold: true
                color: popup.text
            }

            V2.IconButton {
                id: searchBtn
                size: popup.s(34)
                Layout.preferredWidth: popup.s(34)
                Layout.preferredHeight: popup.s(34)
                Layout.alignment: Qt.AlignVCenter
                cornerRadius: sidebar.borderRadius
                buttonIcon: "\u{f0349}"
                centerInk: true
                iconFontSize: popup.s(16)
                accentColor: popup.searchActive ? popup.accent : Qt.alpha(popup.surface0, 0.7)
                textColor: popup.searchActive ? popup.crust : popup.text
                onClicked: popup.searchActive ? popup.closeSearch() : popup.openSearch()
            }
        }

        Flickable {
            id: tabsFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: tabsCol.implicitHeight + popup.s(8)
            contentWidth: width
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Rectangle {
                id: activeHighlight
                z: -1
                radius: sidebar.borderRadius
                color: popup.accent
                visible: activeDelegate !== null
                property bool ready: false
                Timer { interval: 500; running: true; onTriggered: activeHighlight.ready = true }

                opacity: popup.getTabOpacity(sidebar.curTab)
                transform: Translate { x: popup.s(-24) * (1.0 - popup.getTabProgress(sidebar.curTab)) }

                readonly property Item activeDelegate: { void tabsRepeater.count; return (sidebar.curTab >= 0) ? tabsRepeater.itemAt(sidebar.curTab) : null; }
                readonly property bool isSub: sidebar.curTab === sidebar.expTab && sidebar.expTab !== -1
                readonly property real baseY: activeDelegate ? activeDelegate.y + activeDelegate.sepH : 0
                readonly property real subIndent: popup.s(26)
                property real subMix: isSub ? 1.0 : 0.0
                Behavior on subMix { enabled: activeHighlight.ready; NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                readonly property real targetX: subIndent * subMix
                readonly property real targetY: isSub ? baseY + sidebar.headerH + popup.s(4) + sidebar.curSub * (sidebar.subH + sidebar.gap) : baseY
                readonly property real targetW: tabsCol.width - subIndent * subMix
                readonly property real targetH: isSub ? sidebar.subH : sidebar.headerH

                x: targetX
                y: targetY
                width: targetW
                height: targetH

                Behavior on y { enabled: activeHighlight.ready; NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                Behavior on height { enabled: activeHighlight.ready; NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
            }

            ColumnLayout {
                id: tabsCol
                width: tabsFlickable.width
                spacing: sidebar.gap

                Repeater {
                    id: tabsRepeater
                    model: popup.tabsModel
                    delegate: ColumnLayout {
                        id: tabDelegate
                        required property var modelData
                        required property int index

                        readonly property int tabIndex: index
                        opacity: popup.getTabOpacity(tabIndex)
                        transform: Translate { x: popup.s(-24) * (1.0 - popup.getTabProgress(tabIndex)) }
                        readonly property bool hasSubtabs: Boolean(modelData.subtabs && modelData.subtabs.length > 0)
                        readonly property bool isExpanded: hasSubtabs && sidebar.expTab === tabIndex
                        readonly property real fullSubtabsHeight: hasSubtabs ? (modelData.subtabs.length * sidebar.subH + (modelData.subtabs.length - 1) * sidebar.gap + popup.s(8)) : 0
                        readonly property real sepH: modelData.separatorBefore ? popup.s(14) + 1 : 0
                        property real expandProgress: isExpanded ? 1.0 : 0.0
                        Behavior on expandProgress { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        Layout.fillWidth: true
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: popup.s(6)
                            Layout.bottomMargin: popup.s(8)
                            Layout.leftMargin: popup.s(10)
                            Layout.rightMargin: popup.s(10)
                            Layout.preferredHeight: 1
                            visible: !!tabDelegate.modelData.separatorBefore
                            color: Qt.alpha(popup.surface2, 0.4)
                        }

                        Rectangle {
                            id: header
                            Layout.fillWidth: true
                            Layout.preferredHeight: sidebar.headerH
                            radius: sidebar.borderRadius
                            property bool active: false
                            Component.onCompleted: active = Qt.binding(() => tabDelegate.hasSubtabs ? (sidebar.curTab === tabDelegate.tabIndex && !tabDelegate.isExpanded) : (sidebar.curTab === tabDelegate.tabIndex))
                            color: (!active && headerMa.containsMouse) ? Qt.alpha(popup.surface1, 0.5) : "transparent"
                            Behavior on color { ColorAnimation { duration: 90 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: popup.s(8)
                                anchors.rightMargin: popup.s(12)
                                spacing: popup.s(10)

                                V2.IconButton {
                                    enabled: false
                                    size: popup.s(28)
                                    Layout.preferredWidth: popup.s(28)
                                    Layout.preferredHeight: popup.s(28)
                                    Layout.alignment: Qt.AlignVCenter
                                    cornerRadius: sidebar.borderRadius
                                    buttonIcon: tabDelegate.modelData.icon || "\u{f0493}"
                                    centerInk: true
                                    iconFontSize: popup.s(15)
                                    accentColor: popup.surface0
                                    textColor: popup.text
                                }

                                Text {
                                    text: tabDelegate.modelData.name
                                    font.family: popup.fontFamily
                                    font.weight: header.active ? Font.Bold : Font.Medium
                                    font.pixelSize: popup.s(13)
                                    color: header.active ? popup.crust : (headerMa.containsMouse ? popup.text : popup.subtext0)
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                }

                                Text {
                                    visible: tabDelegate.hasSubtabs
                                    text: "\u{f0140}"
                                    font.family: popup.glyphFamily
                                    font.pixelSize: popup.s(14)
                                    color: header.active ? popup.crust : (headerMa.containsMouse ? popup.text : popup.subtext0)
                                    Layout.alignment: Qt.AlignVCenter
                                    rotation: tabDelegate.expandProgress * 180 - 180
                                }
                            }

                            MouseArea {
                                id: headerMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    popup.closeSearch();
                                    popup.forceActiveFocus();
                                    if (tabDelegate.hasSubtabs) {
                                        if (popup.expandedTab === tabDelegate.tabIndex) {
                                            popup.expandedTab = -1;
                                        } else {
                                            popup.expandedTab = tabDelegate.tabIndex;
                                            if (popup.currentTab !== tabDelegate.tabIndex) {
                                                popup.currentTab = tabDelegate.tabIndex;
                                                popup.currentSubTab = 0;
                                            }
                                        }
                                    } else {
                                        popup.expandedTab = -1;
                                        popup.currentTab = tabDelegate.tabIndex;
                                        popup.currentSubTab = 0;
                                    }
                                }
                            }
                        }

                        Item {
                            visible: tabDelegate.hasSubtabs && tabDelegate.expandProgress > 0.001
                            Layout.fillWidth: true
                            Layout.preferredHeight: tabDelegate.fullSubtabsHeight * tabDelegate.expandProgress
                            opacity: Math.max(0.0, (tabDelegate.expandProgress - 0.15) / 0.85)
                            clip: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.topMargin: popup.s(4)
                                anchors.bottomMargin: popup.s(4)
                                spacing: popup.s(6)

                                Item {
                                    Layout.preferredWidth: popup.s(20)
                                    Layout.fillHeight: true

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.topMargin: popup.s(2)
                                        anchors.bottomMargin: popup.s(2)
                                        width: Math.max(1, popup.s(2))
                                        radius: popup.s(1)
                                        color: Qt.rgba(popup.surface2.r, popup.surface2.g, popup.surface2.b, 0.7)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: sidebar.gap

                                    Repeater {
                                        model: tabDelegate.hasSubtabs ? tabDelegate.modelData.subtabs : []
                                        delegate: Rectangle {
                                            id: sub
                                            required property var modelData
                                            required property int index

                                            Layout.fillWidth: true
                                            Layout.preferredHeight: sidebar.subH
                                            radius: sidebar.borderRadius

                                            readonly property int subIndex: index
                                            readonly property int parentIndex: tabDelegate.tabIndex
                                            property bool isCurrent: false
                                            Component.onCompleted: isCurrent = Qt.binding(() => sidebar.curTab === parentIndex && sidebar.expTab === parentIndex && sidebar.curSub === subIndex)
                                            color: (!isCurrent && subMa.containsMouse) ? Qt.alpha(popup.surface1, 0.5) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 90 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: popup.s(8)
                                                anchors.rightMargin: popup.s(10)
                                                spacing: popup.s(8)

                                                V2.IconButton {
                                                    enabled: false
                                                    size: popup.s(24)
                                                    Layout.preferredWidth: popup.s(24)
                                                    Layout.preferredHeight: popup.s(24)
                                                    Layout.alignment: Qt.AlignVCenter
                                                    cornerRadius: sidebar.borderRadius
                                                    buttonIcon: sub.modelData.icon || "\u{f0493}"
                                                    centerInk: true
                                                    iconFontSize: popup.s(12)
                                                    accentColor: popup.surface0
                                                    textColor: popup.text
                                                }

                                                Text {
                                                    text: sub.modelData.name
                                                    font.family: popup.fontFamily
                                                    font.weight: sub.isCurrent ? Font.Bold : Font.Medium
                                                    font.pixelSize: popup.s(12)
                                                    color: sub.isCurrent ? popup.crust : popup.subtext0
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    elide: Text.ElideRight
                                                    Behavior on color { ColorAnimation { duration: 90 } }
                                                }
                                            }

                                            MouseArea {
                                                id: subMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    popup.closeSearch();
                                                    popup.forceActiveFocus();
                                                    popup.currentTab = tabDelegate.tabIndex;
                                                    popup.expandedTab = tabDelegate.tabIndex;
                                                    popup.currentSubTab = sub.index;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
