// Search hits grouped by tab and subtab, upstream's guide/GuideSearchResults.qml.

import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Flickable {
    id: searchResultsFlickable
    required property var popup
    property alias column: searchResultsCol
    visible: popup.searchActive
    contentHeight: searchResultsCol.implicitHeight + popup.s(10)
    contentWidth: width
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property real borderRadius: Radius.outer(popup.s(8))

    ScrollBar.vertical: ScrollBar {
        active: searchResultsFlickable.moving || searchResultsFlickable.movingVertically
        width: popup.s(4)
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: popup.s(4)
            radius: popup.s(2)
            color: popup.surface2
        }
    }

    // One hit: the row's glyph, title and description; the selected one wears the accent.
    component ResultRow : Rectangle {
        id: resultRow
        required property var modelData
        required property int index
        readonly property var popup: searchResultsFlickable.popup

        property bool isSelected: false
        Component.onCompleted: isSelected = Qt.binding(function() {
            if (!popup || !resultRow.modelData) return false;
            let sel = popup.flatSearchResults[popup.searchSelectedIndex];
            return !!sel && (sel === resultRow.modelData || sel.key === resultRow.modelData.key);
        })

        onIsSelectedChanged: {
            if (isSelected) {
                popup.ensureSearchItemVisible(resultRow);
            }
        }

        Layout.fillWidth: true
        implicitHeight: (resultRow.modelData && resultRow.modelData.desc) ? popup.s(48) : popup.s(38)
        radius: searchResultsFlickable.borderRadius
        color: resultRow.isSelected
            ? popup.accent
            : (resultMa.containsMouse ? Qt.alpha(popup.surface1, 0.6) : Qt.alpha(popup.surface0, 0.35))

        Behavior on color { ColorAnimation { duration: 150 } }

        MouseArea {
            id: resultMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: popup.selectSearchResult(resultRow.modelData)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: popup.s(8) + (resultRow.isSelected ? popup.s(4) : 0)
            anchors.rightMargin: popup.s(8)
            anchors.topMargin: popup.s(6)
            anchors.bottomMargin: popup.s(6)
            spacing: popup.s(8)

            Behavior on anchors.leftMargin { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

            Rectangle {
                Layout.preferredWidth: popup.s(28)
                Layout.preferredHeight: popup.s(28)
                Layout.alignment: Qt.AlignVCenter
                radius: popup.s(6)
                color: popup.surface0
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: popup.glyphNudge(resultRow.modelData.icon || "\u{f0493}", popup.s(14))
                    text: resultRow.modelData.icon || "\u{f0493}"
                    font.family: popup.glyphFamily
                    font.pixelSize: popup.s(14)
                    color: popup.text
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: resultRow.modelData.title
                    font.family: popup.fontFamily
                    font.pixelSize: popup.s(12)
                    font.bold: true
                    color: resultRow.isSelected ? popup.crust : popup.text
                    elide: Text.ElideRight

                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                Text {
                    Layout.fillWidth: true
                    text: resultRow.modelData.desc || ""
                    visible: text !== ""
                    font.family: popup.fontFamily
                    font.pixelSize: popup.s(10)
                    color: resultRow.isSelected ? Qt.alpha(popup.crust, 0.75) : popup.subtext0
                    elide: Text.ElideRight

                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }

    // The indent column beside a group's hits.
    component IndentLine : Item {
        readonly property var popup: searchResultsFlickable.popup
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
        id: searchResultsCol
        width: parent.width
        spacing: popup.s(8)

        Text {
            visible: popup.searchActive && popup.searchQuery.trim() === ""
            Layout.fillWidth: true
            Layout.topMargin: popup.s(24)
            horizontalAlignment: Text.AlignHCenter
            text: "Type to search settings..."
            font.family: popup.fontFamily
            font.pixelSize: popup.s(12)
            color: popup.subtext0
        }

        Text {
            visible: popup.searchActive && popup.searchQuery.trim() !== "" && popup.filteredSearchResults.length === 0
            Layout.fillWidth: true
            Layout.topMargin: popup.s(24)
            horizontalAlignment: Text.AlignHCenter
            text: "No settings found"
            font.family: popup.fontFamily
            font.pixelSize: popup.s(12)
            color: popup.subtext0
        }

        Repeater {
            id: searchTabsRepeater
            model: popup.groupedSearchResults
            delegate: ColumnLayout {
                id: tabGroup
                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: popup.s(4)

                Rectangle {
                    id: tabHeaderItem
                    Layout.fillWidth: true
                    Layout.preferredHeight: popup.s(44)
                    implicitHeight: popup.s(44)
                    radius: searchResultsFlickable.borderRadius
                    z: 1

                    color: tabHeaderItemMa.containsMouse ? Qt.alpha(popup.surface1, 0.5) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    scale: tabHeaderItemMa.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: popup.s(10)
                        anchors.rightMargin: popup.s(14)
                        spacing: popup.s(10)

                        V2.IconButton {
                            enabled: false
                            size: popup.s(32)
                            Layout.preferredWidth: popup.s(32)
                            Layout.preferredHeight: popup.s(32)
                            Layout.alignment: Qt.AlignVCenter
                            cornerRadius: searchResultsFlickable.borderRadius
                            buttonIcon: tabGroup.modelData.icon || "\u{f0493}"
                            centerInk: true
                            iconFontSize: popup.s(16)
                            accentColor: popup.surface0
                            textColor: popup.text
                        }

                        Text {
                            text: tabGroup.modelData.title
                            font.family: popup.fontFamily
                            font.weight: Font.Medium
                            font.pixelSize: popup.s(13)
                            color: tabHeaderItemMa.containsMouse ? popup.text : popup.subtext0
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: tabHeaderItemMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            popup.gotoTab(tabGroup.modelData.tabKey);
                            popup.closeSearch();
                        }
                    }
                }

                RowLayout {
                    id: tabIndentRow
                    visible: (tabGroup.modelData.directItems.length + tabGroup.modelData.subgroups.length) > 0
                    Layout.fillWidth: true
                    spacing: popup.s(6)

                    IndentLine {}

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: popup.s(4)

                        Repeater {
                            model: tabGroup.modelData.directItems
                            delegate: ResultRow {}
                        }

                        Repeater {
                            model: tabGroup.modelData.subgroups
                            delegate: ColumnLayout {
                                id: subGroup
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                spacing: popup.s(4)

                                Rectangle {
                                    id: subtabHeaderItem
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: popup.s(36)
                                    implicitHeight: popup.s(36)
                                    radius: searchResultsFlickable.borderRadius
                                    z: 1

                                    color: subtabHeaderItemMa.containsMouse ? Qt.alpha(popup.surface1, 0.5) : "transparent"
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    scale: subtabHeaderItemMa.pressed ? 0.98 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: popup.s(8)
                                        anchors.rightMargin: popup.s(10)
                                        spacing: popup.s(8)

                                        V2.IconButton {
                                            enabled: false
                                            size: popup.s(26)
                                            Layout.preferredWidth: popup.s(26)
                                            Layout.preferredHeight: popup.s(26)
                                            Layout.alignment: Qt.AlignVCenter
                                            cornerRadius: searchResultsFlickable.borderRadius
                                            buttonIcon: subGroup.modelData.icon || "\u{f0493}"
                                            centerInk: true
                                            iconFontSize: popup.s(13)
                                            accentColor: popup.surface0
                                            textColor: popup.text
                                        }

                                        Text {
                                            text: subGroup.modelData.title
                                            font.family: popup.fontFamily
                                            font.weight: Font.Medium
                                            font.pixelSize: popup.s(12)
                                            color: subtabHeaderItemMa.containsMouse ? popup.text : popup.subtext0
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            elide: Text.ElideRight
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                        }
                                    }

                                    MouseArea {
                                        id: subtabHeaderItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            popup.gotoTab(tabGroup.modelData.tabKey, subGroup.modelData.subKey);
                                            popup.closeSearch();
                                        }
                                    }
                                }

                                RowLayout {
                                    visible: subGroup.modelData.items.length > 0
                                    Layout.fillWidth: true
                                    spacing: popup.s(6)

                                    IndentLine {}

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: popup.s(4)

                                        Repeater {
                                            model: subGroup.modelData.items
                                            delegate: ResultRow {}
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
