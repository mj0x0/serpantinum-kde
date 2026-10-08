import "../../../services/settings"
import QtQuick

Item {
    id: root

    property var picker
    property int currentIndex: -1
    readonly property int count: 5
    property var order: []
    property int page: 0
    readonly property var hand: root.order.slice(root.page * root.count, root.page * root.count + root.count)
    readonly property int selectedSlot: root.hand.indexOf(root.currentIndex)
    property bool snapping: false
    property bool dealing: false
    property real dealT: 0
    property int dealDir: 1
    property string move: "cascade"
    property var leaving: []
    property int leavingSel: -1
    // Still the previous index while onCurrentIndexChanged runs, so dealTo knows the old highlight.
    property int shownIndex: -1
    property int cycleAt: -1
    property real tilt: 0

    readonly property real cardW: root.picker.s(230) * root.sizeScale
    readonly property real cardH: root.picker.s(345) * root.sizeScale
    readonly property real spread: root.picker.s(200) * root.sizeScale
    readonly property real yawStep: 10
    readonly property real arch: root.picker.s(5) * root.sizeScale
    readonly property real c: (root.count - 1) / 2
    // What the popup should give us: the fan at the requested size, uncapped, plus margins.
    readonly property real wantedHeight: (root.picker.s(345) * 1.18 + 4 * root.picker.s(5)) * (ShellSettings.handCardSize / 100) + root.picker.s(48)
    // Capped so the selected card (1.18x) and the fan's width stay inside the stage at any knob value.
    readonly property real sizeScale: Math.min(ShellSettings.handCardSize / 100,
                                               (stage.height - root.picker.s(24)) / (root.picker.s(345) * 1.18 + 4 * root.picker.s(5)),
                                               (stage.width - root.picker.s(48)) / (4 * root.picker.s(200) + root.picker.s(230) * 1.18))
    readonly property bool animate: !root.dealing && !root.snapping && root.picker.initialFocusSet

    function refreshOrder() {
        if (!root.picker)
            return;
        root.order = root.picker.visibleIndexList();
        const pos = root.order.indexOf(root.currentIndex);
        const last = Math.max(0, Math.ceil(root.order.length / root.count) - 1);
        root.page = pos >= 0 ? Math.floor(pos / root.count) : Math.min(root.page, last);
    }

    function snapTo(index) {
        root.snapping = true;
        root.currentIndex = index;
        root.refreshOrder();
        root.snapping = false;
    }

    function stepRow(direction) {
        const p = root.page + direction;
        if (p < 0 || p * root.count >= root.order.length)
            return;
        const target = Math.min(p * root.count + Math.max(0, root.selectedSlot), root.order.length - 1);
        root.currentIndex = root.order[target];
    }

    function selectedRect() {
        const it = root.selectedSlot >= 0 ? resting.itemAt(root.selectedSlot) : null;
        if (!it || !it.visible)
            return null;
        return it.mapToItem(root, 0, 0, it.width, it.height);
    }

    function pickMove() {
        const moves = ["cascade", "corkscrew", "shuffle", "spiral"];
        const want = "" + ShellSettings.value("wallpaper.handMove", "random");
        if (moves.indexOf(want) >= 0)
            return want;
        if (want === "cycle") {
            root.cycleAt = (root.cycleAt + 1) % moves.length;
            return moves[root.cycleAt];
        }
        return moves[Math.floor(Math.random() * moves.length)];
    }

    function dealTo(p) {
        if (root.snapping || !root.picker.initialFocusSet) {
            root.page = p;
            return;
        }
        if (root.dealing)
            dealAnim.stop();
        root.leaving = root.hand.map(i => {
            const e = root.picker.activeModel.get(i);
            return e ? ({ fileName: "" + e.fileName, fileUrl: "" + e.fileUrl }) : null;
        });
        root.leavingSel = root.hand.indexOf(root.shownIndex);
        root.dealDir = p > root.page ? 1 : -1;
        root.move = root.pickMove();
        root.dealT = 0;
        root.dealing = true;
        root.page = p;
        dealAnim.restart();
    }

    onCurrentIndexChanged: {
        root.picker.noteItemMove();
        const pos = root.order.indexOf(root.currentIndex);
        if (pos >= 0) {
            const p = Math.floor(pos / root.count);
            if (p !== root.page)
                root.dealTo(p);
        }
        root.shownIndex = root.currentIndex;
    }
    onPickerChanged: root.refreshOrder()
    Component.onCompleted: root.refreshOrder()

    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    function lerp(a, b, u) {
        return a + (b - a) * u;
    }

    function easeOut(u) {
        return 1 - Math.pow(1 - u, 3);
    }

    function easeIn(u) {
        return u * u * u;
    }

    function easeInOut(u) {
        return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(2 - 2 * u, 3) / 2;
    }

    function stagger(t, k, step) {
        return root.clamp01((t - k * step) / (1 - (root.count - 1) * step));
    }

    function restPose(slot, sel) {
        if (sel === undefined)
            sel = root.selectedSlot;
        const d = slot - root.c;
        return {
            x: stage.width / 2 - root.cardW / 2 + d * root.spread,
            y: stage.height / 2 - root.cardH / 2 + d * d * root.arch,
            yaw: d * root.yawStep,
            roll: 0,
            scale: slot === sel ? 1.18 : 1.0,
            opacity: slot === sel ? 1 : 0.72
        };
    }

    function dealPose(kind, dir, phase, t, slot) {
        const out = phase === "out";
        const rest = root.restPose(slot, out ? root.leavingSel : root.selectedSlot);
        const k = dir > 0 ? slot : root.count - 1 - slot;
        switch (kind) {
        case "corkscrew":
            return root.corkscrew(rest, dir, out, root.stagger(t, k, 0.07));
        case "shuffle":
            return root.shuffle(rest, dir, out, t, k);
        case "spiral":
            return root.spiral(rest, dir, out, root.stagger(t, k, 0.07));
        default:
            return root.cascade(rest, dir, out, root.stagger(t, k, 0.07));
        }
    }

    function cascade(rest, dir, out, st) {
        if (out) {
            return {
                x: rest.x,
                y: rest.y + (stage.height + root.cardH - rest.y) * root.easeIn(st),
                yaw: rest.yaw,
                roll: dir * 14 * st,
                scale: rest.scale,
                opacity: rest.opacity * (1 - st)
            };
        }
        const u = root.easeOut(st);
        return {
            x: rest.x,
            y: root.lerp(-root.cardH, rest.y, u),
            yaw: rest.yaw,
            roll: -dir * 10 * (1 - u),
            scale: rest.scale,
            opacity: rest.opacity * Math.min(1, st * 2.5)
        };
    }

    function corkscrew(rest, dir, out, st) {
        if (out) {
            return {
                x: rest.x,
                y: rest.y - (rest.y + root.cardH) * root.easeIn(st),
                yaw: rest.yaw + dir * 540 * st,
                roll: 0,
                scale: rest.scale * (1 - 0.6 * st),
                opacity: rest.opacity * (1 - st * st)
            };
        }
        const u = root.easeOut(st);
        return {
            x: rest.x,
            y: root.lerp(stage.height, rest.y, u),
            yaw: rest.yaw + dir * 540 * (1 - u),
            roll: 0,
            scale: rest.scale * (0.4 + 0.6 * u),
            opacity: rest.opacity * Math.min(1, st * 2)
        };
    }

    function shuffle(rest, dir, out, t, k) {
        const split = 0.4;
        const sx = stage.width / 2 - root.cardW / 2;
        const sy = stage.height / 2 - root.cardH / 2;
        const drift = dir * root.cardW * 0.4;
        if (out) {
            if (t < split) {
                const u = root.easeInOut(t / split);
                return {
                    x: root.lerp(rest.x, sx, u),
                    y: root.lerp(rest.y, sy, u),
                    yaw: rest.yaw * (1 - u),
                    roll: 0,
                    scale: root.lerp(rest.scale, 0.92, u),
                    opacity: root.lerp(rest.opacity, 1, u)
                };
            }
            const v = root.stagger((t - split) / (1 - split), k, 0.08);
            return {
                x: sx + drift * v,
                y: sy + (stage.height + root.cardH - sy) * root.easeIn(v),
                yaw: 0,
                roll: dir * 18 * v,
                scale: 0.92,
                opacity: 1 - v
            };
        }
        if (t < split)
            return { x: sx, y: stage.height, yaw: 0, roll: 0, scale: 0.92, opacity: 0 };
        const v = root.stagger((t - split) / (1 - split), k, 0.08);
        if (v < 0.5) {
            const u = root.easeOut(v / 0.5);
            return {
                x: sx - drift * (1 - u),
                y: root.lerp(stage.height, sy, u),
                yaw: 0,
                roll: -dir * 18 * (1 - u),
                scale: 0.92,
                opacity: Math.min(1, u * 2)
            };
        }
        const u = root.easeOut((v - 0.5) / 0.5);
        return {
            x: root.lerp(sx, rest.x, u),
            y: root.lerp(sy, rest.y, u),
            yaw: rest.yaw * u,
            roll: 0,
            scale: root.lerp(0.92, rest.scale, u),
            opacity: root.lerp(1, rest.opacity, u)
        };
    }

    function spiral(rest, dir, out, st) {
        const cx = stage.width / 2;
        const cy = stage.height / 2;
        const dx = rest.x + root.cardW / 2 - cx;
        const dy = rest.y + root.cardH / 2 - cy;
        const r0 = Math.sqrt(dx * dx + dy * dy);
        const a0 = Math.atan2(dy, dx);
        const u = out ? root.easeIn(st) : 1 - root.easeOut(st);
        const a = a0 + dir * Math.PI * 2 * u;
        const r = root.lerp(r0, stage.width / 2 + root.cardW / 2, u);
        return {
            x: cx + r * Math.cos(a) - root.cardW / 2,
            y: cy + r * Math.sin(a) - root.cardH / 2,
            yaw: rest.yaw * (1 - u),
            roll: dir * 360 * u,
            scale: rest.scale * (1 - 0.7 * u),
            opacity: rest.opacity * (out ? 1 - st : Math.min(1, st * 2))
        };
    }

    Behavior on tilt {
        NumberAnimation {
            duration: 250
        }
    }

    Connections {
        target: root.picker
        function onCacheVersionChanged() {
            root.refreshOrder();
        }
        function onCurrentFilterChanged() {
            root.refreshOrder();
        }
    }

    Connections {
        target: root.picker.activeModel
        function onCountChanged() {
            root.refreshOrder();
        }
    }

    NumberAnimation {
        id: dealAnim
        target: root
        property: "dealT"
        from: 0
        to: 1
        duration: 700
        easing.type: Easing.InOutSine
        onFinished: {
            root.dealing = false;
            root.leaving = [];
        }
    }

    // Sits outside the tilting stage: measured inside it, the tilt would move its own mouseX.
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        anchors.topMargin: root.picker.contentTop
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        onPositionChanged: root.tilt = (hoverArea.mouseX / hoverArea.width - 0.5) * 8
        onExited: root.tilt = 0
        onWheel: wheel => {
            if (!root.picker.isApplying) {
                const d = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) ? wheel.angleDelta.x : wheel.angleDelta.y;
                root.picker.wheelStep(d);
            }
            wheel.accepted = true;
        }
    }

    Item {
        id: stage
        anchors.fill: parent
        anchors.topMargin: root.picker.contentTop
        transform: Rotation {
            origin.x: stage.width / 2
            origin.y: stage.height / 2
            axis {
                x: 0
                y: 1
                z: 0
            }
            angle: root.tilt
        }

        Repeater {
            id: resting
            model: root.count

            delegate: Item {
                id: slot

                required property int index
                readonly property var entry: {
                    const i = root.hand[slot.index];
                    return i === undefined ? null : (root.picker.activeModel.get(i) || null);
                }
                readonly property bool selected: slot.index === root.selectedSlot
                readonly property bool isVideo: slot.entry !== null && ("" + slot.entry.fileName).startsWith("000_")
                readonly property var pose: root.dealing ? root.dealPose(root.move, root.dealDir, "in", root.dealT, slot.index) : root.restPose(slot.index)
                property real yawAngle: slot.pose.yaw

                width: root.cardW
                height: root.cardH
                x: slot.pose.x
                y: slot.pose.y
                scale: slot.pose.scale
                opacity: slot.pose.opacity
                rotation: slot.pose.roll
                z: 100 - Math.abs(slot.index - root.c) + (slot.selected ? 50 : 0)
                transform: Rotation {
                    origin.x: root.cardW / 2
                    origin.y: root.cardH / 2
                    axis {
                        x: 0
                        y: 1
                        z: 0
                    }
                    angle: slot.yawAngle
                }

                Behavior on y {
                    enabled: root.animate
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on scale {
                    enabled: root.animate
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on opacity {
                    enabled: root.animate
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: slot.entry !== null
                    sourceComponent: PickerCard {
                        picker: root.picker
                        fileName: slot.entry ? "" + slot.entry.fileName : ""
                        fileUrl: slot.entry ? "" + slot.entry.fileUrl : ""
                        current: slot.selected
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: slot.entry !== null && !root.dealing && !root.picker.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (slot.selected)
                            root.picker.applyWallpaper("" + slot.entry.fileName, slot.isVideo);
                        else
                            root.currentIndex = root.hand[slot.index];
                    }
                }
            }
        }

        Repeater {
            model: root.count

            delegate: Item {
                id: gone

                required property int index
                readonly property var entry: root.leaving[gone.index] || null
                readonly property var pose: root.dealPose(root.move, root.dealDir, "out", root.dealT, gone.index)
                property real yawAngle: gone.pose.yaw

                visible: root.dealing && gone.entry !== null
                width: root.cardW
                height: root.cardH
                x: gone.pose.x
                y: gone.pose.y
                scale: gone.pose.scale
                opacity: gone.pose.opacity
                rotation: gone.pose.roll
                z: 200 - Math.abs(gone.index - root.c)
                transform: Rotation {
                    origin.x: root.cardW / 2
                    origin.y: root.cardH / 2
                    axis {
                        x: 0
                        y: 1
                        z: 0
                    }
                    angle: gone.yawAngle
                }

                Loader {
                    anchors.fill: parent
                    active: gone.entry !== null
                    sourceComponent: PickerCard {
                        picker: root.picker
                        fileName: gone.entry ? gone.entry.fileName : ""
                        fileUrl: gone.entry ? gone.entry.fileUrl : ""
                        current: false
                    }
                }
            }
        }
    }
}
