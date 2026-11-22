//@ pragma UseQApplication
import "../../../services/caching"
import "../../../services/layout"
import "../../../services/reusables"
import "../../../services/settings"
import "../../../services/shims"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "NotesFormat.js" as NotesFormat

Item {
    id: root

    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property string nerdFont: Fonts.icons
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    property bool stateLoaded: false
    property var interceptedShortcuts: isEditing ? ["Return", "Enter", "Left", "Right", "Up", "Down", "Escape"] : []
    readonly property bool hasInputFocus: (typeof nameInput !== "undefined" && nameInput.hasFocus) || (typeof contentInput !== "undefined" && contentInput.hasFocus)

    function unfocusInputs() {
        if (typeof nameInput !== "undefined" && typeof nameInput.releaseFocus === "function") {
            nameInput.releaseFocus();
        }
        if (typeof contentInput !== "undefined" && typeof contentInput.releaseFocus === "function") {
            contentInput.releaseFocus();
        }
    }

    Shortcut {
        enabled: root.isActiveTab && root.isEditing
        sequence: "Escape"
        onActivated: root.saveCurrentNote()
    }

    function s(val) {
        return typeof scaleFunc === "function" ? scaleFunc(val) : val;
    }

    property real baseW: s(460)
    property real baseL: s(430)

    property real preferredWidth: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseL + 50 : baseW
    property real preferredExtraLength: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (root.safeActiveEdge === "right") return 180;
        if (root.safeActiveEdge === "bottom") return 90;
        if (root.safeActiveEdge === "top") return -90;
        return 0;
    }

    MatugenColors { id: _theme }
    property color cBase: _theme.base
    property color cCrust: _theme.crust
    property color cMantle: _theme.mantle
    property color cSurface0: _theme.surface0
    property color cSurface1: _theme.surface1
    property color cSurface2: _theme.surface2
    property color cText: _theme.text
    property color cSubtext0: _theme.subtext0
    property color cSubtext1: _theme.subtext1
    property color cMauve: _theme.mauve
    property color cRed: _theme.red
    property color cPeach: _theme.peach

    function alpha(color, a) { return Qt.rgba(color.r, color.g, color.b, a); }

    Caching { id: paths }

    function getStorageDir() {
        return paths.getStateDir("quickactions");
    }

    property var notesList: []
    property var selectedIds: ({})
    property int selectedCount: 0

    property bool isEditing: false
    property string editingNoteId: ""
    property real editingUpdatedAt: 0
    property bool editingNotePinned: false
    property bool isMarkdownPreview: false

    readonly property bool areSelectedNotesPinned: {
        let keys = Object.keys(root.selectedIds);
        if (keys.length === 0) return false;
        for (let i = 0; i < root.notesList.length; i++) {
            let n = root.notesList[i];
            if (root.selectedIds[n.id] && !n.pinned) {
                return false;
            }
        }
        return true;
    }

    readonly property var displayNotesList: {
        let raw = root.notesList || [];
        let hasPinned = false;
        for (let i = 0; i < raw.length; i++) {
            if (raw[i].pinned) {
                hasPinned = true;
                break;
            }
        }
        let pinnedLabel = "Pinned";
        let recentLabel = "Recent";

        let pinned = [];
        let unpinned = [];
        for (let i = 0; i < raw.length; i++) {
            let item = raw[i];
            let copy = Object.assign({}, item);
            copy.sectionCategory = hasPinned ? (item.pinned ? pinnedLabel : recentLabel) : "";
            if (item.pinned) {
                pinned.push(copy);
            } else {
                unpinned.push(copy);
            }
        }
        return pinned.concat(unpinned);
    }

    property real expandProgress: 0.0
    property bool isDraggingV: false
    Behavior on expandProgress {
        enabled: !root.isDraggingV
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    onExpandProgressChanged: {
        if (expandProgress <= 0.001 && isEditing && !isDraggingV) {
            isEditing = false;
            editingNoteId = "";
        }
    }

    property real currentTimeTicker: 0
    Timer {
        interval: 10000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.currentTimeTicker = Date.now()
    }

    function formatRelativeTime(timestamp) {
        let fmt = "" + ShellSettings.value("bar.time.format", "HH:mm");
        return NotesFormat.formatRelativeTime(timestamp, I18n, fmt);
    }

    function formatPreciseTime(timestamp) {
        return NotesFormat.formatPreciseTime(timestamp);
    }

    FileView {
        id: notesStore
        printErrors: false
        path: root.getStorageDir() + "/notes.json"
        onLoaded: root.restoreNotes(text())
        onLoadFailed: root.restoreNotes("")
    }

    function restoreNotes(rawText) {
        let txt = (rawText || "").trim();
        if (txt !== "") {
            try {
                let data = JSON.parse(txt);
                if (Array.isArray(data)) {
                    root.notesList = data;
                }
            } catch (e) {}
        }
        root.stateLoaded = true;
    }

    function saveNotes() {
        if (!root.stateLoaded) return;
        notesStore.setText(JSON.stringify(root.notesList));
    }

    function isSelected(id) {
        return !!root.selectedIds[id];
    }

    function toggleSelection(id) {
        let copy = Object.assign({}, root.selectedIds);
        if (copy[id]) {
            delete copy[id];
        } else {
            copy[id] = true;
        }
        root.selectedIds = copy;
        root.selectedCount = Object.keys(copy).length;
    }

    function clearSelection() {
        root.selectedIds = ({});
        root.selectedCount = 0;
    }

    function deleteSelectedNotes() {
        let remaining = [];
        for (let i = 0; i < root.notesList.length; i++) {
            let item = root.notesList[i];
            if (!root.selectedIds[item.id]) {
                remaining.push(item);
            }
        }
        root.notesList = remaining;
        root.clearSelection();
        root.saveNotes();
    }

    function togglePinSelectedNotes() {
        let allPinned = root.areSelectedNotesPinned;
        let targetPinned = !allPinned;
        let list = root.notesList.map(n => {
            if (root.selectedIds[n.id]) {
                let copy = Object.assign({}, n);
                copy.pinned = targetPinned;
                return copy;
            }
            return n;
        });
        root.notesList = list;
        root.clearSelection();
        root.saveNotes();
    }

    function createNewNote() {
        root.clearSelection();
        let newId = "note_" + Date.now();
        root.editingNoteId = newId;
        root.editingUpdatedAt = Date.now();
        root.editingNotePinned = false;
        nameInput.text = "";
        contentInput.text = "";
        root.isMarkdownPreview = false;
        root.isEditing = true;
        root.expandProgress = 1.0;
    }

    function openNote(noteItem) {
        if (root.selectedCount > 0) {
            root.toggleSelection(noteItem.id);
            return;
        }
        root.editingNoteId = noteItem.id;
        root.editingUpdatedAt = noteItem.updatedAt || Date.now();
        root.editingNotePinned = Boolean(noteItem.pinned);
        nameInput.text = noteItem.title || "";
        contentInput.text = noteItem.content || "";
        root.isMarkdownPreview = false;
        root.isEditing = true;
        root.expandProgress = 1.0;
    }

    function saveCurrentNote() {
        if (!root.isEditing) return;
        let t = nameInput.text.trim();
        let c = contentInput.text;
        let id = root.editingNoteId;

        if (t === "" && c.trim() === "") {
            root.notesList = root.notesList.filter(n => n.id !== id);
            root.saveNotes();
            root.expandProgress = 0.0;
            return;
        }

        if (t === "") {
            let firstLine = c.trim().split("\n")[0];
            t = firstLine.length > 25 ? (firstLine.substring(0, 25) + "...") : firstLine;
            if (t === "") t = "New note";
        }

        let list = root.notesList.slice();
        let idx = -1;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                idx = i;
                break;
            }
        }

        let now = Date.now();
        if (idx !== -1) {
            list[idx] = {
                id: id,
                title: t,
                content: c,
                pinned: root.editingNotePinned,
                updatedAt: now,
                createdAt: list[idx].createdAt || now
            };
        } else {
            list.unshift({
                id: id,
                title: t,
                content: c,
                pinned: root.editingNotePinned,
                updatedAt: now,
                createdAt: now
            });
        }

        root.notesList = list;
        root.saveNotes();
        root.expandProgress = 0.0;
    }

    function markdownToHtml(md) {
        return NotesFormat.markdownToHtml(md, { code: root.cPeach, codeBg: root.cMantle });
    }

    Item {
        id: orientedRoot
        anchors.centerIn: parent
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Radius.outer(8)

            Item {
                id: mainListView
                anchors.fill: parent
                opacity: Math.max(0.0, 1.0 - root.expandProgress * 1.5)
                visible: opacity > 0.001

                Item {
                    id: listControlBar
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.s(42)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.s(10)
                        anchors.rightMargin: root.s(10)
                        spacing: root.s(8)

                        ClickButton {
                            visible: root.selectedCount === 0
                            Layout.fillWidth: true
                            buttonText: "Add note"
                            buttonIcon: "󰐕"
                            iconFontSize: root.s(14)
                            textFontSize: root.s(12)
                            accentColor: root.cSurface0
                            textColor: root.cText
                            cornerRadius: root.s(10)
                            implicitHeight: root.s(32)
                            onClicked: root.createNewNote()
                        }

                        Text {
                            visible: root.selectedCount > 0
                            text: root.selectedCount + " selected"
                            color: root.cMauve
                            font.family: Fonts.ui
                            font.pixelSize: root.s(13)
                            font.bold: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            Layout.alignment: Qt.AlignVCenter
                        }

                        IconButton {
                            visible: root.selectedCount > 0
                            size: root.s(32)
                            cornerRadius: root.s(8)
                            iconFontSize: root.s(15)
                            buttonIcon: "󰐃"
                            textColor: root.areSelectedNotesPinned ? root.cMauve : root.cSubtext0
                            accentColor: root.areSelectedNotesPinned ? root.alpha(root.cMauve, 0.2) : root.cSurface0
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: root.togglePinSelectedNotes()
                        }

                        IconButton {
                            visible: root.selectedCount > 0
                            size: root.s(32)
                            cornerRadius: root.s(8)
                            iconFontSize: root.s(15)
                            buttonIcon: "󰅖"
                            textColor: root.cSubtext0
                            accentColor: root.cSurface0
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: root.clearSelection()
                        }

                        IconButton {
                            visible: root.selectedCount > 0
                            size: root.s(32)
                            cornerRadius: root.s(8)
                            iconFontSize: root.s(15)
                            buttonIcon: "󰆴"
                            textColor: root.cRed
                            accentColor: root.alpha(root.cRed, 0.18)
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: root.deleteSelectedNotes()
                        }
                    }
                }

                ListView {
                    id: notesListView
                    anchors.top: listControlBar.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.topMargin: root.s(4)
                    anchors.bottomMargin: root.s(6)
                    anchors.leftMargin: root.s(8)
                    anchors.rightMargin: root.s(8)
                    spacing: root.s(6)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.displayNotesList

                    section.property: "sectionCategory"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        width: ListView.view ? ListView.view.width : 0
                        height: (section && section !== "") ? root.s(22) : 0
                        visible: section && section !== ""

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: root.s(4)
                            anchors.verticalCenter: parent.verticalCenter
                            text: section
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: root.s(10.5)
                            color: root.cSubtext0
                            opacity: 0.85
                        }
                    }

                    ScrollBar.vertical: ScrollBar {
                        active: notesListView.moving || notesListView.movingVertically
                        width: root.s(4)
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: root.s(4)
                            radius: root.s(2)
                            color: root.cSurface2
                        }
                    }

                    delegate: Item {
                        id: noteDelegateWrapper
                        width: notesListView.width

                        readonly property bool isSelected: root && modelData ? root.isSelected(modelData.id) : false
                        readonly property bool isTargetNote: root.editingNoteId === modelData.id
                        property real relativeUpdateTracker: root.currentTimeTicker

                        height: isTargetNote ? (root.s(54) + (root.s(130) - root.s(54)) * root.expandProgress) : root.s(54)

                        scale: itemMouseArea.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                        Rectangle {
                            id: noteItemCard
                            anchors.fill: parent
                            radius: Radius.outer(8)
                            readonly property color legacyColor: {
                                if (noteDelegateWrapper.isSelected) {
                                    return root.cMauve;
                                }
                                return itemMouseArea.containsMouse ? Qt.lighter(root.cSurface1, 1.04) : root.cSurface1;
                            }
                            color: legacyColor
                            clip: true

                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: root.s(12)
                                anchors.rightMargin: root.s(12)
                                spacing: root.s(10)

                                Item {
                                    id: noteIconArea
                                    Layout.preferredWidth: root.s(30)
                                    Layout.preferredHeight: root.s(30)
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: root.s(8)
                                        color: noteDelegateWrapper.isSelected
                                            ? Qt.rgba(0, 0, 0, 0.15)
                                            : root.cSurface2

                                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                        Text {
                                            anchors.centerIn: parent
                                            font.family: root.nerdFont
                                            font.pixelSize: root.s(14)
                                            color: noteDelegateWrapper.isSelected ? root.cCrust : root.cSubtext0
                                            text: "󰈙"

                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: root.s(1)

                                    Text {
                                        text: modelData.title || "New note"
                                        color: noteDelegateWrapper.isSelected ? root.cCrust : root.cText
                                        font.family: Fonts.ui
                                        font.pixelSize: root.s(12)
                                        font.weight: noteDelegateWrapper.isSelected ? Font.Bold : Font.Medium
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight

                                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }

                                    Text {
                                        text: {
                                            let c = (modelData.content || "").replace(/\n/g, " ").trim();
                                            return c.length > 0 ? c : "...";
                                        }
                                        color: noteDelegateWrapper.isSelected ? root.cCrust : root.cSubtext0
                                        opacity: noteDelegateWrapper.isSelected ? 0.9 : 0.85
                                        font.family: Fonts.ui
                                        font.pixelSize: root.s(10)
                                        font.weight: Font.Normal
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight

                                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: root.s(6)

                                    Text {
                                        text: root.formatRelativeTime(modelData.updatedAt)
                                        color: noteDelegateWrapper.isSelected ? root.cCrust : root.cSubtext1
                                        font.family: Fonts.ui
                                        font.pixelSize: root.s(10)

                                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }

                                    FlipIcon {
                                        id: noteExpandBtn
                                        size: root.s(26)
                                        cornerRadius: root.s(6)
                                        accentColor: root.cSurface2
                                        iconColor: isHoveredOrHighlighted ? root.cText : root.cSubtext1
                                        autoToggle: false
                                        flipped: isTargetNote && root.expandProgress > 0.5
                                        visible: root.selectedCount === 0
                                        onClicked: root.openNote(modelData)
                                    }
                                }
                            }

                            MouseArea {
                                id: itemMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton

                                property real startY: 0
                                property bool draggingV: false

                                onPressed: mouse => {
                                    startY = mouse.y;
                                    draggingV = false;
                                    root.isDraggingV = false;
                                }

                                onPositionChanged: mouse => {
                                    if (!pressed) return;
                                    let dy = mouse.y - startY;
                                    if (!draggingV && dy > root.s(6)) {
                                        if (root.selectedCount === 0) {
                                            draggingV = true;
                                            root.isDraggingV = true;
                                            preventStealing = true;
                                            root.editingNoteId = modelData.id;
                                            root.editingUpdatedAt = modelData.updatedAt || Date.now();
                                            root.editingNotePinned = Boolean(modelData.pinned);
                                            nameInput.text = modelData.title || "";
                                            contentInput.text = modelData.content || "";
                                            root.isMarkdownPreview = false;
                                            root.isEditing = true;
                                        }
                                    }

                                    if (draggingV) {
                                        let prog = Math.max(0.0, Math.min(1.0, dy / root.s(90)));
                                        root.expandProgress = prog;
                                    }
                                }

                                onReleased: mouse => {
                                    preventStealing = false;
                                    if (draggingV) {
                                        root.isDraggingV = false;
                                        draggingV = false;
                                        if (root.expandProgress > 0.35) {
                                            root.expandProgress = 1.0;
                                        } else {
                                            root.expandProgress = 0.0;
                                        }
                                    } else {
                                        if (mouse.button === Qt.RightButton) {
                                            root.toggleSelection(modelData.id);
                                        } else {
                                            root.openNote(modelData);
                                        }
                                    }
                                }

                                onCanceled: {
                                    preventStealing = false;
                                    if (draggingV) {
                                        root.isDraggingV = false;
                                        draggingV = false;
                                        if (root.expandProgress > 0.35) {
                                            root.expandProgress = 1.0;
                                        } else {
                                            root.expandProgress = 0.0;
                                        }
                                    }
                                }

                                onPressAndHold: {
                                    if (!draggingV) {
                                        root.toggleSelection(modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    anchors.centerIn: parent
                    visible: root.notesList.length === 0
                    width: parent.width - root.s(40)
                    height: emptyCol.implicitHeight

                    ColumnLayout {
                        id: emptyCol
                        anchors.centerIn: parent
                        spacing: root.s(10)

                        Text {
                            text: "󰈙"
                            font.family: root.nerdFont
                            font.pixelSize: root.s(36)
                            color: root.cSurface2
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: 'No notes yet. Click "Add note" to create one.'
                            color: root.cSubtext0
                            font.family: Fonts.ui
                            font.pixelSize: root.s(12)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            Item {
                id: editorView
                anchors.fill: parent
                visible: root.expandProgress > 0.001
                opacity: Math.max(0.0, (root.expandProgress - 0.15) / 0.85)
                scale: 0.96 + 0.04 * root.expandProgress
                transform: Translate { y: root.s(25) * (1.0 - root.expandProgress) }

                Rectangle {
                    id: editorCard
                    anchors.fill: parent
                    anchors.margins: root.s(8)
                    color: root.cSurface1
                    radius: Radius.outer(8)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.s(8)
                        spacing: root.s(8)

                        Item {
                            id: editorHeaderBar
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(32)

                            RowLayout {
                                anchors.fill: parent
                                spacing: root.s(8)

                                IconButton {
                                    id: closeBtn
                                    size: root.s(32)
                                    cornerRadius: root.s(8)
                                    iconFontSize: root.s(15)
                                    buttonIcon: "󰅖"
                                    textColor: root.cText
                                    accentColor: root.cSurface2
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: root.saveCurrentNote()
                                }

                                Item {
                                    id: headerTitleArea
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    ColumnLayout {
                                        id: headerTitleCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0

                                        Text {
                                            text: root.isMarkdownPreview ? "Preview markdown" : "Edit note"
                                            color: root.cText
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(12.5)
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: root.formatPreciseTime(root.editingUpdatedAt)
                                            color: root.cSubtext0
                                            font.family: Fonts.ui
                                            font.pixelSize: root.s(9.5)
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: headerDragArea
                                        anchors.fill: parent
                                        hoverEnabled: true

                                        property real startY: 0
                                        property bool draggingV: false

                                        onPressed: mouse => {
                                            startY = mouse.y;
                                            draggingV = false;
                                            root.isDraggingV = false;
                                        }

                                        onPositionChanged: mouse => {
                                            if (!pressed) return;
                                            let dy = mouse.y - startY;
                                            if (!draggingV && dy > root.s(6)) {
                                                draggingV = true;
                                                root.isDraggingV = true;
                                                preventStealing = true;
                                            }
                                            if (draggingV) {
                                                let prog = Math.max(0.0, Math.min(1.0, 1.0 - (dy / root.s(90))));
                                                root.expandProgress = prog;
                                            }
                                        }

                                        onReleased: {
                                            preventStealing = false;
                                            if (draggingV) {
                                                root.isDraggingV = false;
                                                draggingV = false;
                                                if (root.expandProgress < 0.65) {
                                                    root.saveCurrentNote();
                                                } else {
                                                    root.expandProgress = 1.0;
                                                }
                                            }
                                        }

                                        onCanceled: {
                                            preventStealing = false;
                                            if (draggingV) {
                                                root.isDraggingV = false;
                                                draggingV = false;
                                                if (root.expandProgress < 0.65) {
                                                    root.saveCurrentNote();
                                                } else {
                                                    root.expandProgress = 1.0;
                                                }
                                            }
                                        }
                                    }
                                }

                                IconButton {
                                    id: pinBtn
                                    size: root.s(32)
                                    cornerRadius: root.s(8)
                                    iconFontSize: root.s(15)
                                    buttonIcon: "󰐃"
                                    textColor: root.editingNotePinned ? root.cMauve : root.cSubtext0
                                    accentColor: root.editingNotePinned ? root.alpha(root.cMauve, 0.2) : root.cSurface2
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: root.editingNotePinned = !root.editingNotePinned
                                }

                                IconButton {
                                    id: markdownPreviewBtn
                                    size: root.s(32)
                                    cornerRadius: root.s(8)
                                    iconFontSize: root.s(15)
                                    buttonIcon: root.isMarkdownPreview ? "󰈙" : "󰂺"
                                    textColor: root.isMarkdownPreview ? root.cMauve : root.cSubtext0
                                    accentColor: root.isMarkdownPreview ? root.alpha(root.cMauve, 0.2) : root.cSurface2
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: root.isMarkdownPreview = !root.isMarkdownPreview
                                }

                                ClickButton {
                                    id: saveBtn
                                    buttonText: "Done"
                                    buttonIcon: "󰄬"
                                    iconFontSize: root.s(13)
                                    textFontSize: root.s(12)
                                    accentColor: root.cMauve
                                    textColor: root.cBase
                                    cornerRadius: root.s(8)
                                    implicitHeight: root.s(32)
                                    Layout.alignment: Qt.AlignVCenter
                                    onClicked: root.saveCurrentNote()
                                }
                            }
                        }

                        Item {
                            id: noteNameWrapper
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.s(34)

                            Input {
                                id: nameInput
                                anchors.fill: parent
                                baseColor: root.cSurface0
                                textColor: root.cText
                                subTextColor: root.cSubtext0
                                placeholderText: "Note title..."
                                cornerRadius: root.s(8)
                                fontPixelSize: root.s(12)
                                leadingIcon: ""
                                showClearButton: true
                                visible: !root.isMarkdownPreview
                            }

                            Rectangle {
                                id: previewTitleBar
                                anchors.fill: parent
                                radius: root.s(8)
                                color: root.cSurface0
                                visible: root.isMarkdownPreview

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.s(12)
                                    anchors.rightMargin: root.s(12)
                                    verticalAlignment: Text.AlignVCenter
                                    text: nameInput.text.trim().length > 0 ? nameInput.text.trim() : "New note"
                                    color: root.cText
                                    font.family: Fonts.ui
                                    font.pixelSize: root.s(12.5)
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Item {
                            id: editorContent
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            TapHandler {
                                enabled: !root.isMarkdownPreview
                                onPressedChanged: {
                                    if (pressed) {
                                        contentInput.forceInputFocus();
                                    }
                                }
                                onTapped: {
                                    contentInput.forceInputFocus();
                                }
                            }

                            Input {
                                id: contentInput
                                anchors.fill: parent
                                baseColor: root.cSurface0
                                textColor: root.cText
                                subTextColor: root.cSubtext0
                                placeholderText: "Write your note here in markdown..."
                                cornerRadius: root.s(8)
                                fontPixelSize: root.s(12)
                                multiLine: true
                                leadingIcon: ""
                                visible: !root.isMarkdownPreview
                            }

                            Rectangle {
                                id: previewContainer
                                anchors.fill: parent
                                color: root.cSurface0
                                radius: root.s(8)
                                visible: root.isMarkdownPreview

                                Flickable {
                                    id: previewFlickable
                                    anchors.fill: parent
                                    anchors.margins: root.s(10)
                                    contentWidth: width
                                    contentHeight: previewText.height
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true

                                    ScrollBar.vertical: ScrollBar {
                                        active: previewFlickable.moving || previewFlickable.movingVertically
                                        width: root.s(4)
                                        policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle {
                                            implicitWidth: root.s(4)
                                            radius: root.s(2)
                                            color: root.cSurface2
                                        }
                                    }

                                    Text {
                                        id: previewText
                                        width: previewFlickable.width
                                        visible: root.isMarkdownPreview
                                        textFormat: Text.RichText
                                        text: root.markdownToHtml(contentInput.text)
                                        color: root.cText
                                        font.family: Fonts.ui
                                        font.pixelSize: root.s(12)
                                        wrapMode: Text.WordWrap
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
