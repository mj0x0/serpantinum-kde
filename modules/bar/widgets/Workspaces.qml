// Workspace switcher: eight styles on the KWin workspaces bridge; placed by TopBar via targetX/targetY.
import "../../../services/audio"
import "../../../services/reusables/rpoly"
import "../../../services/reusables/rpoly/material-shapes.js" as MaterialShapes
import "../../../services/settings"
import "../../../services/theme"
import QtQuick
import QtQuick.Shapes
import Quickshell

Rectangle {
    id: workspacesBox
    required property var barWindow
    required property var mocha
    required property var workspacesModel
    color: grouped ? "transparent" : barWindow.pillBg
    radius: barWindow.pillRadius; border.width: grouped ? 0 : 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05 * barWindow.pillBorderAlpha)
    property bool vertical: false
    property bool shown: true
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0

    // bar.workspaces.* knobs; every style keeps active/occupied/empty distinct.
    property string wsStyle: "" + ShellSettings.value("bar.workspaces.style", "pills")
    property bool activeIndicator: ShellSettings.value("bar.workspaces.activeIndicator", true) !== false
    property bool occupiedBg: ShellSettings.value("bar.workspaces.occupiedBg", true) !== false
    // Named palette role, so the tint follows the wallpaper like everything else.
    property string occupiedColorName: "" + ShellSettings.value("bar.workspaces.occupiedColor", "text")
    readonly property color occupiedTint: mocha[workspacesBox.occupiedColorName] !== undefined
                                        ? mocha[workspacesBox.occupiedColorName] : mocha.text

    // glyphs style: console, web, code, folder, chat, music, gamepad, image, email, cog; past the list, the number.
    readonly property var defaultGlyphs: ["\u{f018d}", "\u{f059f}", "\u{f0169}", "\u{f024b}", "\u{f0b79}",
                                          "\u{f075a}", "\u{f0297}", "\u{f02e9}", "\u{f01ee}", "\u{f0493}"]
    readonly property var glyphs: {
        let g = ShellSettings.value("bar.workspaces.glyphs", null);
        return (g && typeof g.length === "number" && g.length > 0) ? g : defaultGlyphs;
    }

    // Cells: pills are v2's capsules (the active one stretched); every other style keeps square cells.
    readonly property bool usesPills: wsStyle === "pills"
    readonly property real cellSize: barWindow.s(32)
    readonly property real cellSpacing: usesPills ? barWindow.s(8) : barWindow.s(6)
    readonly property real pillShort: barWindow.s(18)
    readonly property real pillLong: barWindow.s(36)

    readonly property bool hasContent: shown && placed && workspacesModel.count > 0
    readonly property real targetWidth: (hasContent && !vertical) ? wsLayout.implicitWidth + barWindow.s(20) : 0
    readonly property real targetHeight: (hasContent && vertical) ? wsLayout.implicitHeight + barWindow.s(20) : 0
    height: vertical ? targetHeight : barWindow.barHeight
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    clip: true

    width: vertical ? parent.width : targetWidth
    x: vertical ? 0 : targetX
    Behavior on x { enabled: barWindow.startupCascadeFinished && !workspacesBox.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && workspacesBox.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    visible: shown && placed && ((vertical ? height : width) > 0 || opacity > 0)
    opacity: workspacesModel.count > 0 ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 300 } }

    // --- Mouse-wheel desktop switching --- delegates to KWin's own Next/Previous
    // shortcuts. NoButton MouseArea, not WheelHandler: clicks and hover fall through.
    Timer { id: wsWheelCooldown; interval: 120; onTriggered: wsWheelArea.cooling = false }

    MouseArea {
        id: wsWheelArea
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.NoButton   // clicks pass straight through
        hoverEnabled: false            // hover passes through too
        propagateComposedEvents: true

        property int acc: 0            // accumulated angle, for fine-grained devices
        property bool cooling: false   // rate-limit so a fast flick can't flood KWin

        onWheel: (wheel) => {
            var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
            if (d === 0)
                return;
            wsWheelArea.acc += d;
            // One notch is 120; accumulating also smooths touchpads,
            // which emit many small deltas per gesture.
            if (Math.abs(wsWheelArea.acc) < 120)
                return;
            var next = wsWheelArea.acc < 0;   // wheel down = next, up = previous
            wsWheelArea.acc = 0;
            if (wsWheelArea.cooling)
                return;
            wsWheelArea.cooling = true;
            wsWheelCooldown.restart();
            Quickshell.execDetached(["qdbus6", "org.kde.kglobalaccel",
                                     "/component/kwin", "invokeShortcut",
                                     next ? "Switch to Next Desktop"
                                          : "Switch to Previous Desktop"]);
        }
    }

    // Sliding highlight for the uniform-cell styles; underline and Pac-Man ride its spring values too.
    Rectangle {
        id: activeHighlight
        y: workspacesBox.vertical ? actualTop : (workspacesBox.height - workspacesBox.cellSize) / 2
        height: workspacesBox.vertical ? actualBottom - actualTop : workspacesBox.cellSize
        radius: barWindow.innerRadius
        color: mocha.mauve
        z: 0

        property int prevIdx: 0
        property int curIdx: workspacesModel.activeIndex
        property int dir: 1

        onCurIdxChanged: {
            if (curIdx > prevIdx) {
                rightAnim.duration = 200; leftAnim.duration = 350;
                bottomAnim.duration = 200; topAnim.duration = 350;
                dir = 1;
            } else if (curIdx < prevIdx) {
                leftAnim.duration = 200; rightAnim.duration = 350;
                topAnim.duration = 200; bottomAnim.duration = 350;
                dir = -1;
            }
            prevIdx = curIdx;
            pacman.chomp();
        }

        property real stepSize: workspacesBox.cellSize + workspacesBox.cellSpacing
        property real targetLeft: wsLayout.x + (curIdx * stepSize)
        property real targetRight: targetLeft + workspacesBox.cellSize
        property real targetTop: wsLayout.y + (curIdx * stepSize)
        property real targetBottom: targetTop + workspacesBox.cellSize

        property real actualLeft: targetLeft
        property real actualRight: targetRight
        property real actualTop: targetTop
        property real actualBottom: targetBottom

        Behavior on actualLeft { NumberAnimation { id: leftAnim; duration: 250; easing.type: Easing.OutExpo } }
        Behavior on actualRight { NumberAnimation { id: rightAnim; duration: 250; easing.type: Easing.OutExpo } }
        Behavior on actualTop { NumberAnimation { id: topAnim; duration: 250; easing.type: Easing.OutExpo } }
        Behavior on actualBottom { NumberAnimation { id: bottomAnim; duration: 250; easing.type: Easing.OutExpo } }

        x: workspacesBox.vertical ? (workspacesBox.width - workspacesBox.cellSize) / 2 : actualLeft
        width: workspacesBox.vertical ? workspacesBox.cellSize : actualRight - actualLeft
        visible: (workspacesBox.wsStyle === "numbers" || workspacesBox.wsStyle === "glyphs") && workspacesBox.activeIndicator
        opacity: workspacesModel.count > 0 ? 1 : 0
    }

    // v2's pill highlight: the leading edge runs ahead of the trailing one.
    Rectangle {
        id: pillHighlight
        visible: workspacesBox.usesPills && workspacesBox.activeIndicator && curIdx >= 0 && workspacesModel.count > 0
        z: 0
        color: mocha.mauve
        radius: workspacesBox.pillShort / 2

        property int prevIdx: 0
        property int curIdx: workspacesModel.activeIndex

        onCurIdxChanged: {
            if (curIdx > prevIdx) { startAnim.duration = 400; endAnim.duration = 300; }
            else if (curIdx < prevIdx) { startAnim.duration = 300; endAnim.duration = 400; }
            prevIdx = curIdx;
        }

        // From final pill sizes, so the highlight never chases the pills while they animate.
        function offsetOf(i) {
            let off = 0;
            for (let k = 0; k < i; k++)
                off += (k === curIdx ? workspacesBox.pillLong : workspacesBox.pillShort) + workspacesBox.cellSpacing;
            return off;
        }
        property real targetStart: curIdx >= 0 ? offsetOf(curIdx) : 0
        property real targetEnd: targetStart + workspacesBox.pillLong
        property real actualStart: targetStart
        property real actualEnd: targetEnd
        Behavior on actualStart { NumberAnimation { id: startAnim; duration: 380; easing.type: Easing.OutQuint } }
        Behavior on actualEnd { NumberAnimation { id: endAnim; duration: 380; easing.type: Easing.OutQuint } }

        x: workspacesBox.vertical ? wsLayout.x + (wsLayout.width - width) / 2 : wsLayout.x + actualStart
        y: workspacesBox.vertical ? wsLayout.y + actualStart : wsLayout.y + (wsLayout.height - height) / 2
        width: workspacesBox.vertical ? workspacesBox.pillShort : actualEnd - actualStart
        height: workspacesBox.vertical ? actualEnd - actualStart : workspacesBox.pillShort
    }

    // Slim sliding bar for the underline style; rides the same spring values.
    Rectangle {
        visible: workspacesBox.wsStyle === "underline" && workspacesBox.activeIndicator
        color: mocha.mauve
        radius: barWindow.s(2)
        x: workspacesBox.vertical
           ? (workspacesBox.width + barWindow.s(32)) / 2 + barWindow.s(1)
           : activeHighlight.actualLeft + barWindow.s(5)
        y: workspacesBox.vertical
           ? activeHighlight.actualTop + barWindow.s(5)
           : (workspacesBox.height + barWindow.s(32)) / 2 + barWindow.s(1)
        width: workspacesBox.vertical ? barWindow.s(3) : barWindow.s(22)
        height: workspacesBox.vertical ? barWindow.s(22) : barWindow.s(3)
        opacity: workspacesModel.count > 0 ? 1 : 0
    }

    // Pac-Man chomps his way to the active workspace, facing the way he moved.
    Item {
        id: pacman
        z: 5
        visible: workspacesBox.wsStyle === "pacman" && workspacesModel.count > 0 && workspacesModel.activeIndex >= 0
        readonly property real sz: barWindow.s(18)
        width: sz
        height: sz
        x: workspacesBox.vertical ? (workspacesBox.width - sz) / 2
                                  : (activeHighlight.actualLeft + activeHighlight.actualRight - sz) / 2
        y: workspacesBox.vertical ? (activeHighlight.actualTop + activeHighlight.actualBottom - sz) / 2
                                  : (workspacesBox.height - sz) / 2
        // At either end he turns to face the way he can still travel, like hitting a wall.
        readonly property int facing: workspacesModel.activeIndex <= 0 ? 1
                                    : (workspacesModel.activeIndex >= workspacesModel.count - 1 ? -1 : activeHighlight.dir)
        rotation: workspacesBox.vertical ? (facing > 0 ? 90 : -90) : 0
        transform: Scale { origin.x: pacman.sz / 2; xScale: workspacesBox.vertical ? 1 : pacman.facing }

        property real mouth: 32
        property bool chomping: false
        function chomp() { chomping = true; chompStop.restart(); }
        Timer { id: chompStop; interval: 450; onTriggered: { pacman.chomping = false; pacman.mouth = 32; } }
        SequentialAnimation on mouth {
            running: pacman.chomping
            loops: Animation.Infinite
            NumberAnimation { to: 3; duration: 80; easing.type: Easing.InQuad }
            NumberAnimation { to: 40; duration: 80; easing.type: Easing.OutQuad }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: mocha.mauve
                strokeColor: "transparent"
                startX: pacman.sz / 2
                startY: pacman.sz / 2
                PathAngleArc {
                    centerX: pacman.sz / 2; centerY: pacman.sz / 2
                    radiusX: pacman.sz / 2; radiusY: pacman.sz / 2
                    startAngle: pacman.mouth
                    sweepAngle: 360 - pacman.mouth * 2
                }
                PathLine { x: pacman.sz / 2; y: pacman.sz / 2 }
            }
        }
        Rectangle {
            x: pacman.sz * 0.46
            y: pacman.sz * 0.17
            width: barWindow.s(2.5)
            height: width
            radius: width / 2
            color: mocha.crust
        }
    }

    Grid {
        id: wsLayout
        columns: workspacesBox.vertical ? 1 : (workspacesModel.count || 1)
        onColumnsChanged: Qt.callLater(wsLayout.forceLayout)
        anchors.centerIn: parent
        spacing: workspacesBox.cellSpacing

        Repeater {
            model: workspacesModel
            delegate: Rectangle {
                id: wsPill

                property bool isLimited: false
                visible: !isLimited

                property bool isHovered: wsPillMouse.containsMouse

                property string stateLabel: model.wsState
                property string wsName: model.wsId
                readonly property bool isActive: index === workspacesModel.activeIndex
                readonly property bool isOccupied: stateLabel === "occupied"
                readonly property string st: workspacesBox.wsStyle
                // numbers and glyphs sit in boxes that take the sliding highlight.
                readonly property bool boxed: st === "numbers" || st === "glyphs"

                readonly property real along: workspacesBox.usesPills ? (isActive ? workspacesBox.pillLong : workspacesBox.pillShort)
                                                                      : workspacesBox.cellSize
                readonly property real across: workspacesBox.usesPills ? workspacesBox.pillShort : workspacesBox.cellSize
                width: workspacesBox.vertical ? across : along
                height: workspacesBox.vertical ? along : across
                Behavior on width { enabled: workspacesBox.usesPills; NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                Behavior on height { enabled: workspacesBox.usesPills; NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
                radius: workspacesBox.usesPills ? workspacesBox.pillShort / 2 : barWindow.innerRadius

                color: {
                    if (st === "pills") {
                        if (isActive) return workspacesBox.activeIndicator ? "transparent" : mocha.mauve;
                        if (isOccupied && workspacesBox.occupiedBg)
                            return Qt.rgba(workspacesBox.occupiedTint.r, workspacesBox.occupiedTint.g,
                                           workspacesBox.occupiedTint.b, isHovered ? 0.5 : 0.35);
                        return Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.16 : 0.08);
                    }
                    if (boxed) {
                        if (isHovered)
                            return Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.1);
                        if (isOccupied && workspacesBox.occupiedBg)
                            return Qt.rgba(workspacesBox.occupiedTint.r, workspacesBox.occupiedTint.g,
                                           workspacesBox.occupiedTint.b, 0.15);
                        return "transparent";
                    }
                    return isHovered ? Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.06) : "transparent";
                }

                scale: wsPillMouse.pressed ? 0.9 : (isHovered && !isActive ? 1.08 : 1.0)
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                property bool initAnimTrigger: false
                opacity: initAnimTrigger ? 1 : 0
                transform: Translate {
                    y: wsPill.initAnimTrigger ? 0 : barWindow.s(15)
                    Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                }

                Component.onCompleted: {
                    if (!barWindow.startupCascadeFinished) {
                        animTimer.interval = index * 60;
                        animTimer.start();
                    } else {
                        initAnimTrigger = true;
                    }
                }

                Timer {
                    id: animTimer
                    running: false
                    repeat: false
                    onTriggered: wsPill.initAnimTrigger = true
                }

                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 250 } }

                // numbers, underline and glyphs: the label (a glyph, or the number past the glyph list).
                Text {
                    visible: wsPill.boxed || wsPill.st === "underline"
                    anchors.centerIn: parent
                    readonly property bool useGlyph: wsPill.st === "glyphs" && index < workspacesBox.glyphs.length
                                                     && ("" + workspacesBox.glyphs[index]) !== ""
                    text: useGlyph ? "" + workspacesBox.glyphs[index] : wsName
                    font.family: useGlyph ? "Iosevka Nerd Font" : Fonts.ui
                    font.pixelSize: useGlyph ? barWindow.s(17) : barWindow.s(14)
                    font.weight: stateLabel === "active" ? Font.Black : (stateLabel === "occupied" ? Font.Bold : Font.Medium)

                    color: {
                        if (wsPill.isActive)
                            return (wsPill.boxed && workspacesBox.activeIndicator) ? mocha.crust : mocha.mauve;
                        if (isHovered) return mocha.text;
                        return wsPill.isOccupied && workspacesBox.occupiedBg ? workspacesBox.occupiedTint : mocha.overlay0;
                    }

                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                // dots: fixed pips, the active one stretched along the bar.
                Rectangle {
                    visible: wsPill.st === "dots"
                    anchors.centerIn: parent
                    readonly property bool isActive: wsPill.isActive
                    width: workspacesBox.vertical ? barWindow.s(10) : (isActive ? barWindow.s(22) : barWindow.s(10))
                    height: workspacesBox.vertical ? (isActive ? barWindow.s(22) : barWindow.s(10)) : barWindow.s(10)
                    radius: barWindow.s(5)
                    color: isActive ? mocha.mauve
                         : (wsPill.isOccupied && workspacesBox.occupiedBg ? workspacesBox.occupiedTint : mocha.overlay0)
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                // squares: outlined when empty, filled when occupied; the active one grows and turns a quarter.
                Rectangle {
                    visible: wsPill.st === "squares"
                    anchors.centerIn: parent
                    width: wsPill.isActive ? barWindow.s(16) : barWindow.s(11)
                    height: width
                    radius: wsPill.isActive ? barWindow.s(4) : barWindow.s(3)
                    rotation: wsPill.isActive ? 90 : 0
                    color: wsPill.isActive ? mocha.mauve
                         : !wsPill.isOccupied ? "transparent"
                         : (workspacesBox.occupiedBg ? workspacesBox.occupiedTint : mocha.overlay0)
                    border.width: wsPill.isActive || wsPill.isOccupied ? 0 : Math.max(1, barWindow.s(1.5))
                    border.color: wsPill.isHovered ? mocha.text : mocha.overlay0
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 450; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                // pacman: a pellet per workspace, a power pellet where something is open; his square is eaten.
                Rectangle {
                    visible: wsPill.st === "pacman"
                    anchors.centerIn: parent
                    width: wsPill.isOccupied ? barWindow.s(8) : barWindow.s(4)
                    height: width
                    radius: width / 2
                    color: wsPill.isOccupied && workspacesBox.occupiedBg ? workspacesBox.occupiedTint : mocha.overlay0
                    opacity: wsPill.isActive ? 0 : 1
                    // Eaten as he arrives, back only once he has left.
                    Behavior on opacity {
                        id: pelletFade
                        SequentialAnimation {
                            PauseAnimation { duration: pelletFade.targetValue < 0.5 ? 150 : 320 }
                            NumberAnimation { duration: 90 }
                        }
                    }
                }

                // shapes: caelestia's trick — the active workspace draws a random
                // Material shape on every focus change; others stay square/circle.
                ShapeCanvas {
                    visible: wsPill.st === "shapes"
                    anchors.centerIn: parent
                    readonly property bool isActive: wsPill.isActive
                    width: isActive ? barWindow.s(24) : (wsPill.stateLabel === "occupied" ? barWindow.s(16) : barWindow.s(11))
                    height: width
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                    color: isActive ? mocha.mauve
                         : (wsPill.stateLabel === "occupied" && workspacesBox.occupiedBg ? workspacesBox.occupiedTint : mocha.overlay0)

                    property var focusShape: MaterialShapes.getCircle()
                    onIsActiveChanged: if (isActive) rollShape()
                    Component.onCompleted: if (isActive) rollShape()
                    function rollShape() {
                        var pool = [MaterialShapes.getSlanted, MaterialShapes.getOval, MaterialShapes.getPill,
                                    MaterialShapes.getTriangle, MaterialShapes.getArrow, MaterialShapes.getDiamond,
                                    MaterialShapes.getPentagon, MaterialShapes.getGem, MaterialShapes.getVerySunny,
                                    MaterialShapes.getSunny, MaterialShapes.getCookie4Sided, MaterialShapes.getCookie6Sided,
                                    MaterialShapes.getCookie7Sided, MaterialShapes.getCookie9Sided, MaterialShapes.getCookie12Sided,
                                    MaterialShapes.getClover4Leaf, MaterialShapes.getSoftBurst, MaterialShapes.getGhostish];
                        focusShape = pool[Math.floor(Math.random() * pool.length)]();
                    }
                    roundedPolygon: isActive ? focusShape
                                  : (wsPill.stateLabel === "occupied" ? MaterialShapes.getSquare() : MaterialShapes.getCircle())
                    polygonIsNormalized: true
                }
                MouseArea {
                    id: wsPillMouse
                    hoverEnabled: true
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Sounds.playSfx("system/quick_click.wav"); Quickshell.execDetached(["busctl", "--user", "call", "io.quickshell.ws", "/ws", "io.quickshell.ws", "switch", "i", wsName]) }
                }
            }
        }
    }
}
