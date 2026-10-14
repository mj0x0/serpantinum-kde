// Servers tab: the self-hosted services on this box, on the same plasma-strand orbit as
// the other tabs. The ring holds groups; picking one drops its services into the ring.
// helpers/servers.py owns every action, so nothing here runs docker or systemctl.

import "shared"
import "../components"
import "../../services/audio"
import "../../services/layout"
import "../../services/servers"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import "../../services/layout/Orbit.js" as Orbit

Item {
    id: tab

    property var popup: null
    // Part of the contract, but it gates nothing here: Servers watches the panel's own
    // tab, so the helper already stops running when this tab is not the one up.
    property bool active: false

    // --- tab contract -------------------------------------------------------
    readonly property string headerGlyph: tab.problem !== "" ? "\u{f048e}" : "\u{f048d}"
    readonly property bool headerLit: Servers.runningCount > 0
    readonly property string headerStatus: Servers.started ? "" : "Checking…"
    readonly property string footerText: {
        if (!Servers.started || tab.rows.length === 0)
            return "";
        var parts = [Servers.runningCount + " running", tab.stoppedCount + " stopped"];
        if (tab.failedCount > 0)
            parts.push(tab.failedCount + " failed");
        return parts.join(", ");
    }
    readonly property bool textFocus: false
    // No single switch fits N services, so the chassis parks its power morph.
    readonly property bool hasPower: false

    // --- problems -----------------------------------------------------------
    // The next good poll wipes Servers.lastError within a second or two, so a failed
    // stop's reason is latched here long enough to read; a lasting one keeps itself up.
    property string notice: ""
    readonly property string problem: tab.notice !== "" ? tab.notice : Servers.lastError

    Connections {
        target: Servers
        function onLastErrorChanged() {
            if (Servers.lastError === "")
                return;
            tab.notice = Servers.lastError;
            noticeClear.restart();
        }
    }
    Timer {
        id: noticeClear
        interval: 6000
        onTriggered: tab.notice = ""
    }

    // --- model --------------------------------------------------------------
    readonly property var rows: Servers.servers || []

    function tally(s) {
        var n = 0;
        for (var i = 0; i < tab.rows.length; i++)
            if (tab.rows[i] && tab.rows[i].state === s)
                n++;
        return n;
    }
    readonly property int stoppedCount: tab.tally("stopped")
    readonly property int failedCount: tab.tally("failed")

    // kind + id, like the helper's own slots: a container and a unit can share a name.
    function slotOf(svc) {
        return svc ? (("" + svc.kind) + "/" + ("" + svc.id)) : "";
    }

    onRowsChanged: tab.prunePending()

    // --- actions ------------------------------------------------------------
    // A stop or start lands a poll or two later; the row shows what was asked for until
    // the helper agrees, or until the give-up timer drops the claim.
    property var pending: ({})

    function prunePending() {
        if (Object.keys(tab.pending).length === 0)
            return;
        var next = {};
        for (var i = 0; i < tab.rows.length; i++) {
            var r = tab.rows[i];
            var want = r ? tab.pending[tab.slotOf(r)] : undefined;
            if (want !== undefined && r.state !== want)
                next[tab.slotOf(r)] = want;
        }
        tab.pending = next;
        if (Object.keys(next).length === 0)
            pendingGiveUp.stop();
    }
    // A cancelled polkit prompt never changes the unit, so the claim must expire - but not
    // while the helper is still on it: a system unit's prompt is answered at human speed.
    Timer {
        id: pendingGiveUp
        interval: 15000
        onTriggered: {
            if (Servers.acting)
                pendingGiveUp.restart();
            else
                tab.pending = ({});
        }
    }

    function act(svc, start) {
        if (!svc)
            return;
        if (start)
            Servers.start(svc.kind, "" + svc.id);
        else
            Servers.stop(svc.kind, "" + svc.id);

        // Fresh object: mutating a var property emits no change signal.
        var next = {};
        var held = Object.keys(tab.pending);
        for (var i = 0; i < held.length; i++)
            next[held[i]] = tab.pending[held[i]];
        next[tab.slotOf(svc)] = start ? "running" : "stopped";
        tab.pending = next;
        pendingGiveUp.restart();

        Sounds.playSfx(start ? "network/power_on.wav" : "network/power_off.wav");
    }

    // --- row readouts -------------------------------------------------------
    function phaseOf(svc) {
        if (!svc)
            return "unknown";
        var want = tab.pending[tab.slotOf(svc)];
        return want === undefined ? ("" + (svc.state || "unknown")) : want;
    }

    function stateColor(p) {
        if (p === "running")
            return tab.popup.green;
        if (p === "failed")
            return tab.popup.red;
        return tab.popup.overlay0;
    }

    function kindGlyph(k) {
        if (k === "docker")
            return "\u{f0868}";
        if (k === "user")
            return "\u{f0004}";
        if (k === "system")
            return "\u{f08d6}";
        return "\u{f0625}";
    }

    function portText(svc) {
        var p = (svc && svc.ports) ? svc.ports : [];
        if (p.length === 0)
            return "—";
        if (p.length <= 3)
            return p.join("  ");
        return p.slice(0, 3).join("  ") + " +" + (p.length - 3);
    }

    // A remembered port is the last one seen, not one anything is listening on now.
    function noteText(svc) {
        if (!svc)
            return "";
        var bits = [];
        if (svc.detail)
            bits.push("" + svc.detail);
        if (svc.portSource === "seen" && svc.ports && svc.ports.length > 0)
            bits.push("port last seen");
        return bits.join("   ·   ");
    }


    // --- groups -------------------------------------------------------------
    // Fourteen services will not fit one ring, so the ring holds groups and a pick
    // swaps in that group's services. "" is the group level.
    property string groupKey: ""

    readonly property var groupDefs: [
        { key: "docker", label: "Docker", glyph: "\u{f0868}" },
        { key: "user",   label: "User",   glyph: "\u{f0004}" },
        { key: "system", label: "System", glyph: "\u{f08d6}" },
        { key: "other",  label: "Other",  glyph: "\u{f0625}" }
    ]

    function groupOf(svc) {
        var k = svc ? ("" + svc.kind) : "";
        return (k === "docker" || k === "user" || k === "system") ? k : "other";
    }

    function groupRows(key) {
        var out = [];
        for (var i = 0; i < tab.rows.length; i++)
            if (tab.rows[i] && tab.groupOf(tab.rows[i]) === key)
                out.push(tab.rows[i]);
        return out;
    }

    readonly property var groups: {
        var out = [];
        for (var i = 0; i < tab.groupDefs.length; i++) {
            var g = tab.groupDefs[i];
            var members = tab.groupRows(g.key);
            if (members.length > 0)
                out.push({ key: g.key, label: g.label, glyph: g.glyph, count: members.length });
        }
        return out;
    }

    readonly property var openGroup: {
        for (var i = 0; i < tab.groups.length; i++)
            if (tab.groups[i].key === tab.groupKey)
                return tab.groups[i];
        return null;
    }

    // A group that empties out drops you back rather than leaving an empty ring.
    onGroupsChanged: if (tab.groupKey !== "" && tab.openGroup === null) tab.groupKey = "";
    onActiveChanged: if (!tab.active) { tab.groupKey = ""; tab.armedSlot = ""; }

    readonly property var nodes: tab.openGroup
        ? [{ back: true }].concat(tab.groupRows(tab.groupKey))
        : tab.groups
    readonly property int nodeCount: tab.nodes.length
    property real smoothedNodeCount: nodeCount
    Behavior on smoothedNodeCount { NumberAnimation { duration: 1000; easing.type: Easing.InOutExpo } }

    function slotAngle(i, count) {
        return -Math.PI / 2 + (i / Math.max(1, count)) * Math.PI * 2;
    }

    // --- arming -------------------------------------------------------------
    // One armed service at a time: a stop is the only destructive thing here, so it
    // takes a second click. Remote Input cannot hold a button, so holding is not it.
    property string armedSlot: ""
    property double armedAt: 0
    Timer { id: disarm; interval: 6000; onTriggered: tab.armedSlot = "" }
    onGroupKeyChanged: tab.armedSlot = ""

    // Escape backs out of a group before it closes the panel, as the Wi-Fi sheet does.
    function handleEscape() {
        if (tab.armedSlot !== "") { tab.cancel(); return true; }
        if (tab.groupKey !== "") { tab.groupKey = ""; return true; }
        return false;
    }

    function press(svc) {
        if (!svc || svc.canStop === false)
            return;
        var slot = tab.slotOf(svc);
        if (Servers.isBusy("" + svc.kind, "" + svc.id) || tab.pending[slot] !== undefined)
            return;
        if (tab.phaseOf(svc) !== "running") {
            tab.armedSlot = "";
            disarm.stop();
            tab.act(svc, true);
            return;
        }
        if (tab.armedSlot === slot)
            return;
        tab.armedSlot = slot;
        tab.armedAt = Date.now();
        disarm.restart();
        Sounds.playSfx("system/quick_click.wav");
    }

    function cancel() {
        tab.armedSlot = "";
        disarm.stop();
    }

    function commit(svc) {
        // The tick lands where the pill was just clicked, so a double-click must not reach it.
        if (!svc || tab.armedSlot !== tab.slotOf(svc) || Date.now() - tab.armedAt < 250)
            return;
        disarm.stop();
        tab.armedSlot = "";
        tab.act(svc, false);
    }

    // --- orbit --------------------------------------------------------------
    Canvas {
        id: nodeLinesCanvas
        anchors.fill: parent
        z: 0
        opacity: (tab.active && tab.nodeCount > 0) ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 500 } }

        Timer {
            interval: 45; repeat: true
            running: nodeLinesCanvas.opacity > 0.01
            onTriggered: nodeLinesCanvas.requestPaint()
        }

        onPaint: {
            var ctx = getContext("2d");
            var S = tab.popup.s;
            ctx.clearRect(0, 0, width, height);
            if (!tab.active || tab.nodeCount === 0) return;

            var time = Date.now() / 1000;
            var tWave1 = time * 2.5;
            var tWave2 = time * -1.5;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";

            var startX = width / 2, startY = height / 2;
            var coreW = serversCore.width;

            for (var i = 0; i < nodeRepeater.count; i++) {
                var item = nodeRepeater.itemAt(i);
                if (!item || item.width <= 0) continue;
                var targetX = item.x + item.width / 2;
                var targetY = item.y + item.height / 2;
                if (targetX < 0 || targetY < 0 || targetX > width || targetY > height) continue;

                var dx = targetX - startX, dy = targetY - startY;
                var fullDist = Math.sqrt(dx * dx + dy * dy);
                if (fullDist < S(10)) continue;

                var alpha = Math.atan2(dy, dx);
                var cosA = Math.cos(alpha), sinA = Math.sin(alpha);
                var perpX = -sinA, perpY = cosA;
                var startOffset = coreW / 2 + S(5), endOffset = S(35);
                var drawDist = fullDist - startOffset - endOffset;
                if (drawDist <= 0) continue;

                var sX = startX + cosA * startOffset;
                var sY = startY + sinA * startOffset;
                var distanceFactor = Math.max(0, 1.0 - (fullDist / 400.0));
                var wCore = S(1.0) + (distanceFactor * S(2.0));
                var wGlow = S(4.0) + (distanceFactor * S(4.0));
                var a = 0.2 + (distanceFactor * 0.7);
                var tint = item.accentColor;

                for (var pass = 0; pass < 2; pass++) {
                    ctx.beginPath();
                    ctx.globalAlpha = pass === 0 ? a * 0.18 : a;
                    ctx.lineWidth = pass === 0 ? wGlow : wCore;
                    ctx.strokeStyle = tint;
                    for (var step = 0; step <= 20; step++) {
                        var t = step / 20;
                        var along = t * drawDist;
                        var taper = Math.sin(t * Math.PI);
                        var wob = Math.sin(t * 9 + tWave1 + i) * S(3) * taper
                                + Math.sin(t * 5 + tWave2 - i) * S(2) * taper;
                        var px = sX + cosA * along + perpX * wob;
                        var py = sY + sinA * along + perpY * wob;
                        if (step === 0) ctx.moveTo(px, py);
                        else ctx.lineTo(px, py);
                    }
                    ctx.stroke();
                }
            }
            ctx.globalAlpha = 1.0;
        }
    }

    Repeater {
        model: 4
        delegate: Rectangle {
            required property int index
            anchors.centerIn: parent
            width: serversCore.width + tab.popup.s(70) * (index + 1)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: tab.popup.accent
            opacity: tab.active ? (0.06 - index * 0.012) : 0.02
            Behavior on opacity { NumberAnimation { duration: 500 } }
        }
    }

    // --- core ---------------------------------------------------------------
    NetworkCore {
        id: serversCore
        anchors.centerIn: parent
        popup: tab.popup

        connected: tab.rows.length > 0
        powered: true
        scanning: !Servers.started
        holdEnabled: false
        interactive: tab.openGroup !== null
        width: tab.popup.s(tab.openGroup ? 180 : 200)

        glyph: tab.openGroup ? tab.openGroup.glyph : "\u{f048d}"
        offGlyph: "\u{f048e}"
        name: tab.openGroup ? tab.openGroup.label
                            : (Servers.runningCount + " running")
        statusText: tab.openGroup ? (tab.openGroup.count + " service" + (tab.openGroup.count === 1 ? "" : "s"))
                                  : (tab.rows.length + " service" + (tab.rows.length === 1 ? "" : "s"))
        offText: Servers.started ? "Nothing found" : "Looking…"

        onTapped: tab.groupKey = ""
    }

    // Only inside a group: the way back out, and the one hint the core cannot carry.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: serversCore.bottom
        anchors.topMargin: tab.popup.s(10)
        text: tab.problem !== "" ? tab.problem
            : (tab.rows.length === 0 && Servers.started ? "Add units in Settings → Network" : "")
        color: tab.problem !== "" ? tab.popup.red : tab.popup.overlay0
        font.family: Fonts.ui
        font.pixelSize: tab.popup.s(10)
        width: tab.width - tab.popup.s(80)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        opacity: text === "" ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    // --- nodes --------------------------------------------------------------
    Repeater {
        id: nodeRepeater
        // Built only once the tab has a size, or every node starts on the origin.
        model: (tab.width > 0 && tab.height > 0) ? tab.nodes : []

        delegate: InfoNode {
            id: node
            required property var modelData
            required property int index
            popup: tab.popup

            readonly property bool isBack: node.modelData.back === true
            readonly property bool isGroup: !node.isBack && tab.openGroup === null
            readonly property bool isSvc: !node.isBack && !node.isGroup
            readonly property string slot: node.isSvc ? tab.slotOf(node.modelData) : ""
            readonly property string phase: node.isSvc ? tab.phaseOf(node.modelData) : ""
            readonly property bool armed: node.isSvc && tab.armedSlot === node.slot
            readonly property bool busy: node.isSvc
                && (Servers.isBusy("" + node.modelData.kind, "" + node.modelData.id)
                    || tab.pending[node.slot] !== undefined)

            value: node.isBack ? "Back"
                 : node.isGroup ? ("" + node.modelData.count)
                 : (node.busy ? "Working…" : tab.portText(node.modelData))
            label: node.isBack ? "All groups"
                 : node.isGroup ? node.modelData.label
                 : ("" + node.modelData.name)
            glyph: node.isBack ? "\u{f004d}"
                 : node.isGroup ? node.modelData.glyph
                 : tab.kindGlyph(node.modelData.kind)
            actionable: node.isBack || node.isGroup
                     || (node.modelData.canStop !== false && !node.busy)
            emphasised: node.isSvc
            accentColor: node.armed ? tab.popup.red
                       : node.isSvc ? tab.stateColor(node.phase)
                       : tab.popup.accent

            onTriggered: {
                if (node.isBack)
                    tab.groupKey = "";
                else if (node.isGroup)
                    tab.groupKey = node.modelData.key;
                else
                    tab.press(node.modelData);
            }

            readonly property real nodeAngle: tab.slotAngle(index, tab.nodeCount)
            readonly property var radii: Orbit.ringRadii({ x: tab.popup.s(285), y: tab.popup.s(185) },
                                                         0, tab.smoothedNodeCount,
                                                         { x: tab.popup.s(6), y: tab.popup.s(4) })
            readonly property var spot: Orbit.clampIn(
                Orbit.pos(tab.width, tab.height, node.nodeAngle, node.radii.x, node.radii.y,
                          node.width, node.height),
                node.width, node.height, tab.width, tab.height)
            x: node.spot.x
            y: node.spot.y

            property bool placed: false
            Component.onCompleted: { placed = true; entryAnim = 1.0; }
            Behavior on x { enabled: node.placed; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }
            Behavior on y { enabled: node.placed; NumberAnimation { duration: 600; easing.type: Easing.OutQuint } }

            property real entryAnim: 0.0
            Behavior on entryAnim { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
            entryScale: 0.6 + 0.4 * entryAnim
            opacity: entryAnim

            // Armed: the pill hands over two targets instead of asking for a blind second
            // click where the first one landed.
            Item {
                anchors.fill: parent
                visible: node.armed
                z: 5

                Rectangle {
                    anchors.fill: parent
                    radius: Radius.outer(tab.popup.s(14))
                    color: Qt.alpha(tab.popup.surface0, 0.97)
                    border.width: 1
                    border.color: tab.popup.red
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: tab.popup.s(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Stop?"
                    font.family: Fonts.ui
                    font.weight: Font.Bold
                    font.pixelSize: tab.popup.s(12)
                    color: tab.popup.red
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: tab.popup.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: tab.popup.s(6)

                    PillButton {
                        glyph: "\u{f0156}"           // md-close
                        tint: tab.popup.overlay0
                        onHit: tab.cancel()
                    }
                    PillButton {
                        glyph: "\u{f012c}"           // md-check
                        tint: tab.popup.red
                        onHit: tab.commit(node.modelData)
                    }
                }
            }
        }
    }

    component PillButton: Rectangle {
        id: btn
        property string glyph: ""
        property color tint: "white"
        signal hit()

        width: tab.popup.s(30)
        height: width
        radius: width / 2
        color: btnMa.containsMouse ? Qt.alpha(btn.tint, 0.22) : Qt.alpha(tab.popup.surface2, 0.6)
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: btnMa.pressed ? 0.92 : (btnMa.containsMouse ? 1.08 : 1.0)
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: btn.glyph
            font.family: "Iosevka Nerd Font"
            font.pixelSize: tab.popup.s(15)
            color: btn.tint
        }

        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.hit()
        }
    }
}
