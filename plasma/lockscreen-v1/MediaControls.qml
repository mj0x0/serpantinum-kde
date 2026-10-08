/*
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-or-later

    Reshaped for the rice: a compact FROSTED PILL sized to sit in the SAME bottom
    row as the weather/keyboard pills (used as a Repeater delegate over
    Mpris.MultiplexerModel, so `model.*` roles are in scope). serpantinum's lock
    has no media widget, so this stays deliberately small and only appears WHILE
    SOMETHING IS PLAYING — otherwise the root is invisible and the Row positioner
    skips it, closing the gap between weather and keyboard. Track+artist share one
    line that auto-scrolls (marquee) when it overflows. Album art is circular.
*/

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.mpris as Mpris
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: pill

    // Same height as the weather/kb pills so the row aligns. Shown whenever a
    // player HAS a track, not only while it is Playing: gating on Playing meant
    // pressing pause hid the pill, and there was then no way to resume from the
    // lock screen at all.
    visible: config.showMediaControls
             && (model.playbackStatus === Mpris.PlaybackStatus.Playing
                 || model.playbackStatus === Mpris.PlaybackStatus.Paused)
    enabled: model.canControl
    height: Kirigami.Units.gridUnit * 2.2
    width: Kirigami.Units.gridUnit * 14   // room for the third transport button

    // Spotify's mpris:artUrl is a remote https:// image and the greeter REFUSES
    // it — "QML Image: Blocked request". Our session already downloads every
    // cover to a local cache, so resolve that path instead. music_info.sh keys it
    // as md5 of the art URL (via `echo`, so the hash includes a trailing
    // newline): $XDG_RUNTIME_DIR/quickshell/music/covers/<hash>_art.jpg
    property string localArt: ""

    Plasma5Support.DataSource {
        id: artSource
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            artSource.disconnectSource(source);
            pill.localArt = ("" + (data["stdout"] || "")).trim();
        }
        function resolve(url) {
            if (!url || ("" + url).indexOf("'") >= 0) { pill.localArt = ""; return; }
            var cmd = "sh -c 'u=\"" + url + "\"; "
                    + "h=$(printf \"%s\\n\" \"$u\" | md5sum | cut -d\" \" -f1); "
                    + "f=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell/music/covers/${h}_art.jpg\"; "
                    + "[ -f \"$f\" ] && printf \"%s\" \"$f\"'";
            disconnectSource(cmd);
            connectSource(cmd);
        }
    }

    Connections {
        target: model
        function onArtUrlChanged() { artSource.resolve(model.artUrl); }
    }
    Component.onCompleted: artSource.resolve(model.artUrl)

    // --- Frosted glass (same recipe as the weather/kb pills) -----------------
    ShaderEffectSource {
        id: grab
        anchors.fill: parent
        sourceItem: wallpaper
        sourceRect: Qt.rect(pill.mapToItem(wallpaper, 0, 0).x,
                            pill.mapToItem(wallpaper, 0, 0).y,
                            pill.width, pill.height)
        visible: false
    }
    FastBlur {
        anchors.fill: parent
        source: grab
        radius: 48
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle { width: pill.width; height: pill.height; radius: height / 2 }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.30)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
    }

    // --- Single-line content: art | marquee | transport ----------------------
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing * 0.5
        anchors.topMargin: Kirigami.Units.smallSpacing * 0.6
        anchors.bottomMargin: Kirigami.Units.smallSpacing * 0.6
        spacing: Kirigami.Units.smallSpacing * 0.75

        // Circular album art (click = play/pause).
        Item {
            Layout.fillHeight: true
            Layout.preferredWidth: height

            Image {
                id: albumArt
                anchors.fill: parent
                visible: false
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                // Local cache only; a remote URL is blocked and would just log.
                source: pill.localArt !== "" ? "file://" + pill.localArt : ""
                sourceSize.height: height * Screen.devicePixelRatio
            }
            Rectangle { id: artMask; anchors.fill: parent; radius: width / 2; visible: false }
            OpacityMask {
                anchors.fill: parent
                source: albumArt
                maskSource: artMask
                visible: albumArt.status === Image.Ready
            }
            // Fallback disc when there's no cover art.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                visible: albumArt.status !== Image.Ready
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.small
                    height: width
                    source: "media-playback-start"
                    isMask: true
                    color: Kirigami.Theme.textColor
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: { pill.fadeGuard(); model.container.PlayPause(); }
            }
        }

        // Marquee: track — artist on one line, loops only when it overflows.
        Item {
            id: marquee
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            readonly property string label: {
                var t = model.track.length > 0
                        ? model.track
                        : i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "No title");
                var a = model.artist || model.identity;
                return a.length > 0 ? (t + "   —   " + a) : t;
            }
            readonly property real gap: Kirigami.Units.gridUnit * 2.5
            readonly property bool overflow: primary.implicitWidth > width

            Row {
                id: strip
                height: marquee.height
                spacing: marquee.gap
                x: 0

                PlasmaComponents3.Label {
                    id: primary
                    height: marquee.height
                    verticalAlignment: Text.AlignVCenter
                    text: marquee.label
                    textFormat: Text.PlainText
                    wrapMode: Text.NoWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize + 1
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                }
                // Second copy trails the first so the loop reads continuous.
                PlasmaComponents3.Label {
                    height: marquee.height
                    verticalAlignment: Text.AlignVCenter
                    visible: marquee.overflow
                    text: marquee.label
                    textFormat: Text.PlainText
                    wrapMode: Text.NoWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize + 1
                    font.weight: Font.DemiBold
                    color: Kirigami.Theme.textColor
                }
            }

            NumberAnimation {
                id: scrollAnim
                target: strip
                property: "x"
                from: 0
                to: -(primary.implicitWidth + marquee.gap)
                duration: Math.max(4000, (primary.implicitWidth + marquee.gap) * 18)
                loops: Animation.Infinite
                running: marquee.overflow && pill.visible
            }
            onOverflowChanged: if (!overflow) strip.x = 0
            onLabelChanged: { scrollAnim.stop(); strip.x = 0; if (overflow && pill.visible) scrollAnim.start(); }
        }

        // --- Compact transport (previous + play/pause + next) ----------------
        PlasmaComponents3.ToolButton {
            Layout.fillHeight: true
            Layout.preferredWidth: height
            flat: true
            focusPolicy: Qt.TabFocus
            visible: model.canGoPrevious
            icon.name: LayoutMirroring.enabled ? "media-skip-forward" : "media-skip-backward"
            onClicked: { pill.fadeGuard(); model.container.Previous(); }
        }
        PlasmaComponents3.ToolButton {
            Layout.fillHeight: true
            Layout.preferredWidth: height
            flat: true
            focusPolicy: Qt.TabFocus
            icon.name: model.playbackStatus === Mpris.PlaybackStatus.Playing ? "media-playback-pause" : "media-playback-start"
            onClicked: { pill.fadeGuard(); model.container.PlayPause(); }
        }
        PlasmaComponents3.ToolButton {
            Layout.fillHeight: true
            Layout.preferredWidth: height
            flat: true
            focusPolicy: Qt.TabFocus
            visible: model.canGoNext
            icon.name: LayoutMirroring.enabled ? "media-skip-backward" : "media-skip-forward"
            onClicked: { pill.fadeGuard(); model.container.Next(); }
        }
    }

    // A transport tap shouldn't let the idle fade-out fire mid-interaction.
    function fadeGuard() {
        if (typeof fadeoutTimer !== "undefined")
            fadeoutTimer.running = false;
    }
}
