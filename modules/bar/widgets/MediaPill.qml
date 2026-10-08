// Now-playing pill: art, title/time, prev/play/next. `mini` is v2's compact player (always on side bars).
import "../../../services/audio"
import "../../miniplayer"
import "../../music"
import "../../../services/layout"
import "../../../services/settings"
import "../../../services/theme"
import QtQuick
import QtQuick.Effects
import Quickshell

Rectangle {
    id: mediaBox
    required property var barWindow
    required property var mocha
    color: grouped ? "transparent" : barWindow.pillBg
    radius: barWindow.pillRadius; border.width: grouped ? 0 : 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05 * barWindow.pillBorderAlpha)
    property bool vertical: false
    property bool shown: true
    readonly property bool mini: vertical || ShellSettings.value("bar.media.style", "full") === "mini"
    readonly property real miniWidth: miniLayout.implicitWidth + barWindow.s(16)

    // Squeeze support: the title/time column has a FIXED width, so dropping it
    // frees a known amount and the bar's fit maths stays loop-free.
    property bool compact: false
    readonly property real textColWidth: barWindow.width < 1920 ? barWindow.s(120) : barWindow.s(180)
    readonly property real compactSaving: shown && barWindow.isMediaActive && !vertical && !mini ? textColWidth + barWindow.s(10) : 0
    // Built from parts that never hide, so it cannot depend on `compact`
    // (that dependency is a binding loop through the bar's fit maths).
    readonly property real naturalWidth: !(shown && barWindow.isMediaActive) ? 0
        : mini ? miniWidth
        : barWindow.s(32) + barWindow.s(10) + textColWidth + innerMediaLayout.spacing
          + controlsRow.implicitWidth + barWindow.s(24)
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0
    readonly property bool hasContent: shown && placed && barWindow.isMediaActive
    // Non-animated size for the placement engine; `width` animates toward it.
    readonly property real targetWidth: (hasContent && !vertical) ? naturalWidth - (compact ? compactSaving : 0) : 0
    readonly property real targetHeight: (hasContent && vertical) ? miniLayout.implicitHeight + barWindow.s(16) : 0
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
    clip: true

    width: vertical ? parent.width : (hasContent ? (mini ? miniWidth : innerMediaLayout.implicitWidth + barWindow.s(24)) : 0)
    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }
    x: vertical ? 0 : targetX
    Behavior on x { enabled: barWindow.startupCascadeFinished && !mediaBox.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && mediaBox.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    visible: shown && placed && ((vertical ? height : width) > 0 || opacity > 0)
    opacity: barWindow.isMediaActive ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 400 } }

    function control(cmd) {
        Quickshell.execDetached(["bash", barWindow.shellPath + "/helpers/player_control.sh", cmd, "", "", barWindow.musicData.playerName || ""]);
        barWindow.refreshMusic();
    }
    function popoutAnchor() { return mediaBox.mapToItem(null, mediaBox.width / 2, mediaBox.height / 2); }

    // Declared first so it sits BEHIND the controls; only leftover box area hits it.
    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!mediaBox.mini) { MusicState.toggle(); return; }
            var p = mediaBox.popoutAnchor();
            MiniPlayerState.toggle(p.x, p.y, barWindow.screen);
        }
    }

    // The mini player's popout opens on hover; a HoverHandler isn't stolen by the buttons' MouseAreas.
    HoverHandler {
        enabled: mediaBox.mini && mediaBox.hasContent
        onHoveredChanged: {
            if (hovered) { var p = mediaBox.popoutAnchor(); MiniPlayerState.enter(p.x, p.y, barWindow.screen); }
            else MiniPlayerState.leave();
        }
    }
    onHasContentChanged: if (!hasContent) MiniPlayerState.leave()

    component MiniBtn : Rectangle {
        id: mb
        property string glyph: ""
        property real size: barWindow.s(26)
        property real glyphSize: barWindow.s(13)
        property bool primary: false
        signal clicked()
        width: size
        height: size
        radius: Radius.inner(barWindow.s(8), size / 2)
        color: mbMa.containsMouse ? mocha.surface1 : mocha.surface0
        scale: mbMa.pressed ? 0.92 : (mbMa.containsMouse ? 1.06 : 1.0)
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
        Text {
            anchors.centerIn: parent
            text: mb.glyph
            font.family: Fonts.icons
            font.pixelSize: mb.glyphSize
            color: mbMa.containsMouse ? (mb.primary ? mocha.green : mocha.text) : (mb.primary ? mocha.text : mocha.subtext0)
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        MouseArea { id: mbMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mb.clicked() }
    }

    // v2's mini player: rounded art (ringed while playing) and boxed prev/play/next; a column on side bars.
    Grid {
        id: miniLayout
        visible: mediaBox.mini
        anchors.centerIn: parent
        columns: mediaBox.vertical ? 1 : 4
        rowSpacing: barWindow.s(4)
        columnSpacing: barWindow.s(4)
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        onColumnsChanged: Qt.callLater(miniLayout.forceLayout)

        Rectangle {
            id: miniArt
            width: barWindow.s(28)
            height: width
            radius: Radius.inner(barWindow.s(8), width / 2)
            color: mocha.surface1
            border.width: 1
            border.color: barWindow.musicData.status === "Playing" ? mocha.mauve : mocha.surface1
            Behavior on border.color { ColorAnimation { duration: 250 } }

            Text {
                anchors.centerIn: parent
                visible: miniArtImg.status !== Image.Ready
                text: "\u{f075a}"   // md-music
                font.family: Fonts.icons
                font.pixelSize: barWindow.s(13)
                color: mocha.subtext0
            }
            Image {
                id: miniArtImg
                anchors.fill: parent
                anchors.margins: 1
                source: barWindow.displayArtUrl || ""
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            Rectangle {
                id: miniArtMask
                anchors.fill: miniArtImg
                radius: Math.max(0, miniArt.radius - 1)
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: miniArtImg
                source: miniArtImg
                maskEnabled: true
                maskSource: miniArtMask
                visible: miniArtImg.status === Image.Ready
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { MiniPlayerState.hide(); MusicState.toggle(); } }
        }
        MiniBtn { glyph: "󰒮"; onClicked: { Sounds.playSfx("system/quick_click.wav"); mediaBox.control("prev"); } }
        MiniBtn {
            size: barWindow.s(28)
            glyphSize: barWindow.s(15)
            primary: true
            glyph: barWindow.musicData.status === "Playing" ? "󰏤" : "󰐊"
            onClicked: { Sounds.playSfx("system/quick_click.wav"); mediaBox.control("play-pause"); }
        }
        MiniBtn { glyph: "󰒭"; onClicked: { Sounds.playSfx("system/quick_click.wav"); mediaBox.control("next"); } }
    }

    Item {
        id: mediaLayoutContainer
        visible: !mediaBox.mini
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: barWindow.s(12)
        height: parent.height
        width: innerMediaLayout.implicitWidth

        opacity: barWindow.isMediaActive ? 1.0 : 0.0
        transform: Translate { 
            x: barWindow.isMediaActive ? 0 : barWindow.s(-20) 
            Behavior on x { NumberAnimation { duration: 700; easing.type: Easing.OutQuint } }
        }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        Row {
            id: innerMediaLayout
            anchors.verticalCenter: parent.verticalCenter
            spacing: barWindow.width < 1920 ? barWindow.s(8) : barWindow.s(16)

            MouseArea {
                id: mediaInfoMouse
                width: infoLayout.width
                height: innerMediaLayout.height
                hoverEnabled: true
                onClicked: { Sounds.playSfx("system/quick_click.wav"); MusicState.toggle(); }   // same instance as Music.qml host

                Row {
                    id: infoLayout
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: barWindow.s(10)

                    scale: mediaInfoMouse.containsMouse ? 1.02 : 1.0
                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                    Rectangle {
                        width: barWindow.s(32); height: barWindow.s(32); radius: Radius.inset(barWindow.s(8), barWindow.s(2)); color: mocha.surface1
                        border.width: barWindow.musicData.status === "Playing" ? 1 : 0
                        border.color: mocha.mauve
                        clip: true
                        Image { 
                            anchors.fill: parent; 
                            source: barWindow.displayArtUrl || ""; 
                            fillMode: Image.PreserveAspectCrop 
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.2)
                        }
                    }
                    Column {
                        spacing: -2
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !mediaBox.compact
                        property real maxColWidth: mediaBox.textColWidth
                        width: maxColWidth 

                        Text { 
                            text: barWindow.displayTitle; 
                            font.family: Fonts.ui; 
                            font.weight: Font.Black; 
                            font.pixelSize: barWindow.s(13); 
                            color: mocha.text;
                            width: parent.width
                            elide: Text.ElideRight; 
                        }
                        Text { 
                            text: barWindow.displayTime; 
                            font.family: Fonts.ui; 
                            font.weight: Font.Black; 
                            font.pixelSize: barWindow.s(10); 
                            color: mocha.subtext0;
                            width: parent.width
                            elide: Text.ElideRight;
                        }
                    }
                }
            }

            Row {
                id: controlsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: barWindow.width < 1920 ? barWindow.s(4) : barWindow.s(8)
                Item { 
                    width: barWindow.s(24); height: barWindow.s(24); 
                    anchors.verticalCenter: parent.verticalCenter
                    Text { 
                        anchors.centerIn: parent; text: "󰒮"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26);
                        color: prevMouse.containsMouse ? mocha.green : mocha.text;   // white at rest, like play/pause
                        Behavior on color { ColorAnimation { duration: 150 } }
                        scale: prevMouse.containsMouse ? 1.1 : 1.0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    }
                    MouseArea { id: prevMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Sounds.playSfx("system/quick_click.wav"); Quickshell.execDetached(["bash", barWindow.shellPath + "/helpers/player_control.sh", "prev", "", "", barWindow.musicData.playerName || ""]); barWindow.refreshMusic(); } }
                }
                Item { 
                    width: barWindow.s(28); height: barWindow.s(28); 
                    anchors.verticalCenter: parent.verticalCenter
                    Text { 
                        anchors.centerIn: parent; text: barWindow.musicData.status === "Playing" ? "󰏤" : "󰐊"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(30); 
                        color: playMouse.containsMouse ? mocha.green : mocha.text; 
                        Behavior on color { ColorAnimation { duration: 150 } }
                        scale: playMouse.containsMouse ? 1.15 : 1.0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    }
                    MouseArea { id: playMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Sounds.playSfx("system/quick_click.wav"); Quickshell.execDetached(["bash", barWindow.shellPath + "/helpers/player_control.sh", "play-pause", "", "", barWindow.musicData.playerName || ""]); barWindow.refreshMusic(); } }
                }
                Item { 
                    width: barWindow.s(24); height: barWindow.s(24); 
                    anchors.verticalCenter: parent.verticalCenter
                    Text { 
                        anchors.centerIn: parent; text: "󰒭"; font.family: "Iosevka Nerd Font"; font.pixelSize: barWindow.s(26);
                        color: nextMouse.containsMouse ? mocha.green : mocha.text;   // white at rest, like play/pause
                        Behavior on color { ColorAnimation { duration: 150 } }
                        scale: nextMouse.containsMouse ? 1.1 : 1.0
                        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                    }
                    MouseArea { id: nextMouse; hoverEnabled: true; anchors.fill: parent; onClicked: { Sounds.playSfx("system/quick_click.wav"); Quickshell.execDetached(["bash", barWindow.shellPath + "/helpers/player_control.sh", "next", "", "", barWindow.musicData.playerName || ""]); barWindow.refreshMusic(); } }
                }
            }
        }
    }
}
