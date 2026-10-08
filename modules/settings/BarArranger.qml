// Bar arranger, serpantinum v2's guide/BarTab.qml drag boxes on ShellSettings: Available
// plus the three sections, chips dragged between them with a placeholder, right-click A
// then B in one list to group, right-click a grouped chip to ungroup, Reset to the
// default. Every change writes the whole bar.modules object in ONE setValue.
import "../../services/bar"
import "../../services/layout"
import "../../services/settings"
import QtQuick
import QtQuick.Layouts
import "../../services/bar/BarModules.js" as BarModules

Item {
    id: root
    required property var host      // the Settings window: s(), palette, fonts
    implicitHeight: col.implicitHeight

    readonly property bool vertical: BarState.isVertical
    readonly property real chipH: host.s(30)
    readonly property real chipR: Radius.inner(host.s(8), host.s(15))

    ListModel { id: leftModel }
    ListModel { id: centerModel }
    ListModel { id: rightModel }
    ListModel { id: availableModel }

    property string placeholderList: ""
    property int placeholderIndex: -1
    property string pendingId: ""
    property string pendingList: ""
    property string lastSaved: ""

    // --- config <-> models ---------------------------------------------------------
    function widgetOn(k) { return ShellSettings.value("bar.widgets." + k, true) !== false; }
    function currentModules() { return BarModules.parse(ShellSettings.value("bar.modules", null), root.widgetOn); }

    function chip(id, gid) {
        var info = BarModules.INFO[id] || {};
        return { moduleId: id, moduleLabel: info.label || id, moduleIcon: info.icon || "", isPlaceholder: false, placeholderWidth: 0, groupId: gid };
    }

    function loadFrom(m) {
        clearPending();
        leftModel.clear(); centerModel.clear(); rightModel.clear(); availableModel.clear();
        var used = ({});
        var add = function (arr, model) {
            for (var i = 0; i < arr.length; i++) {
                var entry = Array.isArray(arr[i]) ? arr[i] : [arr[i]];
                var gid = Array.isArray(arr[i]) ? "g_" + arr[i][0] : "";
                for (var j = 0; j < entry.length; j++) {
                    if (used[entry[j]]) continue;
                    used[entry[j]] = true;
                    model.append(chip(entry[j], gid));
                }
            }
        };
        add(m.left, leftModel); add(m.center, centerModel); add(m.right, rightModel);
        for (var k = 0; k < BarModules.KNOWN.length; k++)
            if (!used[BarModules.KNOWN[k]]) availableModel.append(chip(BarModules.KNOWN[k], ""));
        lastSaved = JSON.stringify(m);
    }
    function load() { loadFrom(currentModules()); }
    Component.onCompleted: load()

    // A hand-edited file reloads the lists; our own writes round-trip unchanged.
    Connections {
        target: ShellSettings
        function onCfgChanged() {
            if (JSON.stringify(root.currentModules()) !== root.lastSaved) root.load();
        }
    }

    function buildArray(model) {
        var res = [], group = [], groupId = "";
        for (var i = 0; i < model.count; i++) {
            var it = model.get(i);
            if (it.isPlaceholder) continue;
            if (it.groupId && it.groupId !== "") {
                if (groupId === it.groupId) { group.push(it.moduleId); continue; }
                if (group.length > 0) res.push(group.length === 1 ? group[0] : group);
                groupId = it.groupId; group = [it.moduleId];
            } else {
                if (group.length > 0) { res.push(group.length === 1 ? group[0] : group); group = []; groupId = ""; }
                res.push(it.moduleId);
            }
        }
        if (group.length > 0) res.push(group.length === 1 ? group[0] : group);
        return res;
    }

    function save() {
        var obj = { left: buildArray(leftModel), center: buildArray(centerModel), right: buildArray(rightModel) };
        lastSaved = JSON.stringify(BarModules.parse(obj, root.widgetOn));
        ShellSettings.setValue("bar.modules", obj);
    }

    function reset() {
        var m = BarModules.defaultModules(root.widgetOn);
        loadFrom(m);
        ShellSettings.setValue("bar.modules", m);
    }

    // --- drag, drop and groups --------------------------------------------------------
    function clearPending() { pendingId = ""; pendingList = ""; }
    function modelFor(name) {
        if (name === "left") return leftModel;
        if (name === "center") return centerModel;
        if (name === "right") return rightModel;
        if (name === "available") return availableModel;
        return null;
    }
    function validCount(m) {
        var n = 0;
        for (var i = 0; i < m.count; i++) if (!m.get(i).isPlaceholder) n++;
        return n;
    }
    function clearPlaceholders() {
        var ms = [leftModel, centerModel, rightModel, availableModel];
        for (var a = 0; a < ms.length; a++)
            for (var i = ms[a].count - 1; i >= 0; i--) if (ms[a].get(i).isPlaceholder) ms[a].remove(i, 1);
    }
    function updatePlaceholder(listName, index, width, sourceList, sourceId) {
        if (placeholderList === listName && placeholderIndex === index) return;
        clearPlaceholders();
        var m = modelFor(listName);
        if (m) {
            var raw = index;
            if (listName === sourceList) {
                for (var i = 0; i < m.count; i++) {
                    var it = m.get(i);
                    if (!it.isPlaceholder && it.moduleId === sourceId) { if (index >= i) raw = index + 1; break; }
                }
            }
            raw = Math.max(0, Math.min(raw, m.count));
            m.insert(raw, { moduleId: "", moduleLabel: "", moduleIcon: "", isPlaceholder: true, placeholderWidth: width, groupId: "" });
        }
        placeholderList = listName;
        placeholderIndex = index;
    }
    function pendingGroupId() {
        if (pendingId === "" || pendingList === "") return "";
        var m = modelFor(pendingList);
        for (var i = 0; m && i < m.count; i++) { var it = m.get(i); if (it.moduleId === pendingId) return it.groupId || ""; }
        return "";
    }
    // A group of one is no group.
    function cleanupGroups() {
        var ms = [leftModel, centerModel, rightModel, availableModel], counts = ({}), keep = pendingGroupId();
        for (var a = 0; a < ms.length; a++)
            for (var i = 0; i < ms[a].count; i++) { var g = ms[a].get(i).groupId; if (g) counts[g] = (counts[g] || 0) + 1; }
        for (var b = 0; b < ms.length; b++)
            for (var j = 0; j < ms[b].count; j++) { var g2 = ms[b].get(j).groupId; if (g2 && counts[g2] < 2 && g2 !== keep) ms[b].setProperty(j, "groupId", ""); }
    }
    function unite(aId, bId, listName) {
        if (aId === bId) return;
        var m = modelFor(listName);
        if (!m) return;
        var aIdx = -1, bIdx = -1;
        for (var i = 0; i < m.count; i++) {
            var it = m.get(i);
            if (it.isPlaceholder) continue;
            if (it.moduleId === aId) aIdx = i;
            if (it.moduleId === bId) bIdx = i;
        }
        if (aIdx === -1 || bIdx === -1) return;
        var gid = m.get(bIdx).groupId || "";
        if (gid === "") { gid = "g_" + bId; m.setProperty(bIdx, "groupId", gid); }
        var moving = m.get(aIdx);
        var data = { moduleId: moving.moduleId, moduleLabel: moving.moduleLabel, moduleIcon: moving.moduleIcon, isPlaceholder: false, placeholderWidth: 0, groupId: gid };
        var wasBefore = aIdx < bIdx;
        m.remove(aIdx, 1);
        var first = -1, last = -1;
        for (var j = 0; j < m.count; j++) if (m.get(j).groupId === gid && !m.get(j).isPlaceholder) { if (first < 0) first = j; last = j; }
        if (first >= 0) m.insert(wasBefore ? first : last + 1, data);
        else m.insert(m.count, data);
        cleanupGroups();
        save();
    }
    function executeDrop(src) {
        var sModel = modelFor(src.listName);
        if (!sModel) return;
        var data = null;
        for (var i = 0; i < sModel.count; i++) {
            var it = sModel.get(i);
            if (!it.isPlaceholder && it.moduleId === src.moduleId) {
                data = { moduleId: it.moduleId, moduleLabel: it.moduleLabel, moduleIcon: it.moduleIcon, isPlaceholder: false, placeholderWidth: 0, groupId: it.groupId || "" };
                sModel.remove(i, 1);
                break;
            }
        }
        var tList = placeholderList, tIdx = placeholderIndex;
        clearPlaceholders();
        if (data && tList !== "") {
            var tModel = modelFor(tList);
            tIdx = Math.max(0, Math.min(tIdx, tModel.count));
            if (tList === "available") data.groupId = "";
            else {
                // A chip dropped between two members of one group joins it.
                var prev = tIdx > 0 ? tModel.get(tIdx - 1) : null, next = tIdx < tModel.count ? tModel.get(tIdx) : null;
                var pg = prev && prev.groupId ? prev.groupId : "", ng = next && next.groupId ? next.groupId : "";
                data.groupId = (pg !== "" && (pg === ng || ng === "")) ? pg : (ng !== "" && pg === "" ? ng : "");
            }
            tModel.insert(tIdx, data);
        } else if (data) {
            sModel.insert(sModel.count, data);
        }
        placeholderList = ""; placeholderIndex = -1;
        cleanupGroups();
        save();
    }
    function dropIndex(flow, mx, my) {
        var count = 0, phIndex = -1, phWidth = 0, hasPh = false;
        for (var i = 0; i < flow.children.length; i++) {
            var c = flow.children[i];
            if (c.isDelegate && c.isPlaceholder) { hasPh = true; phWidth = c.width; phIndex = count; break; }
            if (c.isDelegate && !c.isBeingDragged) count++;
        }
        count = 0;
        var target = 0, found = false;
        for (var j = 0; j < flow.children.length; j++) {
            var d = flow.children[j];
            if (!d.isDelegate || d.isBeingDragged || d.isPlaceholder) continue;
            var ux = d.x;
            if (hasPh && count >= phIndex) ux -= phWidth + flow.spacing;
            var cx = ux + d.width / 2, cy = d.y + d.height / 2;
            if (!found) {
                if (Math.abs(my - cy) < d.height / 2 + flow.spacing / 2) { if (mx < cx) { target = count; found = true; } }
                else if (my < d.y) { target = count; found = true; }
            }
            count++;
        }
        return found ? target : count;
    }
    // Editor-only tint per group; nothing is persisted for it.
    function groupColor(gid) {
        var palette = [host.mauve, host.sapphire, host.green, host.yellow, host.peach, host.pink, host.red];
        var h = 0;
        for (var i = 0; i < gid.length; i++) h = ((h << 5) - h + gid.charCodeAt(i)) | 0;
        return palette[Math.abs(h) % palette.length];
    }

    // --- one box per list -------------------------------------------------------------
    component DragBox : Rectangle {
        id: box
        property string listName
        property var listModel
        property string title
        readonly property bool hasPlaceholder: root.placeholderList === listName
        implicitHeight: Math.max(host.s(listName === "available" ? 60 : 96), titleText.implicitHeight + flow.childrenRect.height + host.s(26))
        color: host.surface0
        radius: Radius.outer(host.s(10))
        border.width: 1
        border.color: hasPlaceholder ? host.accent : host.surface2
        Behavior on border.color { ColorAnimation { duration: 150 } }
        clip: true

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: root.clearPending() }

        Text {
            id: titleText
            anchors.top: parent.top
            anchors.topMargin: host.s(8)
            anchors.left: parent.left
            anchors.leftMargin: host.s(12)
            text: box.title
            font.family: host.fontFamily
            font.pixelSize: host.s(10)
            font.weight: Font.Bold
            color: host.subtext0
        }

        DropArea {
            anchors.fill: parent
            onPositionChanged: drag => {
                var idx = root.dropIndex(flow, drag.x - flow.x, drag.y - flow.y);
                root.updatePlaceholder(box.listName, idx, drag.source.btnWidth, drag.source.listName, drag.source.moduleId);
            }
            onExited: {
                if (root.placeholderList === box.listName) { root.clearPlaceholders(); root.placeholderList = ""; root.placeholderIndex = -1; }
            }
        }

        Flow {
            id: flow
            anchors.top: titleText.bottom
            anchors.topMargin: host.s(6)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: host.s(8)
            anchors.rightMargin: host.s(8)
            spacing: host.s(6)

            Repeater {
                model: box.listModel
                delegate: Item {
                    id: d
                    property bool isDelegate: true
                    readonly property bool isPlaceholder: model.isPlaceholder === true
                    readonly property string moduleId: model.moduleId
                    readonly property string moduleLabel: model.moduleLabel
                    readonly property string moduleIcon: model.moduleIcon
                    readonly property string groupId: model.groupId || ""
                    readonly property string listName: box.listName
                    readonly property int moduleIndex: index
                    readonly property bool isBeingDragged: dragArea.drag.active
                    readonly property int btnWidth: chipBody.implicitWidth
                    readonly property bool isGrouped: groupId !== ""
                    readonly property bool isPending: root.pendingId === moduleId && root.pendingList === listName
                    property bool showError: false

                    implicitWidth: isPlaceholder ? model.placeholderWidth : chipBody.implicitWidth
                    implicitHeight: root.chipH
                    width: isPlaceholder ? model.placeholderWidth : (isBeingDragged ? 0 : chipBody.implicitWidth)
                    height: isPlaceholder ? root.chipH : (isBeingDragged ? 0 : root.chipH)
                    visible: isPlaceholder || !isBeingDragged
                    Behavior on width { enabled: !d.isBeingDragged; NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }

                    SequentialAnimation {
                        id: shakeAnim
                        NumberAnimation { target: floatWrapper; property: "x"; to: -2; duration: 50 }
                        NumberAnimation { target: floatWrapper; property: "x"; to: 2; duration: 50 }
                        NumberAnimation { target: floatWrapper; property: "x"; to: -2; duration: 50 }
                        NumberAnimation { target: floatWrapper; property: "x"; to: 0; duration: 50 }
                        onStarted: d.showError = true
                        onStopped: d.showError = false
                    }
                    function triggerError() { shakeAnim.stop(); shakeAnim.start(); }

                    Rectangle {
                        anchors.fill: parent
                        visible: d.isPlaceholder
                        color: Qt.alpha(host.accent, 0.15)
                        border.color: host.accent
                        border.width: 1
                        radius: root.chipR
                    }

                    Item {
                        id: floatWrapper
                        anchors.fill: !dragArea.drag.active ? parent : undefined
                        visible: !d.isPlaceholder
                        Drag.active: dragArea.drag.active
                        Drag.source: d
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2

                        // The chip floats over every box while dragged.
                        states: [
                            State {
                                when: dragArea.drag.active
                                ParentChange { target: floatWrapper; parent: root }
                                PropertyChanges { target: floatWrapper; width: d.btnWidth; height: root.chipH; opacity: 0.9; scale: 1.05 }
                            }
                        ]

                        Rectangle {
                            id: chipBody
                            anchors.fill: parent
                            implicitWidth: chipRow.implicitWidth + host.s(20)
                            radius: root.chipR
                            color: d.isGrouped ? root.groupColor(d.groupId) : host.surface1
                            border.width: 1
                            border.color: d.isGrouped ? "transparent" : host.surface2
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Row {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: host.s(6)
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: d.moduleIcon
                                    font.family: host.glyphFamily
                                    font.pixelSize: host.s(13)
                                    color: d.isGrouped ? host.base : host.subtext0
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: d.moduleLabel
                                    font.family: host.fontFamily
                                    font.pixelSize: host.s(10)
                                    font.weight: Font.Bold
                                    color: d.isGrouped ? host.base : host.text
                                }
                            }
                        }

                        Rectangle { anchors.fill: parent; radius: root.chipR; color: host.red; opacity: d.showError ? 0.25 : 0.0; Behavior on opacity { NumberAnimation { duration: 200 } } }
                        Rectangle { anchors.fill: parent; radius: root.chipR; color: "transparent"; border.width: 2; border.color: host.accent; opacity: d.isPending ? 1.0 : 0.0; Behavior on opacity { NumberAnimation { duration: 150 } } }

                        // Right-click: pick a partner, then group; on a grouped chip, ungroup.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: {
                                if (d.listName === "available") { root.clearPending(); return; }
                                var m = root.modelFor(d.listName);
                                if (root.pendingId !== "") {
                                    if (root.pendingId === d.moduleId && root.pendingList === d.listName) { root.clearPending(); return; }
                                    if (root.pendingList === d.listName) root.unite(root.pendingId, d.moduleId, d.listName);
                                    else d.triggerError();
                                    root.clearPending();
                                    return;
                                }
                                if (root.validCount(m) <= 1) return;
                                if (d.isGrouped) { m.setProperty(d.moduleIndex, "groupId", ""); root.cleanupGroups(); root.save(); }
                                else { root.pendingId = d.moduleId; root.pendingList = d.listName; }
                            }
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            drag.target: floatWrapper
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            onPressed: root.clearPending()
                            onReleased: {
                                floatWrapper.Drag.drop();
                                if (root.placeholderList !== "") root.executeDrop(d);
                                else root.clearPlaceholders();
                                floatWrapper.x = 0;
                                floatWrapper.y = 0;
                            }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: host.s(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: host.s(10)
            Text {
                Layout.fillWidth: true
                text: "Drag chips between the lists. Right-click a chip, then another in the same list, to share one pill; right-click a grouped chip to split it off."
                font.family: host.fontFamily
                font.pixelSize: host.s(9)
                color: host.overlay0
                wrapMode: Text.Wrap
            }
            Rectangle {
                implicitWidth: resetText.implicitWidth + host.s(20)
                implicitHeight: host.s(26)
                radius: height / 2
                color: resetMa.containsMouse ? host.surface2 : host.surface1
                border.color: host.surface2
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    id: resetText
                    anchors.centerIn: parent
                    text: "\u{f0453} Reset"
                    font.family: host.glyphFamily
                    font.pixelSize: host.s(10)
                    color: host.text
                }
                MouseArea { id: resetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.reset() }
            }
        }

        DragBox { Layout.fillWidth: true; listName: "available"; listModel: availableModel; title: "AVAILABLE" }

        RowLayout {
            Layout.fillWidth: true
            spacing: host.s(8)
            DragBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true; listName: "left";   listModel: leftModel;   title: root.vertical ? "TOP" : "LEFT" }
            DragBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true; listName: "center"; listModel: centerModel; title: "CENTER" }
            DragBox { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true; listName: "right";  listModel: rightModel;  title: root.vertical ? "BOTTOM" : "RIGHT" }
        }
    }
}
