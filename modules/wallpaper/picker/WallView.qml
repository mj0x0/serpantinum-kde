import "../../../services/settings"
import QtQuick

Item {
    id: root

    property var picker
    property int currentIndex: -1
    readonly property int columns: ShellSettings.wallColumns
    property bool snapping: false
    // Breathing room so the 1.04 lift on an edge card is not clipped by the Flickable.
    readonly property real inset: root.picker.s(12)
    readonly property real cellWidth: Math.max(0, Math.floor((grid.width - (root.columns - 1) * grid.columnSpacing) / root.columns))
    readonly property real cellHeight: Math.round(root.cellWidth * 9 / 16)

    onCurrentIndexChanged: {
        root.picker.noteItemMove();
        root.ensureVisible();
    }

    function snapTo(index) {
        root.snapping = true;
        root.currentIndex = index;
        root.ensureVisible();
        root.snapping = false;
    }

    function stepRow(direction) {
        const list = root.picker.visibleIndexList();
        const pos = list.indexOf(root.currentIndex);
        if (pos < 0)
            return;
        const target = pos + direction * root.columns;
        if (target >= 0 && target < list.length)
            root.currentIndex = list[target];
    }

    function selectedRect() {
        const it = cards.itemAt(root.currentIndex);
        if (!it || !it.visible)
            return null;
        return it.mapToItem(root, 0, 0, it.width, it.height);
    }

    // Row-derived rather than item.y: a delegate may be mid move-transition after a filter change.
    function ensureVisible() {
        const pos = root.picker.visibleIndexList().indexOf(root.currentIndex);
        if (pos < 0 || flick.height <= 0)
            return;
        grid.forceLayout();
        const top = Math.floor(pos / root.columns) * (root.cellHeight + grid.rowSpacing);
        const bottom = top + root.cellHeight + 2 * root.inset;
        let y = flick.contentY;
        if (top < y)
            y = top;
        else if (bottom > y + flick.height)
            y = bottom - flick.height;
        y = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
        if (y !== flick.contentY)
            flick.contentY = y;
    }

    Connections {
        target: root.picker
        function onCurrentFilterChanged() { Qt.callLater(root.ensureVisible); }
        function onCacheVersionChanged() { Qt.callLater(root.ensureVisible); }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: root.picker.contentTop
        anchors.leftMargin: root.picker.s(72)
        anchors.rightMargin: root.picker.s(72)
        anchors.bottomMargin: root.picker.s(24)
        clip: true
        interactive: !root.picker.isApplying
        contentHeight: grid.height + 2 * root.inset
        boundsBehavior: Flickable.StopAtBounds

        Behavior on contentY {
            enabled: !root.snapping && root.picker.initialFocusSet
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }

        Grid {
            id: grid
            x: root.inset
            y: root.inset
            width: flick.width - 2 * root.inset
            columns: root.columns
            columnSpacing: root.picker.s(14)
            rowSpacing: root.picker.s(14)

            move: Transition {
                enabled: root.picker.initialFocusSet
                NumberAnimation {
                    properties: "x,y"
                    duration: 350
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                id: cards
                model: root.picker.activeModel

                delegate: Item {
                    id: cell

                    required property int index
                    required property string fileName
                    required property string fileUrl
                    readonly property bool isVideo: cell.fileName.startsWith("000_")
                    readonly property bool matches: root.picker.checkItemMatchesFilter(cell.fileName, cell.isVideo, root.picker.cacheVersion, root.picker.currentFilter)
                    readonly property bool current: cell.index === root.currentIndex

                    visible: cell.matches
                    width: root.cellWidth
                    height: root.cellHeight
                    z: cell.current ? 2 : 1
                    scale: cell.current ? 1.04 : 1.0

                    Behavior on scale {
                        enabled: root.picker.initialFocusSet
                        NumberAnimation {
                            duration: 250
                            easing.type: Easing.OutCubic
                        }
                    }

                    PickerCard {
                        anchors.fill: parent
                        picker: root.picker
                        fileName: cell.fileName
                        fileUrl: cell.fileUrl
                        current: cell.current
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: cell.matches && !root.picker.isApplying
                        onClicked: {
                            if (cell.current)
                                root.picker.applyWallpaper(cell.fileName, cell.isVideo);
                            else
                                root.currentIndex = cell.index;
                        }
                    }
                }
            }
        }
    }
}
