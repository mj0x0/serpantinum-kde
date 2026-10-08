// serpantinum v2's side music popout (popouts/SideMusicPopout.qml): title, artist, player switch and
// a seek bar, beside the bar's mini player. Native MPRIS; grows out of a solid bar with fillets.
import "../../services/audio"
import "../music"
import "../../services/bar"
import "../../services/layout"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris

PanelWindow {
    id: pop

    screen: MiniPlayerState.screen
    readonly property bool isOpen: MiniPlayerState.open
    visible: isOpen || card.prog > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayershell.Top
    WlrLayershell.namespace: "quickshell-miniplayer"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    mask: Region { item: card }

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }
    MatugenColors { id: c }

    // --- Player ---------------------------------------------------------------
    readonly property var players: Mpris.players ? Mpris.players.values : []
    property var manualPlayer: null
    readonly property var player: {
        let list = players;
        if (manualPlayer && list.indexOf(manualPlayer) !== -1) return manualPlayer;
        let playing = list.find(p => p.isPlaying);
        if (playing) return playing;
        let controllable = list.find(p => p.canControl);
        return controllable ? controllable : (list.length > 0 ? list[0] : null);
    }
    readonly property bool active: player !== null && !!player.trackTitle
    function nextPlayer() {
        let list = players;
        if (list.length < 2) return;
        manualPlayer = list[(list.indexOf(player) + 1) % list.length];
    }

    // MPRIS only reports position on request, so poll it while shown.
    property real livePosition: 0
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: pop.visible && pop.player !== null
        onTriggered: {
            if (!pop.player) return;
            pop.player.positionChanged();
            if (!seek.dragging && !seekHold.running) pop.livePosition = pop.player.position;
        }
    }
    Timer { id: seekHold; interval: 800 }

    function formatTime(sec) {
        sec = Math.max(0, Math.floor(sec || 0));
        let m = Math.floor(sec / 60), r = sec % 60;
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r;
    }

    // --- Geometry -------------------------------------------------------------
    readonly property string edge: BarState.position
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property bool flush: BarState.solid && !BarState.hidden
    readonly property real cardW: s(240)
    readonly property real cardH: s(140)
    readonly property real cornerR: Radius.outer(s(14))

    component Fillet : Shape {
        id: fil
        property string vertexX: "left"
        property string vertexY: "top"
        readonly property real r: card.r
        readonly property real vx: vertexX === "left" ? 0 : r
        readonly property real ox: vertexX === "left" ? r : 0
        readonly property real vy: vertexY === "top" ? 0 : r
        readonly property real oy: vertexY === "top" ? r : 0
        width: r
        height: r
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: c.base
            strokeColor: "transparent"
            startX: fil.vx
            startY: fil.vy
            PathLine { x: fil.ox; y: fil.vy }
            PathArc {
                x: fil.vx; y: fil.oy
                radiusX: fil.r; radiusY: fil.r
                direction: ((fil.vertexX === "left") !== (fil.vertexY === "top")) ? PathArc.Clockwise : PathArc.Counterclockwise
            }
            PathLine { x: fil.vx; y: fil.vy }
        }
    }

    Item {
        id: card

        property real prog: pop.isOpen ? 1 : 0
        Behavior on prog {
            id: progBehavior
            NumberAnimation { duration: progBehavior.targetValue > 0.5 ? 280 : 220; easing.type: Easing.OutCubic }
        }

        readonly property real bound: pop.s(8)
        // A solid bar: flush against its slab. Modular: clear of the bar like the popups, sliding in.
        readonly property real slide: pop.flush ? 0 : pop.s(16) * (1 - prog)
        readonly property real r: pop.flush ? Math.max(0, Math.min(pop.cornerR, (pop.vertical ? width : height) * 0.5)) : 0

        width: pop.flush && pop.vertical ? pop.cardW * prog : pop.cardW
        height: pop.flush && !pop.vertical ? pop.cardH * prog : pop.cardH
        x: pop.edge === "left" ? (pop.flush ? BarState.slabThickness : BarState.leftGap) - slide
         : pop.edge === "right" ? pop.width - width - (pop.flush ? BarState.slabThickness : BarState.rightGap) + slide
         : Math.max(bound, Math.min(pop.width - width - bound, MiniPlayerState.anchorX - width / 2))
        y: pop.edge === "top" ? (pop.flush ? BarState.slabThickness : BarState.topGap) - slide
         : pop.edge === "bottom" ? pop.height - height - (pop.flush ? BarState.slabThickness : BarState.bottomGap) + slide
         : Math.max(bound, Math.min(pop.height - height - bound, MiniPlayerState.anchorY - height / 2))

        opacity: pop.flush ? Math.min(1, prog * 3) : prog
        scale: pop.flush ? 1 : 0.92 + 0.08 * prog
        transformOrigin: pop.edge === "left" ? Item.Left : pop.edge === "right" ? Item.Right
                       : pop.edge === "bottom" ? Item.Bottom : Item.Top

        HoverHandler {
            onHoveredChanged: {
                MiniPlayerState.cardHovered = hovered;
                if (hovered) MiniPlayerState.cancelHide();
                else MiniPlayerState.requestHide();
            }
        }

        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "top";    x: -card.r;                  y: 0;                        vertexX: "right"; vertexY: "top" }
        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "top";    x: card.width;               y: 0;                        vertexX: "left";  vertexY: "top" }
        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "bottom"; x: -card.r;                  y: card.height - card.r;     vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "bottom"; x: card.width;               y: card.height - card.r;     vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "left";   x: 0;                        y: -card.r;                  vertexX: "left";  vertexY: "bottom" }
        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "left";   x: 0;                        y: card.height;              vertexX: "left";  vertexY: "top" }
        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "right";  x: card.width - card.r;      y: -card.r;                  vertexX: "right"; vertexY: "bottom" }
        Fillet { visible: pop.flush && card.r > 0.5 && pop.edge === "right";  x: card.width - card.r;      y: card.height;              vertexX: "right"; vertexY: "top" }

        Rectangle {
            id: bg
            anchors.fill: parent
            color: c.base
            radius: pop.cornerR
            topLeftRadius:     pop.flush && (pop.edge === "top"    || pop.edge === "left")  ? 0 : pop.cornerR
            topRightRadius:    pop.flush && (pop.edge === "top"    || pop.edge === "right") ? 0 : pop.cornerR
            bottomLeftRadius:  pop.flush && (pop.edge === "bottom" || pop.edge === "left")  ? 0 : pop.cornerR
            bottomRightRadius: pop.flush && (pop.edge === "bottom" || pop.edge === "right") ? 0 : pop.cornerR
            border.width: pop.flush ? 0 : 1
            border.color: Qt.rgba(c.surface2.r, c.surface2.g, c.surface2.b, 0.9)
            clip: true

            ColumnLayout {
                x: pop.s(12)
                y: pop.s(8)
                width: pop.cardW - pop.s(24)
                height: pop.cardH - pop.s(16)
                spacing: pop.s(4)

                // Title (scrolls while hovered when it doesn't fit) and artist; opens the full Music popup.
                MouseArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleCol.implicitHeight
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { Sounds.playSfx("system/quick_click.wav"); MiniPlayerState.hide(); MusicState.toggle(); }

                    ColumnLayout {
                        id: titleCol
                        anchors.fill: parent
                        spacing: pop.s(2)

                        Item {
                            id: titleClip
                            Layout.fillWidth: true
                            Layout.preferredHeight: pop.s(18)
                            clip: true
                            readonly property real gap: pop.s(40)
                            readonly property bool overflow: titleText.implicitWidth > width

                            Row {
                                id: titleStrip
                                spacing: titleClip.gap
                                Text {
                                    id: titleText
                                    text: pop.active ? pop.player.trackTitle : "Nothing playing"
                                    font.family: Fonts.ui
                                    font.weight: Font.Black
                                    font.pixelSize: pop.s(13)
                                    color: c.text
                                    onTextChanged: titleStrip.x = 0
                                }
                                Text {
                                    visible: titleClip.overflow
                                    text: titleText.text
                                    font: titleText.font
                                    color: c.text
                                }
                            }
                            SequentialAnimation {
                                loops: Animation.Infinite
                                running: titleClip.overflow && MiniPlayerState.cardHovered
                                onRunningChanged: if (!running) titleStrip.x = 0
                                PauseAnimation { duration: 2500 }
                                NumberAnimation {
                                    target: titleStrip; property: "x"
                                    from: 0; to: -(titleText.implicitWidth + titleClip.gap)
                                    duration: (titleText.implicitWidth + titleClip.gap) * 25
                                }
                                PropertyAction { target: titleStrip; property: "x"; value: 0 }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: pop.player ? (pop.player.trackArtist || pop.player.identity || "") : ""
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: pop.s(11)
                            color: c.subtext0
                            elide: Text.ElideRight
                        }
                    }
                }

                // Source pill; with several players it cycles through them.
                Rectangle {
                    Layout.preferredHeight: pop.s(20)
                    Layout.preferredWidth: Math.min(parent.width, srcRow.implicitWidth + pop.s(16))
                    radius: Radius.inner(pop.s(6), height / 2)
                    color: srcMa.containsMouse && pop.players.length > 1 ? c.surface1 : c.surface0
                    Behavior on color { ColorAnimation { duration: 150 } }
                    clip: true

                    Row {
                        id: srcRow
                        anchors.centerIn: parent
                        spacing: pop.s(6)
                        Text {
                            text: "via " + (pop.player ? (pop.player.identity || pop.player.desktopEntry || "Media") : "nothing")
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: pop.s(10)
                            color: c.subtext0
                        }
                        Text {
                            visible: pop.players.length > 1
                            text: (pop.players.indexOf(pop.player) + 1) + "/" + pop.players.length
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: pop.s(10)
                            color: c.blue
                        }
                    }
                    MouseArea {
                        id: srcMa
                        anchors.fill: parent
                        enabled: pop.players.length > 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Sounds.playSfx("system/quick_click.wav"); pop.nextPlayer(); }
                    }
                }

                Item { Layout.fillHeight: true }

                // Seek bar.
                Item {
                    id: seek
                    Layout.fillWidth: true
                    Layout.preferredHeight: pop.s(12)
                    readonly property real len: pop.player ? pop.player.length : 0
                    readonly property bool canSeek: pop.player !== null && pop.player.canSeek && len > 0
                    readonly property bool dragging: seekMa.pressed
                    property real dragValue: 0
                    readonly property real frac: len > 0 ? Math.max(0, Math.min(1, (dragging ? dragValue : pop.livePosition) / len)) : 0

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: pop.s(4)
                        radius: height / 2
                        color: c.surface1
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * seek.frac
                        height: pop.s(4)
                        radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: c.blue }
                            GradientStop { position: 1.0; color: Qt.lighter(c.blue, 1.2) }
                        }
                    }
                    Rectangle {
                        visible: seek.canSeek
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * seek.frac - width / 2
                        width: pop.s(10)
                        height: width
                        radius: width / 2
                        color: seekMa.pressed || seekMa.containsMouse ? Qt.lighter(c.blue, 1.3) : c.blue
                        scale: seekMa.pressed ? 1.2 : 1.0
                        Behavior on scale { NumberAnimation { duration: 150 } }
                    }
                    MouseArea {
                        id: seekMa
                        anchors.fill: parent
                        anchors.topMargin: -pop.s(4)
                        anchors.bottomMargin: -pop.s(4)
                        enabled: seek.canSeek
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        function valueAt(mx) { return Math.max(0, Math.min(1, mx / width)) * seek.len; }
                        onPressed: mouse => { MiniPlayerState.holding = true; seek.dragValue = valueAt(mouse.x); }
                        onPositionChanged: mouse => { if (pressed) seek.dragValue = valueAt(mouse.x); }
                        onReleased: {
                            pop.player.position = seek.dragValue;
                            pop.livePosition = seek.dragValue;
                            seekHold.restart();
                            MiniPlayerState.holding = false;
                            MiniPlayerState.requestHide();
                        }
                        onCanceled: { MiniPlayerState.holding = false; MiniPlayerState.requestHide(); }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: pop.formatTime(seek.dragging ? seek.dragValue : pop.livePosition)
                        font.family: Fonts.ui
                        font.weight: Font.Bold
                        font.pixelSize: pop.s(9.5)
                        color: c.subtext0
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: pop.formatTime(seek.len)
                        font.family: Fonts.ui
                        font.weight: Font.Bold
                        font.pixelSize: pop.s(9.5)
                        color: c.subtext0
                    }
                }
            }
        }
    }
}
