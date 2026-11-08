// The guide's content frame, upstream's guide/GuideContent.qml: one page per tab or
// subtab, cross-faded, with the search overlay on top.

import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts

Item {
    id: contentArea
    required property var popup
    property alias searchInput: searchField
    property alias searchResults: resultsList

    readonly property real searchHeaderHeight: popup.s(64)

    opacity: popup.introContent
    scale: 0.95 + (0.05 * popup.introContent)
    transform: Translate { y: popup.s(20) * (1.0 - popup.introContent) }

    Item {
        id: body
        anchors.top: parent.top
        anchors.topMargin: popup.s(4)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        Repeater {
            model: popup.tabsModel
            delegate: Item {
                id: tabContentWrapper
                required property var modelData
                required property int index
                x: 0
                y: 0

                readonly property int tabIndex: index
                readonly property bool hasSubtabs: Boolean(modelData.subtabs && modelData.subtabs.length > 0)

                readonly property bool isCurrent: popup.currentTab === tabIndex
                visible: isCurrent || opacity > 0.001
                opacity: isCurrent ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                Binding {
                    target: tabContentWrapper
                    property: "width"
                    value: body.width
                    when: tabContentWrapper.visible
                }

                Binding {
                    target: tabContentWrapper
                    property: "height"
                    value: body.height
                    when: tabContentWrapper.visible
                }

                // Pages are built with the popup, so every row is in the search index from the start.
                Loader {
                    anchors.fill: parent
                    anchors.margins: popup.s(8)
                    active: !tabContentWrapper.hasSubtabs
                    visible: !tabContentWrapper.hasSubtabs && tabContentWrapper.visible
                    readonly property int tabIndex: tabContentWrapper.tabIndex
                    readonly property int subTabIndex: -1
                    Component.onCompleted: if (active) setSource(tabContentWrapper.modelData.file, { "host": popup })
                    onStatusChanged: if (status === Loader.Error) console.warn("Settings page failed to load:", source)
                }

                Repeater {
                    model: tabContentWrapper.hasSubtabs ? tabContentWrapper.modelData.subtabs : []

                    delegate: Loader {
                        id: subTabLoader
                        required property var modelData
                        required property int index
                        anchors.fill: parent
                        anchors.margins: popup.s(8)
                        readonly property int tabIndex: tabContentWrapper.tabIndex
                        readonly property int subTabIndex: index

                        readonly property bool isSubCurrent: popup.currentTab === tabContentWrapper.tabIndex && popup.currentSubTab === index
                        visible: isSubCurrent || opacity > 0.001
                        opacity: isSubCurrent ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }

                        Component.onCompleted: setSource(modelData.file, { "host": popup })
                        onStatusChanged: if (status === Loader.Error) console.warn("Settings page failed to load:", source)
                    }
                }
            }
        }
    }

    Rectangle {
        id: searchOverlay
        anchors.fill: parent
        color: popup.base
        visible: popup.searchActive
        z: 10

        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: contentArea.searchHeaderHeight

            V2.Input {
                id: searchField
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: popup.s(20)
                anchors.rightMargin: popup.s(20)
                implicitHeight: popup.s(38)
                height: popup.s(38)
                placeholderText: "Search settings..."
                showClearButton: true
                fontFamily: popup.fontFamily
                fontPixelSize: popup.s(12)
                baseColor: Qt.alpha(popup.surface0, 0.6)
                accentColor: popup.accent
                textColor: popup.text
                subTextColor: popup.subtext0
                borderColor: Qt.alpha(popup.surface2, 0.4)
                cornerRadius: Radius.outer(popup.s(8))

                onTextEdited: (txt) => {
                    popup.searchQuery = txt;
                    popup.searchSelectedIndex = 0;
                }
                onCleared: {
                    popup.searchQuery = "";
                    popup.searchSelectedIndex = 0;
                }

                Keys.onEscapePressed: (event) => {
                    if (popup.searchQuery !== "") {
                        searchField.text = "";
                        popup.searchQuery = "";
                    } else {
                        popup.closeSearch();
                    }
                    event.accepted = true;
                }
                Keys.onDownPressed: (event) => { popup.navigateSearch(1); event.accepted = true; }
                Keys.onUpPressed: (event) => { popup.navigateSearch(-1); event.accepted = true; }
                Keys.onReturnPressed: (event) => { popup.activateSelectedSearch(); event.accepted = true; }
                Keys.onEnterPressed: (event) => { popup.activateSelectedSearch(); event.accepted = true; }
            }
        }

        SettingsSearchResults {
            id: resultsList
            popup: contentArea.popup
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: popup.s(16)
            anchors.rightMargin: popup.s(16)
            anchors.bottomMargin: popup.s(8)
        }
    }
}
