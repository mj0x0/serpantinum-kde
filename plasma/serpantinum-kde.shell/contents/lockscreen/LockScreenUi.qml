/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// serpantinum v2's lock screen (Lock.qml) rebuilt on KDE's greeter: an idle clock, then a
// three-column card on the first keypress. Login stays KDE's `authenticator`.

import "rpoly"
import "rpoly/material-shapes.js" as MaterialShapes
import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker
import org.kde.plasma.private.sessions
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: lockScreenUi

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    // --- Palette: v2's Catppuccin roles read off the matugen-driven KDE scheme ---------
    // Zero-sized, not invisible: Plasma's platform theme never syncs colours for hidden items.
    Item { id: palWindow; width: 0; height: 0; Kirigami.Theme.inherit: false; Kirigami.Theme.colorSet: Kirigami.Theme.Window }
    Item { id: palButton; width: 0; height: 0; Kirigami.Theme.inherit: false; Kirigami.Theme.colorSet: Kirigami.Theme.Button }
    Item { id: palComp;   width: 0; height: 0; Kirigami.Theme.inherit: false; Kirigami.Theme.colorSet: Kirigami.Theme.Complementary }

    readonly property color base:     palComp.Kirigami.Theme.backgroundColor
    readonly property color surface0: palWindow.Kirigami.Theme.backgroundColor
    readonly property color surface1: palButton.Kirigami.Theme.backgroundColor
    readonly property color surface2: Qt.lighter(surface1, 1.12)
    readonly property color crust:    Qt.darker(base, 1.18)
    readonly property color text:     palWindow.Kirigami.Theme.textColor
    readonly property color subtext0: palWindow.Kirigami.Theme.disabledTextColor
    readonly property color subtext1: subtext0
    readonly property color overlay0: Qt.tint(surface1, Qt.alpha(text, 0.30))
    readonly property color overlay1: Qt.tint(surface1, Qt.alpha(text, 0.45))
    readonly property color overlay2: Qt.tint(surface1, Qt.alpha(text, 0.60))
    readonly property color mauve:    palWindow.Kirigami.Theme.highlightColor
    readonly property color blue:     mauve
    readonly property color sapphire: Qt.lighter(mauve, 1.25)
    readonly property color pink:     Qt.lighter(mauve, 1.35)
    readonly property color red:      palWindow.Kirigami.Theme.negativeTextColor
    readonly property color peach:    palWindow.Kirigami.Theme.neutralTextColor
    readonly property color yellow:   Qt.lighter(peach, 1.2)
    readonly property color green:    palWindow.Kirigami.Theme.linkColor
    readonly property color teal:     green

    // --- Knobs from the rice's settings.json, read once -----------------------------
    property var settings: ({})
    Plasma5Support.DataSource {
        id: settingsSource
        engine: "executable"
        connectedSources: []
        onNewData: (src, d) => {
            settingsSource.disconnectSource(src);
            try { lockScreenUi.settings = JSON.parse(("" + (d["stdout"] || "")).trim() || "{}"); } catch (e) {}
        }
        Component.onCompleted: connectSource("sh -c 'cat \"$HOME/.config/quickshell/settings.json\" 2>/dev/null'")
    }
    readonly property var ui: settings && settings.ui ? settings.ui : ({})
    readonly property bool radiusActive: typeof ui.radius === "number" && isFinite(ui.radius)
    // v2's ThemeBackend.borderRadius; r() is the rice's cap for v2's literal radii.
    readonly property real radius: radiusActive ? Math.round(Math.max(0, Math.min(64, ui.radius))) : 8
    function r(v) { return radiusActive ? Math.min(radius, s(v)) : s(v) }
    readonly property real cardRadius: Math.min(48, radius * 1.5)
    // v2 was drawn on 1080p: keep its proportions on any screen, ui.scale on top.
    readonly property real uiScale: (typeof ui.scale === "number" && isFinite(ui.scale) && ui.scale > 0) ? ui.scale : 1.0
    readonly property real sf: (width > 0 && height > 0 ? Math.min(width / 1920, height / 1080) : 1.0) * uiScale
    function s(v) { return Math.round(v * sf) }
    readonly property string uiFont: (ui.font && ("" + ui.font).trim() !== "") ? "" + ui.font : "JetBrainsMono Nerd Font"
    readonly property string iconFont: "Iosevka Nerd Font"
    readonly property int weekStart: {
        var v = settings && settings.calendar ? settings.calendar.weekStart : undefined;
        if (typeof v === "number") return ((v % 7) + 7) % 7;
        var t = ("" + (v || "locale")).toLowerCase();
        if (t === "sunday") return 0;
        if (t === "monday") return 1;
        var q = Qt.locale().firstDayOfWeek;
        return q === 7 ? 0 : q;
    }
    readonly property bool astro: !!(settings && settings.calendar && settings.calendar.astro === true)
    readonly property string timeFormat: (settings && settings.bar && settings.bar.time && settings.bar.time.format)
                                         ? "" + settings.bar.time.format : Qt.locale().timeFormat(Locale.ShortFormat)
    readonly property bool is12Hour: timeFormat.indexOf("h") !== -1 || timeFormat.toLowerCase().indexOf("ap") !== -1

    // --- Time --------------------------------------------------------------------------
    property date now: new Date()
    property date today: new Date()
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date();
            lockScreenUi.now = d;
            if (d.getDate() !== lockScreenUi.today.getDate() || d.getMonth() !== lockScreenUi.today.getMonth())
                lockScreenUi.today = d;
        }
    }

    // --- State ---------------------------------------------------------------------------
    property bool inputActive: false
    property bool powerMenuOpen: false
    property bool isPlayingIntro: true
    property bool isUnlocking: false
    property bool wingsEverNeeded: false
    property bool failed: false
    readonly property bool busy: authenticator.busy
    readonly property string statusText: failed ? "Access denied"
                                       : (busy ? "Authenticating..."
                                       : (passwordBox.text.length > 0 ? "Enter PIN" : "Locked"))

    property real centerReveal: 0.0
    property real wingsReveal: 0.0
    property real contentReveal: 0.0
    property real panelReveal: 0.0
    property real mainOpacity: 1.0
    property real foldScaleX: 1.0
    property real foldScaleY: 1.0

    onWingsRevealChanged: if (wingsReveal > 0 && !wingsEverNeeded) wingsEverNeeded = true

    onInputActiveChanged: {
        if (isUnlocking) return;
        if (inputActive) {
            closeDashboardAnim.stop();
            openDashboardAnim.restart();
            Window.window.requestActivate();
            passwordBox.forceActiveFocus();
            if (passwordBox.text.length === 0) idleTimer.restart();
        } else {
            idleTimer.stop();
            openDashboardAnim.stop();
            closeDashboardAnim.restart();
            powerMenuOpen = false;
            root.clearPassword();
        }
        authenticator.startAuthenticating();
    }

    SequentialAnimation {
        id: openDashboardAnim
        NumberAnimation { target: lockScreenUi; property: "centerReveal"; to: 1.0; duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        NumberAnimation { target: lockScreenUi; property: "wingsReveal"; to: 1.0; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.12 }
    }
    ParallelAnimation {
        id: closeDashboardAnim
        NumberAnimation { target: lockScreenUi; property: "wingsReveal"; to: 0.0; duration: 110; easing.type: Easing.InQuad }
        NumberAnimation { target: lockScreenUi; property: "centerReveal"; to: 0.0; duration: 100; easing.type: Easing.InQuad }
    }

    SequentialAnimation {
        id: introSequence
        ParallelAnimation {
            NumberAnimation { target: lockScreenUi; property: "panelReveal"; from: 0.0; to: 1.0; duration: 750; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                NumberAnimation { target: lockScreenUi; property: "contentReveal"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        PropertyAction { target: lockScreenUi; property: "isPlayingIntro"; value: false }
        ScriptAction { script: passwordBox.forceActiveFocus() }
    }

    // v2's fold-out, then the greeter exits and the session is back.
    SequentialAnimation {
        id: unlockSequence
        ScriptAction { script: lockScreenUi.powerMenuOpen = false }
        NumberAnimation { target: lockScreenUi; property: "wingsReveal"; to: 0.0; duration: 130; easing.type: Easing.InQuad }
        ParallelAnimation {
            NumberAnimation { target: lockScreenUi; property: "foldScaleX"; to: 0.0; duration: 220; easing.type: Easing.InBack; easing.overshoot: 1.3 }
            NumberAnimation { target: lockScreenUi; property: "foldScaleY"; to: 0.0; duration: 220; easing.type: Easing.InBack; easing.overshoot: 1.3 }
            NumberAnimation { target: lockScreenUi; property: "centerReveal"; to: 0.0; duration: 200; easing.type: Easing.InQuad }
            NumberAnimation { target: lockScreenUi; property: "contentReveal"; to: 0.0; duration: 220; easing.type: Easing.InQuad }
            NumberAnimation { target: lockScreenUi; property: "panelReveal"; to: 0.0; duration: 250; easing.type: Easing.InOutCubic }
            NumberAnimation { target: lockScreenUi; property: "mainOpacity"; to: 0.0; duration: 250; easing.type: Easing.InQuad }
        }
        ScriptAction { script: Qt.quit() }
    }
    // Never let the animation stand between the user and their session.
    Timer { id: quitGuard; interval: 700; onTriggered: Qt.quit() }

    function startUnlock() {
        if (isUnlocking) return;
        isUnlocking = true;
        openDashboardAnim.stop();
        closeDashboardAnim.stop();
        unlockSequence.restart();
        quitGuard.start();
    }

    Component.onCompleted: introSequence.start()

    // --- KDE's login plumbing, unchanged in substance -------------------------------------
    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
    }

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            lockScreenUi.handleMessage(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed"));
            lockScreenUi.failed = true;
            passwordPill.shake();
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
        }
        function onSucceeded() {
            lockScreenUi.failed = false;
            if (authenticator.hadPrompt) {
                lockScreenUi.startUnlock();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"), { userListModel: users }, StackView.Immediate);
                mainStack.forceActiveFocus();
            }
        }
        function onInfoMessageChanged() { lockScreenUi.handleMessage(authenticator.infoMessage); }
        function onErrorMessageChanged() { lockScreenUi.handleMessage(authenticator.errorMessage); }
        function onPromptChanged(msg) { lockScreenUi.handleMessage(authenticator.prompt); }
        function onPromptForSecretChanged(msg) {
            passwordPill.revealed = false;
            passwordBox.forceActiveFocus();
        }
    }

    SessionManagement { id: sessionManagement }
    Connections {
        target: sessionManagement
        function onAboutToSuspend() { root.clearPassword(); }
    }

    KeyboardIndicator.KeyState { id: capsLockState; key: Qt.Key_CapsLock }
    PW.KeyboardLayoutSwitcher { id: kbSwitcher; acceptedButtons: Qt.NoButton }

    Timer { id: notificationRemoveTimer; interval: 3000; onTriggered: root.notification = "" }
    Timer {
        id: graceLockTimer
        interval: 3000
        onTriggered: {
            root.clearPassword();
            authenticator.startAuthenticating();
            lockScreenUi.failed = false;
        }
    }
    // Fifteen idle seconds with an empty field close the card (v2's idleTimer).
    Timer { id: idleTimer; interval: 15000; onTriggered: lockScreenUi.inputActive = false }

    ListModel {
        id: users
        Component.onCompleted: {
            users.append({
                name: kscreenlocker_userName,
                realName: kscreenlocker_userName,
                icon: kscreenlocker_userImage !== ""
                      ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/")
                      : "",
            })
        }
    }

    MouseArea {
        id: lockScreenRoot
        anchors.fill: parent
        hoverEnabled: true
        drag.filterChildren: true
        property bool seenPositionChange: false
        property bool pointerActive: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || passwordBox.text.length > 0)
        cursorShape: (lockScreenUi.inputActive || pointerActive) ? Qt.ArrowCursor : Qt.BlankCursor

        function pressedInside(item, mx, my) {
            if (!item || !item.visible) return false;
            var p = lockScreenRoot.mapToItem(item, mx, my);
            return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height;
        }

        onPressed: mouse => {
            pointerActive = true;
            if (lockScreenUi.isPlayingIntro || lockScreenUi.isUnlocking) return;
            if (lockScreenUi.powerMenuOpen && !pressedInside(powerContainer, mouse.x, mouse.y) && !pressedInside(powerToggle, mouse.x, mouse.y))
                lockScreenUi.powerMenuOpen = false;
            if (!lockScreenUi.inputActive) lockScreenUi.inputActive = true;
        }
        onPositionChanged: {
            pointerActive = seenPositionChange;
            seenPositionChange = true;
        }
        onBlockUIChanged: if (blockUI) lockScreenUi.inputActive = true
        onExited: {
            lockScreenUi.inputActive = false;
            pointerActive = false;
        }
        Keys.onEscapePressed: {
            if (lockScreenUi.powerMenuOpen) {
                lockScreenUi.powerMenuOpen = false;
                passwordBox.forceActiveFocus();
            } else if (lockScreenUi.inputActive) {
                lockScreenUi.inputActive = false;
            }
        }
        Keys.onPressed: event => {
            if (!lockScreenUi.isPlayingIntro && !lockScreenUi.isUnlocking && event.key !== Qt.Key_Escape)
                lockScreenUi.inputActive = true;
            event.accepted = false;
        }

        // --- Background: the wallpaper blurred and dimmed, more so while typing ---------
        MultiEffect {
            id: blurEffect
            anchors.fill: parent
            source: wallpaper
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: lockScreenUi.s(48)
            blur: lockScreenUi.inputActive ? 1.0 : 0.55
            Behavior on blur {
                enabled: !lockScreenUi.isPlayingIntro && !lockScreenUi.isUnlocking
                NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
            }
            opacity: lockScreenUi.contentReveal
            visible: opacity > 0.01
        }
        Rectangle {
            id: dimmer
            anchors.fill: parent
            color: lockScreenUi.crust
            opacity: (lockScreenUi.inputActive ? 0.72 : 0.32) * lockScreenUi.contentReveal
            Behavior on opacity {
                enabled: !lockScreenUi.isPlayingIntro && !lockScreenUi.isUnlocking
                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
            }
        }

        // --- Content ---------------------------------------------------------------------
        Item {
            id: rootContent
            anchors.fill: parent
            opacity: lockScreenUi.mainOpacity

            Item {
                anchors.fill: parent
                opacity: lockScreenUi.contentReveal
                transform: Translate { y: lockScreenUi.s(20) * (1.0 - lockScreenUi.contentReveal) }

                ColumnLayout {
                    id: clockModule
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: lockScreenUi.inputActive ? -lockScreenUi.s(280) : -lockScreenUi.s(130)
                    spacing: lockScreenUi.s(8)
                    opacity: (lockScreenUi.inputActive || lockScreenUi.centerReveal > 0.02) ? 0.0 : 1.0
                    scale: (lockScreenUi.inputActive || lockScreenUi.centerReveal > 0.02) ? 0.92 : 1.0
                    visible: opacity > 0.01
                    Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    readonly property string hourFmt: lockScreenUi.is12Hour
                        ? (lockScreenUi.timeFormat.indexOf("hh") !== -1 ? "hh" : "h")
                        : ((lockScreenUi.timeFormat.indexOf("H") !== -1 && lockScreenUi.timeFormat.indexOf("HH") === -1) ? "H" : "HH")

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: lockScreenUi.s(4)
                        Text {
                            text: Qt.formatDateTime(lockScreenUi.now, clockModule.hourFmt)
                            font.family: lockScreenUi.uiFont
                            font.pixelSize: lockScreenUi.s(120)
                            font.weight: Font.Normal
                            color: lockScreenUi.text
                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.25)
                        }
                        Text {
                            id: clockColon
                            text: ":"
                            font.family: lockScreenUi.uiFont
                            font.pixelSize: lockScreenUi.s(80)
                            font.weight: Font.Light
                            Layout.alignment: Qt.AlignVCenter
                            color: lockScreenUi.text
                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.25)
                            opacity: 0.6
                            SequentialAnimation on opacity {
                                running: !lockScreenUi.isPlayingIntro && !lockScreenUi.isUnlocking
                                loops: Animation.Infinite
                                NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.OutCubic }
                                NumberAnimation { to: 0.35; duration: 500; easing.type: Easing.InCubic }
                            }
                        }
                        Text {
                            text: Qt.formatDateTime(lockScreenUi.now, "mm")
                            font.family: lockScreenUi.uiFont
                            font.pixelSize: lockScreenUi.s(120)
                            font.weight: Font.Normal
                            color: lockScreenUi.text
                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.25)
                        }
                        Text {
                            visible: lockScreenUi.is12Hour
                            text: Qt.formatDateTime(lockScreenUi.now, "AP")
                            font.family: lockScreenUi.uiFont
                            font.pixelSize: lockScreenUi.s(28)
                            font.weight: Font.Bold
                            color: lockScreenUi.text
                            opacity: 0.8
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: lockScreenUi.s(24)
                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.25)
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(lockScreenUi.now, "dddd, d MMMM").toUpperCase()
                        font.family: lockScreenUi.uiFont
                        font.pixelSize: lockScreenUi.s(14)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4 * lockScreenUi.sf
                        color: lockScreenUi.text
                        opacity: 0.85
                    }
                }

                // The prompt keeps KDE's StackView so the no-password unlock path still works.
                StackView {
                    id: mainStack
                    anchors.fill: parent
                    focus: true

                    initialItem: FocusScope {
                        id: dashboard
                        focus: true

                        StackView.onStatusChanged: {
                            if (StackView.status === StackView.Activating) {
                                passwordBox.clear();
                                passwordBox.focus = true;
                                root.notification = "";
                            }
                        }
                        Connections {
                            target: root
                            function onClearPassword() {
                                passwordBox.forceActiveFocus();
                                passwordBox.text = "";
                                passwordBox.text = Qt.binding(() => PasswordSync.password);
                                passwordPill.syncEcho();
                            }
                        }
                        Binding { target: PasswordSync; property: "password"; value: passwordBox.text }

                        function startLogin() {
                            if (passwordBox.text.length === 0 || lockScreenUi.busy || lockScreenUi.isUnlocking) return;
                            const password = passwordBox.text;
                            lockScreenUi.failed = false;
                            authenticator.respond(password);
                        }

                        Rectangle {
                            id: mainDashboardShell
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: lockScreenUi.inputActive ? 0 : lockScreenUi.s(90)
                            width: Math.min(parent.width - lockScreenUi.s(48), lockScreenUi.s(440) + lockScreenUi.wingsReveal * lockScreenUi.s(780))
                            height: lockScreenUi.s(540)
                            radius: lockScreenUi.cardRadius
                            color: lockScreenUi.surface0
                            border.width: 1.5
                            border.color: lockScreenUi.surface1
                            clip: true
                            opacity: lockScreenUi.centerReveal
                            scale: 0.92 + lockScreenUi.centerReveal * 0.08
                            visible: opacity > 0.01
                            transform: Scale {
                                origin.x: mainDashboardShell.width / 2
                                origin.y: mainDashboardShell.height / 2
                                xScale: lockScreenUi.isUnlocking ? lockScreenUi.foldScaleX : 1.0
                                yScale: lockScreenUi.isUnlocking ? lockScreenUi.foldScaleY : 1.0
                            }
                            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                            readonly property real wingWidth: lockScreenUi.wingsReveal * lockScreenUi.s(390)
                            readonly property real centerWidth: lockScreenUi.s(440)

                            Item {
                                x: 0
                                width: mainDashboardShell.wingWidth
                                height: parent.height
                                clip: true
                                opacity: lockScreenUi.wingsReveal
                                visible: width > 0.5
                                Loader {
                                    width: lockScreenUi.s(390)
                                    height: parent.height
                                    active: lockScreenUi.wingsEverNeeded
                                    asynchronous: true
                                    sourceComponent: leftWingContent
                                }
                            }

                            Item {
                                id: centerUserPanel
                                x: mainDashboardShell.wingWidth
                                width: mainDashboardShell.centerWidth
                                height: parent.height

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: lockScreenUi.s(24)
                                    spacing: 0

                                    Item { Layout.fillHeight: true; Layout.preferredHeight: lockScreenUi.s(22) }

                                    Item {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.preferredWidth: lockScreenUi.s(190)
                                        Layout.preferredHeight: lockScreenUi.s(190)
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: lockScreenUi.s(95)
                                            color: lockScreenUi.surface1
                                            visible: avatarImg.status !== Image.Ready
                                            Text {
                                                anchors.centerIn: parent
                                                text: ""
                                                font.family: lockScreenUi.iconFont
                                                font.pixelSize: lockScreenUi.s(95)
                                                color: lockScreenUi.text
                                            }
                                        }
                                        Image {
                                            id: avatarImg
                                            anchors.fill: parent
                                            source: kscreenlocker_userImage !== "" ? "file://" + kscreenlocker_userImage : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: width * Screen.devicePixelRatio
                                            visible: false
                                        }
                                        Rectangle { id: avatarMask; anchors.fill: parent; radius: lockScreenUi.s(95); visible: false }
                                        OpacityMask {
                                            anchors.fill: parent
                                            source: avatarImg
                                            maskSource: avatarMask
                                            visible: avatarImg.status === Image.Ready
                                        }
                                    }

                                    Item { Layout.fillHeight: true; Layout.preferredHeight: lockScreenUi.s(20) }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: lockScreenUi.s(14)

                                        ClickButton {
                                            Layout.alignment: Qt.AlignHCenter
                                            Layout.preferredHeight: lockScreenUi.s(38)
                                            cornerRadius: lockScreenUi.radius
                                            horizontalPadding: lockScreenUi.s(16)
                                            buttonIcon: ""
                                            iconFontSize: lockScreenUi.s(15)
                                            buttonText: kscreenlocker_userName + " • " + lockScreenUi.statusText
                                            textFontSize: lockScreenUi.s(13)
                                            fontFamily: lockScreenUi.uiFont
                                            sf: lockScreenUi.sf
                                            accentColor: Qt.lighter(lockScreenUi.surface0, 1.28)
                                            textColor: lockScreenUi.failed ? lockScreenUi.red : (lockScreenUi.busy ? lockScreenUi.peach : lockScreenUi.text)
                                            iconColor: textColor
                                        }

                                        // v2's PasswordInput pill; the echo is rpoly's, shared with the polkit dialog.
                                        Item {
                                            id: passwordPill
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: lockScreenUi.s(44)

                                            property bool revealed: false
                                            readonly property color signalColor: lockScreenUi.failed ? lockScreenUi.red
                                                                               : (lockScreenUi.busy ? lockScreenUi.peach : lockScreenUi.mauve)
                                            property real focusPop: 1.0

                                            function shake() { shakeAnim.restart(); }
                                            function syncEcho() { glyphEcho.syncEcho(); }

                                            SequentialAnimation {
                                                id: shakeAnim
                                                NumberAnimation { target: shakeT; property: "x"; from: 0; to: -6; duration: 50 }
                                                NumberAnimation { target: shakeT; property: "x"; from: -6; to: 6; duration: 50 }
                                                NumberAnimation { target: shakeT; property: "x"; from: 6; to: -4; duration: 50 }
                                                NumberAnimation { target: shakeT; property: "x"; from: -4; to: 4; duration: 50 }
                                                NumberAnimation { target: shakeT; property: "x"; from: 4; to: 0; duration: 50 }
                                            }
                                            SequentialAnimation {
                                                id: focusPopAnim
                                                NumberAnimation { target: passwordPill; property: "focusPop"; to: 1.02; duration: 120; easing.type: Easing.OutQuad }
                                                NumberAnimation { target: passwordPill; property: "focusPop"; to: 1.0; duration: 320; easing.type: Easing.OutCubic }
                                            }
                                            Connections {
                                                target: passwordBox
                                                function onActiveFocusChanged() { if (passwordBox.activeFocus) focusPopAnim.restart(); }
                                            }

                                            Item {
                                                anchors.fill: parent
                                                scale: (lockScreenUi.failed ? 1.02 : (lockScreenUi.busy ? 0.98 : 1.0)) * passwordPill.focusPop
                                                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                                transform: Translate { id: shakeT }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: lockScreenUi.radius
                                                    color: Qt.lighter(lockScreenUi.surface0, 1.28)
                                                    opacity: passwordBox.enabled ? 1.0 : 0.5
                                                }

                                                // The lock box: state colour, click to reveal.
                                                Rectangle {
                                                    id: lockButton
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: lockScreenUi.s(4)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: lockScreenUi.s(36); height: lockScreenUi.s(36)
                                                    radius: Math.max(lockScreenUi.s(4), lockScreenUi.radius - lockScreenUi.s(4))
                                                    color: (lockScreenUi.failed || lockScreenUi.busy) ? Qt.alpha(passwordPill.signalColor, 0.16)
                                                         : (lockMa.containsMouse ? Qt.lighter(lockScreenUi.surface0, 1.75) : Qt.lighter(lockScreenUi.surface0, 1.55))
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: passwordPill.revealed ? "󰿆" : "󰌾"
                                                        font.family: lockScreenUi.iconFont
                                                        font.pixelSize: lockScreenUi.s(17)
                                                        color: (lockScreenUi.failed || lockScreenUi.busy) ? passwordPill.signalColor : lockScreenUi.subtext0
                                                        rotation: lockScreenUi.busy ? busySpin.angle : 0
                                                    }
                                                    Item {
                                                        id: busySpin
                                                        property real angle: 0
                                                        SequentialAnimation on angle {
                                                            running: lockScreenUi.busy
                                                            loops: Animation.Infinite
                                                            NumberAnimation { from: 0; to: 360; duration: 540; easing.type: Easing.InOutCubic }
                                                            PauseAnimation { duration: 480 }
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: lockMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: { passwordPill.revealed = !passwordPill.revealed; passwordBox.forceActiveFocus(); }
                                                    }
                                                }

                                                // Submit chevron.
                                                Rectangle {
                                                    id: submitButton
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: lockScreenUi.s(4)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: lockScreenUi.s(36); height: lockScreenUi.s(36)
                                                    radius: Math.max(lockScreenUi.s(4), lockScreenUi.radius - lockScreenUi.s(4))
                                                    color: submitMa.pressed ? Qt.darker(passwordPill.signalColor, 1.12)
                                                         : (submitMa.containsMouse ? Qt.lighter(passwordPill.signalColor, 1.12) : passwordPill.signalColor)
                                                    opacity: passwordBox.enabled && !lockScreenUi.busy ? 1.0 : 0.5
                                                    scale: submitMa.pressed ? 1.08 : (submitMa.containsMouse ? 1.04 : 1.0)
                                                    Behavior on color { ColorAnimation { duration: 180 } }
                                                    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: ""
                                                        font.family: lockScreenUi.iconFont
                                                        font.pixelSize: lockScreenUi.s(16)
                                                        color: lockScreenUi.surface0
                                                    }
                                                    MouseArea {
                                                        id: submitMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: { passwordBox.forceActiveFocus(); dashboard.startLogin(); }
                                                    }
                                                }

                                                Item {
                                                    id: fieldArea
                                                    anchors.left: lockButton.right
                                                    anchors.leftMargin: lockScreenUi.s(6)
                                                    anchors.right: submitButton.left
                                                    anchors.rightMargin: lockScreenUi.s(6)
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    clip: true

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Enter PIN"
                                                        font.family: lockScreenUi.uiFont
                                                        font.pixelSize: lockScreenUi.s(14)
                                                        color: lockScreenUi.subtext0
                                                        opacity: (passwordBox.text.length === 0 && !passwordBox.activeFocus) ? 0.45 : 0.0
                                                        Behavior on opacity { NumberAnimation { duration: 180 } }
                                                    }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        width: Math.min(implicitWidth, parent.width)
                                                        text: passwordBox.text
                                                        font.family: lockScreenUi.uiFont
                                                        font.pixelSize: lockScreenUi.s(14)
                                                        color: lockScreenUi.text
                                                        elide: Text.ElideLeft
                                                        visible: passwordPill.revealed
                                                    }

                                                    TextInput {
                                                        id: passwordBox
                                                        anchors.fill: parent
                                                        focus: true
                                                        opacity: 0
                                                        color: "transparent"
                                                        selectionColor: "transparent"
                                                        selectedTextColor: "transparent"
                                                        echoMode: TextInput.Password
                                                        passwordMaskDelay: 0
                                                        cursorVisible: false
                                                        font.family: lockScreenUi.uiFont
                                                        font.pixelSize: lockScreenUi.s(14)
                                                        text: PasswordSync.password
                                                        enabled: !lockScreenUi.isPlayingIntro && !lockScreenUi.isUnlocking
                                                        // The hidden field keeps focus while idle, so the first character lands here and opens the card.
                                                        onTextChanged: {
                                                            if (text.length > 0) {
                                                                lockScreenUi.failed = false;
                                                                idleTimer.stop();
                                                                if (!lockScreenUi.inputActive && !lockScreenUi.isPlayingIntro && !lockScreenUi.isUnlocking)
                                                                    lockScreenUi.inputActive = true;
                                                            } else if (lockScreenUi.inputActive) {
                                                                idleTimer.restart();
                                                            }
                                                        }
                                                        onAccepted: dashboard.startLogin()
                                                    }

                                                    // v1's glyph echo: one Material shape per character, popping in accent then text.
                                                    Item {
                                                        id: glyphEcho
                                                        anchors.fill: parent
                                                        visible: !passwordPill.revealed

                                                        readonly property var shapes: [
                                                            MaterialShapes.getCircle,
                                                            MaterialShapes.getCookie4Sided,
                                                            MaterialShapes.getDiamond,
                                                            MaterialShapes.getClover4Leaf,
                                                            MaterialShapes.getSquare,
                                                            MaterialShapes.getSunny,
                                                            MaterialShapes.getPentagon,
                                                            MaterialShapes.getPuffy,
                                                            MaterialShapes.getGem,
                                                            MaterialShapes.getCookie6Sided,
                                                            MaterialShapes.getTriangle,
                                                            MaterialShapes.getFlower
                                                        ]
                                                        function shapeFor(i) {
                                                            var l = glyphEcho.shapes;
                                                            return l[((i % l.length) + l.length) % l.length]();
                                                        }

                                                        // Append or remove the difference: an int model would rebuild every Canvas per keystroke.
                                                        ListModel { id: echoModel }
                                                        readonly property int charCount: passwordBox.text.length
                                                        onCharCountChanged: glyphEcho.syncEcho()
                                                        Component.onCompleted: glyphEcho.syncEcho()
                                                        function syncEcho() {
                                                            var n = glyphEcho.charCount;
                                                            while (echoModel.count > n) echoModel.remove(echoModel.count - 1);
                                                            while (echoModel.count < n) echoModel.append({ slot: echoModel.count });
                                                        }
                                                        readonly property real cell: lockScreenUi.s(18)

                                                        Row {
                                                            id: glyphRow
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            x: Math.min((glyphEcho.width - width) / 2, glyphEcho.width - width - lockScreenUi.s(4))
                                                            spacing: lockScreenUi.s(3)
                                                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                            Repeater {
                                                                model: echoModel
                                                                delegate: Item {
                                                                    id: cellItem
                                                                    required property int index
                                                                    width: glyphEcho.cell
                                                                    height: glyphEcho.cell
                                                                    opacity: 0
                                                                    scale: 0.5
                                                                    readonly property color settleColor: (cellItem.index % 2 === 0) ? lockScreenUi.mauve : lockScreenUi.text

                                                                    ShapeCanvas {
                                                                        id: glyphShape
                                                                        anchors.centerIn: parent
                                                                        width: Math.round(glyphEcho.cell * 0.74)
                                                                        height: width
                                                                        roundedPolygon: glyphEcho.shapeFor(cellItem.index)
                                                                        polygonIsNormalized: true
                                                                        color: lockScreenUi.mauve
                                                                        antialiasing: true
                                                                    }
                                                                    Component.onCompleted: popIn.start()
                                                                    ParallelAnimation {
                                                                        id: popIn
                                                                        NumberAnimation { target: cellItem; property: "opacity"; to: 1.0; duration: 120 }
                                                                        NumberAnimation { target: cellItem; property: "scale"; from: 0.5; to: 1.0; duration: 240; easing.type: Easing.OutBack }
                                                                        ColorAnimation { target: glyphShape; property: "color"; from: lockScreenUi.mauve; to: cellItem.settleColor; duration: 900 }
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Rectangle {
                                                            id: echoCaret
                                                            visible: passwordBox.activeFocus && passwordBox.text.length > 0
                                                            width: lockScreenUi.s(2)
                                                            radius: lockScreenUi.s(1)
                                                            height: Math.round(glyphEcho.cell * 0.95)
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            x: glyphRow.x + glyphRow.width + lockScreenUi.s(3)
                                                            color: passwordPill.signalColor
                                                            SequentialAnimation on opacity {
                                                                running: echoCaret.visible
                                                                loops: Animation.Infinite
                                                                NumberAnimation { to: 1.0; duration: 1 }
                                                                PauseAnimation { duration: 550 }
                                                                NumberAnimation { to: 0.0; duration: 200 }
                                                                PauseAnimation { duration: 350 }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: lockScreenUi.s(10)

                                            ClickButton {
                                                Layout.preferredHeight: lockScreenUi.s(32)
                                                cornerRadius: lockScreenUi.radius
                                                horizontalPadding: lockScreenUi.s(12)
                                                buttonIcon: "󰌌"
                                                iconFontSize: lockScreenUi.s(14)
                                                buttonText: kbSwitcher.layoutNames.shortName !== "" ? kbSwitcher.layoutNames.shortName.toUpperCase() : "US"
                                                textFontSize: lockScreenUi.s(12)
                                                fontFamily: lockScreenUi.uiFont
                                                sf: lockScreenUi.sf
                                                accentColor: Qt.lighter(lockScreenUi.surface0, 1.28)
                                                textColor: lockScreenUi.text
                                                onClicked: if (kbSwitcher.hasMultipleKeyboardLayouts) kbSwitcher.keyboardLayout.switchToNextLayout()
                                            }
                                            ClickButton {
                                                visible: capsLockState.locked
                                                Layout.preferredHeight: lockScreenUi.s(32)
                                                cornerRadius: lockScreenUi.radius
                                                horizontalPadding: lockScreenUi.s(12)
                                                buttonIcon: "󰪛"
                                                iconFontSize: lockScreenUi.s(14)
                                                buttonText: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on")
                                                textFontSize: lockScreenUi.s(12)
                                                fontFamily: lockScreenUi.uiFont
                                                sf: lockScreenUi.sf
                                                accentColor: Qt.lighter(lockScreenUi.surface0, 1.28)
                                                textColor: lockScreenUi.peach
                                            }
                                        }

                                        // KDE's other authenticators and PAM messages, when there are any.
                                        Text {
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                            text: {
                                                var parts = [];
                                                if (authenticator.authenticatorTypes & ScreenLocker.Authenticator.Fingerprint)
                                                    parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your fingerprint on the reader)"));
                                                if (authenticator.authenticatorTypes & ScreenLocker.Authenticator.Smartcard)
                                                    parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your smartcard)"));
                                                if (root.notification && root.notification.indexOf("Unlocking failed") === -1)
                                                    parts.push(root.notification);
                                                return parts.join("\n");
                                            }
                                            font.family: lockScreenUi.uiFont
                                            font.pixelSize: lockScreenUi.s(10)
                                            color: lockScreenUi.subtext0
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                        }
                                    }

                                    Item { Layout.fillHeight: true; Layout.preferredHeight: lockScreenUi.s(16) }
                                }
                            }

                            Item {
                                x: mainDashboardShell.wingWidth + mainDashboardShell.centerWidth
                                width: mainDashboardShell.wingWidth
                                height: parent.height
                                clip: true
                                opacity: lockScreenUi.wingsReveal
                                visible: width > 0.5
                                Loader {
                                    width: lockScreenUi.s(390)
                                    height: parent.height
                                    active: lockScreenUi.wingsEverNeeded
                                    asynchronous: true
                                    sourceComponent: rightWingContent
                                }
                            }
                        }
                    }
                }

                Item {
                    id: bottomInfoTray
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: lockScreenUi.s(16)
                    anchors.left: parent.left
                    anchors.leftMargin: lockScreenUi.s(20)
                    anchors.right: parent.right
                    anchors.rightMargin: lockScreenUi.s(20)
                    height: lockScreenUi.s(48)
                    opacity: lockScreenUi.inputActive ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

                    IconButton {
                        id: powerToggle
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        size: lockScreenUi.s(48)
                        cornerRadius: lockScreenUi.radius
                        buttonIcon: lockScreenUi.powerMenuOpen ? "󰅖" : "󰐥"
                        iconFontSize: lockScreenUi.s(20)
                        accentColor: lockScreenUi.powerMenuOpen ? lockScreenUi.surface2 : Qt.lighter(lockScreenUi.surface0, 1.28)
                        textColor: lockScreenUi.powerMenuOpen ? lockScreenUi.text : lockScreenUi.red
                        onClicked: lockScreenUi.powerMenuOpen = !lockScreenUi.powerMenuOpen
                    }
                }

                Rectangle {
                    id: powerContainer
                    anchors.bottom: bottomInfoTray.top
                    anchors.bottomMargin: lockScreenUi.s(16)
                    anchors.right: bottomInfoTray.right
                    width: lockScreenUi.s(320)
                    height: lockScreenUi.powerMenuOpen ? menuLayout.implicitHeight + lockScreenUi.s(24) : 0
                    radius: lockScreenUi.radius
                    clip: true
                    visible: height > 0 || opacity > 0
                    opacity: lockScreenUi.powerMenuOpen ? 1.0 : 0.0
                    color: Qt.alpha(lockScreenUi.surface0, 0.45)
                    border.color: Qt.alpha(lockScreenUi.surface1, 0.4)
                    border.width: 1
                    Behavior on height { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: menuLayout
                        anchors.top: parent.top
                        anchors.topMargin: lockScreenUi.s(12)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: lockScreenUi.s(12)
                        anchors.rightMargin: lockScreenUi.s(12)
                        spacing: lockScreenUi.s(8)

                        FillButton {
                            Layout.fillWidth: true
                            cornerRadius: lockScreenUi.radius
                            fontFamily: lockScreenUi.uiFont
                            sf: lockScreenUi.sf
                            buttonIcon: "󰒲"
                            buttonText: "Suspend"
                            accentColor: lockScreenUi.mauve
                            baseColor: lockScreenUi.surface0
                            hoverColor: lockScreenUi.surface1
                            textColor: lockScreenUi.text
                            filledTextColor: lockScreenUi.crust
                            fillDuration: 1200
                            enabled: sessionManagement.canSuspend
                            opacity: enabled ? 1.0 : 0.4
                            onTriggered: { lockScreenUi.powerMenuOpen = false; sessionManagement.suspend(); }
                        }
                        FillButton {
                            Layout.fillWidth: true
                            cornerRadius: lockScreenUi.radius
                            fontFamily: lockScreenUi.uiFont
                            sf: lockScreenUi.sf
                            buttonIcon: "󰑓"
                            buttonText: "Reboot"
                            accentColor: lockScreenUi.sapphire
                            baseColor: lockScreenUi.surface0
                            hoverColor: lockScreenUi.surface1
                            textColor: lockScreenUi.text
                            filledTextColor: lockScreenUi.crust
                            fillDuration: 1200
                            enabled: sessionManagement.canReboot
                            opacity: enabled ? 1.0 : 0.4
                            // Skip the confirmation: it would open behind the lock.
                            onTriggered: { lockScreenUi.powerMenuOpen = false; sessionManagement.requestReboot(SessionManagement.ConfirmationMode.Skip); }
                        }
                        FillButton {
                            Layout.fillWidth: true
                            cornerRadius: lockScreenUi.radius
                            fontFamily: lockScreenUi.uiFont
                            sf: lockScreenUi.sf
                            buttonIcon: "󰐥"
                            buttonText: "Power off"
                            accentColor: lockScreenUi.red
                            baseColor: lockScreenUi.surface0
                            hoverColor: lockScreenUi.surface1
                            textColor: lockScreenUi.text
                            filledTextColor: lockScreenUi.crust
                            fillDuration: 1200
                            enabled: sessionManagement.canShutdown
                            opacity: enabled ? 1.0 : 0.4
                            onTriggered: { lockScreenUi.powerMenuOpen = false; sessionManagement.requestShutdown(SessionManagement.ConfirmationMode.Skip); }
                        }
                    }
                }
            }
        }

        // v2's intro: five colour bands wipe down, then lift to reveal the screen.
        Canvas {
            id: wipeCanvas
            anchors.fill: parent
            renderTarget: Canvas.FramebufferObject
            renderStrategy: Canvas.Immediate
            property real lastPaintedRev: -1
            readonly property var wipeColors: [
                lockScreenUi.crust.toString(),
                lockScreenUi.surface1.toString(),
                lockScreenUi.sapphire.toString(),
                lockScreenUi.mauve.toString(),
                lockScreenUi.surface0.toString()
            ]
            readonly property var wipeAmps: [1.5, 1.3, 1.1, 0.9, 0.6]
            readonly property var wipeOffsets: [0.0, 0.5, 1.0, 1.5, 2.0]
            opacity: lockScreenUi.isPlayingIntro ? (lockScreenUi.panelReveal < 0.8 ? 1.0 : Math.max(0.0, (1.0 - lockScreenUi.panelReveal) / 0.2)) : 0.0
            visible: opacity > 0.001

            Connections {
                target: lockScreenUi
                enabled: lockScreenUi.isPlayingIntro && wipeCanvas.visible
                function onPanelRevealChanged() {
                    if (Math.abs(lockScreenUi.panelReveal - wipeCanvas.lastPaintedRev) >= 0.005) wipeCanvas.requestPaint();
                }
            }

            onPaint: {
                var rev = lockScreenUi.panelReveal;
                lastPaintedRev = rev;
                if (rev <= 0.0) return;
                var ctx = getContext("2d");
                var w = width, h = height;
                var lastFull = -1;
                for (var k = 4; k >= 0; k--) {
                    var p = (rev - (k === 0 ? 0.0 : k * 0.07)) * 1.55;
                    if (p >= 1.0) { lastFull = k; break; }
                }
                if (lastFull >= 0) { ctx.fillStyle = wipeColors[lastFull]; ctx.fillRect(0, 0, w, h); }
                else ctx.clearRect(0, 0, w, h);
                var start = lastFull + 1;
                if (start >= 5) return;
                var phase = rev * 7.853981633974483;
                var cp1x = w * 0.38, cp2x = w * 0.72, pi = Math.PI;
                for (var i = start; i < 5; i++) {
                    var prog = (rev - (i === 0 ? 0.0 : i * 0.07)) * 1.55;
                    if (prog <= 0.0) continue;
                    var smoothProg = Math.pow(prog, 1.4);
                    var currentY = h * smoothProg;
                    var waveAmp = lockScreenUi.s(28) * Math.sin(smoothProg * pi) * wipeAmps[i];
                    var cp1y = currentY + Math.sin(phase + wipeOffsets[i]) * waveAmp;
                    var cp2y = currentY + Math.cos(phase + wipeOffsets[i] + pi) * waveAmp;
                    ctx.beginPath();
                    ctx.moveTo(0, 0);
                    ctx.lineTo(0, currentY);
                    ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, w, currentY);
                    ctx.lineTo(w, 0);
                    ctx.closePath();
                    ctx.fillStyle = wipeColors[i];
                    ctx.fill();
                }
            }
        }

        Loader {
            z: 2
            active: root.viewVisible
            source: "LockOsd.qml"
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: Kirigami.Units.gridUnit
            }
        }
    }

    Component {
        id: leftWingContent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: lockScreenUi.s(14)
            spacing: lockScreenUi.s(8)
            LockWeather { lock: lockScreenUi; Layout.fillWidth: true; Layout.preferredHeight: lockScreenUi.s(182) }
            LockCalendar { lock: lockScreenUi; Layout.fillWidth: true; Layout.fillHeight: true }
        }
    }

    Component {
        id: rightWingContent
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: lockScreenUi.s(14)
            spacing: lockScreenUi.s(10)
            LockNotifications { lock: lockScreenUi; Layout.fillWidth: true; Layout.fillHeight: true }
            LockMedia { lock: lockScreenUi; Layout.fillWidth: true; Layout.preferredHeight: lockScreenUi.s(96) }
        }
    }
}
