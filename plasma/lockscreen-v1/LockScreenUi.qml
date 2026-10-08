/*
    SPDX-FileCopyrightText: 2014 Aleix Pol Gonzalez <aleixpol@blue-systems.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.components as PW
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.plasma.private.sessions
import org.kde.breeze.components
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.private.mpris as Mpris

Item {
    id: lockScreenUi

    // If we're using software rendering, draw outlines instead of shadows
    // See https://bugs.kde.org/show_bug.cgi?id=398317
    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software

    // Flashes true briefly on a failed unlock (drives the ring halo red).
    property bool authFailed: false

    // Ambient orbit angle (drives the drifting glow blobs) + one-shot intro state.
    property real orbitAngle: 0
    NumberAnimation on orbitAngle { from: 0; to: Math.PI * 2; duration: 60000; loops: Animation.Infinite; running: true }
    property real introState: 0
    NumberAnimation on introState { from: 0; to: 1.0; duration: 900; easing.type: Easing.OutCubic; running: true }

    // --- Weather ---------------------------------------------------------------
    // The greeter cannot run our scripts or XHR-read files, so cat the cache the
    // session keeps fresh. Blocked execution just leaves weatherTemp empty.
    property string weatherIcon: ""
    property string weatherTemp: ""
    readonly property string weatherCmd:
        "sh -c 'cat \"$HOME/.cache/quickshell/weather/weather.json\"'"

    Plasma5Support.DataSource {
        id: weatherSource
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            weatherSource.disconnectSource(source);   // one-shot per poll
            var out = ("" + (data["stdout"] || "")).trim();
            if (out === "")
                return;
            try {
                var j = JSON.parse(out);
                lockScreenUi.weatherIcon = j.current_icon || "";
                lockScreenUi.weatherTemp = (j.current_temp !== undefined && j.current_temp !== "" && j.current_temp !== "--")
                    ? (j.current_temp + "°") : "";
            } catch (e) {
                // malformed cache — leave previous values
            }
        }
        function poll() {
            var cmd = lockScreenUi.weatherCmd;
            disconnectSource(cmd);
            connectSource(cmd);
        }
        Component.onCompleted: poll()
    }
    // Refresh periodically in case a lock lasts a while (session keeps cache fresh).
    Timer {
        interval: 300000; running: true; repeat: true
        onTriggered: weatherSource.poll()
    }

    // --- Notifications (count only) --------------------------------------------
    // Asked of the running shell over IPC: the notification list only exists
    // inside whichever process owns org.freedesktop.Notifications (the
    // freedesktop spec cannot enumerate them from the bus), and that is our
    // Quickshell session, which keeps running while locked.
    //
    // Selected by PID, not config path. `qs -p <path>` matches instances by
    // DISPLAY CONNECTION and the greeter has no WAYLAND_DISPLAY at all — ksld
    // passes the compositor as a WAYLAND_SOCKET fd — so every instance looks
    // dead to it. `--pid` ignores the display (and belongs to the `ipc`
    // subcommand). The bracket in quickshel[l] stops pgrep matching this command.
    property int notifCount: 0
    property int notifTick: 0
    property bool notifExpanded: false

    ListModel { id: notifModel }

    // "2m" / "1h": on a lock screen how long ago it landed beats a wall clock.
    function notifAge(ms) {
        if (!ms) return "";
        var d = Math.max(0, Date.now() - ms);
        var m = Math.floor(d / 60000);
        if (m < 1) return "now";
        if (m < 60) return m + "m";
        var h = Math.floor(m / 60);
        if (h < 24) return h + "h";
        return Math.floor(h / 24) + "d";
    }

    readonly property string notifCmd:
        "sh -c '"
        + "p=$(pgrep -f \"(quickshel[l]|q[s]) (-[nd] )*-p .*/shell[.]qml$\" | head -1); "
        + "[ -n \"$p\" ] && qs ipc --pid \"$p\" call notifcenter list"
        + "'"

    Plasma5Support.DataSource {
        id: notifSource
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            notifSource.disconnectSource(source);
            var out = ("" + (data["stdout"] || "")).trim();
            if (out === "")
                return;
            try {
                var arr = JSON.parse(out);
                lockScreenUi.notifCount = arr.length;
                notifModel.clear();
                for (var i = 0; i < arr.length; i++)
                    notifModel.append(arr[i]);
                if (arr.length === 0)
                    lockScreenUi.notifExpanded = false;
            } catch (e) {
                // shell down or mid-restart — keep the last known count
            }
        }
        function poll() {
            // The engine keys results on the command STRING, so an identical
            // command can come back cached — which is why the count stuck at
            // whatever it was when the lock started. The trailing comment makes
            // each poll a distinct source.
            lockScreenUi.notifTick++;
            var cmd = lockScreenUi.notifCmd + " # " + lockScreenUi.notifTick;
            disconnectSource(cmd);
            connectSource(cmd);
        }
        Component.onCompleted: poll()
    }

    Timer {
        // 45s, not 5s. Each tick spawns a shell + pgrep + qs client, so 5s was
        // ~700 process spawns an hour to refresh a count. It was only that fast
        // while chasing the DataSource caching bug.
        interval: 45000; running: true; repeat: true
        onTriggered: notifSource.poll()
    }

    // --- Power menu (Sleep / Reboot / Shut Down) -------------------------------
    property bool powerMenuOpen: false

    function handleMessage(msg) {
        if (!root.notification) {
            root.notification += msg;
        } else if (root.notification.includes(msg)) {
            root.notificationRepeated();
        } else {
            root.notification += "\n" + msg
        }
    }

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) { // if this is coming from the noninteractive authenticators
                return;
            }
            const msg = i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Unlocking failed");
            lockScreenUi.handleMessage(msg);
            lockScreenUi.authFailed = true;
            graceLockTimer.restart();
            notificationRemoveTimer.restart();
            rejectPasswordAnimation.start();
        }

        function onSucceeded() {
            if (authenticator.hadPrompt) {
                Qt.quit();
            } else {
                mainStack.replace(null, Qt.resolvedUrl("NoPasswordUnlock.qml"),
                    {
                        userListModel: users
                    },
                    StackView.Immediate,
                );
                mainStack.forceActiveFocus();
            }
        }

        function onInfoMessageChanged() {
            lockScreenUi.handleMessage(authenticator.infoMessage);
        }

        function onErrorMessageChanged() {
            lockScreenUi.handleMessage(authenticator.errorMessage);
        }

        function onPromptChanged(msg) {
            lockScreenUi.handleMessage(authenticator.prompt);
        }
        function onPromptForSecretChanged(msg) {
            mainBlock.showPassword = false;
            mainBlock.mainPasswordBox.forceActiveFocus();
        }
    }

    SessionManagement {
        id: sessionManagement
    }

    KeyboardIndicator.KeyState {
        id: capsLockState
        key: Qt.Key_CapsLock
    }

    Connections {
        target: sessionManagement
        function onAboutToSuspend() {
            root.clearPassword();
        }
    }

    RejectPasswordAnimation {
        id: rejectPasswordAnimation
        target: mainBlock
    }

    MouseArea {
        id: lockScreenRoot

        property bool uiVisible: false
        property bool seenPositionChange: false
        // Cursor visibility, kept SEPARATE from uiVisible: the pointer must be
        // visible to aim at the bell or the power button, but moving or clicking
        // must not raise the password prompt — only the keyboard does that.
        property bool pointerActive: false
        property bool blockUI: containsMouse && (mainStack.depth > 1 || mainBlock.mainPasswordBox.text.length > 0 || inputPanel.keyboardActive)

        x: parent.x
        y: parent.y
        width: parent.width
        height: parent.height
        hoverEnabled: true
        cursorShape: (uiVisible || pointerActive) ? Qt.ArrowCursor : Qt.BlankCursor
        drag.filterChildren: true

        // drag.filterChildren means THIS area sees presses before its children,
        // so a plain "close everything" here fired before the bell's own
        // onClicked and the toggle could never close. Skip the close when the
        // press landed inside the thing it would close.
        function pressedInside(item, mx, my) {
            if (!item || !item.visible)
                return false;
            var p = lockScreenRoot.mapToItem(item, mx, my);
            return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height;
        }

        onPressed: mouse => {
            pointerActive = true;
            if (lockScreenUi.powerMenuOpen && !pressedInside(powerArea, mouse.x, mouse.y))
                lockScreenUi.powerMenuOpen = false;
            if (lockScreenUi.notifExpanded
                && !pressedInside(notifPill, mouse.x, mouse.y)
                && !pressedInside(notifList, mouse.x, mouse.y))
                lockScreenUi.notifExpanded = false;
        }
        onPositionChanged: {
            pointerActive = seenPositionChange;
            seenPositionChange = true;
        }
        onUiVisibleChanged: {
            if (uiVisible) {
                Window.window.requestActivate();
            }

            if (blockUI) {
                fadeoutTimer.running = false;
            } else if (uiVisible) {
                fadeoutTimer.restart();
            }
            authenticator.startAuthenticating();
        }
        onBlockUIChanged: {
            if (blockUI) {
                fadeoutTimer.running = false;
                uiVisible = true;
            } else {
                fadeoutTimer.restart();
            }
        }
        onExited: {
            uiVisible = false;
            pointerActive = false;
        }
        Keys.onEscapePressed: {
            // If the escape key is pressed, kscreenlocker will turn off the screen.
            // We do not want to show the password prompt in this case.
            if (uiVisible) {
                uiVisible = false;
                if (inputPanel.keyboardActive) {
                    inputPanel.showHide();
                }
                root.clearPassword();
            }
        }
        Keys.onPressed: event => {
            uiVisible = true;
            event.accepted = false;
        }
        Timer {
            id: fadeoutTimer
            interval: 10000
            onTriggered: {
                if (!lockScreenRoot.blockUI) {
                    mainBlock.mainPasswordBox.showPassword = false;
                    lockScreenRoot.uiVisible = false;
                }
            }
        }
        Timer {
            id: notificationRemoveTimer
            interval: 3000
            onTriggered: root.notification = ""
        }
        Timer {
            id: graceLockTimer
            interval: 3000
            onTriggered: {
                root.clearPassword();
                authenticator.startAuthenticating();
                lockScreenUi.authFailed = false;
            }
        }

        PropertyAnimation {
            id: launchAnimation
            target: lockScreenRoot
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration * 2
        }

        Component.onCompleted: launchAnimation.start();

        // Dummy target so the fader's state machine (which forces clock.opacity=1
        // when the UI is up) can't hijack our real clock — we drive the clock fade
        // ourselves (hide on input, serpantinum-style). The fader only ever pokes
        // opacity/shadow.opacity, so a throwaway item satisfies it harmlessly.
        Item {
            id: faderClockDummy
            visible: false
            property Item shadow: Item {}
        }

        WallpaperFader {
            anchors.fill: parent
            state: lockScreenRoot.uiVisible ? "on" : "off"
            source: wallpaper
            mainStack: mainStack
            footer: footer
            clock: faderClockDummy
            alwaysShowClock: config.alwaysShowClock && !config.hideClockWhenIdle
        }

        // Drifting ambient glow blobs (serpantinum). Faint, slow, accent-tinted.
        Item {
            anchors.fill: parent
            z: 0
            Rectangle {
                width: parent.width * 0.5; height: width; radius: width / 2
                x: parent.width / 2 - width / 2 + Math.cos(lockScreenUi.orbitAngle * 2) * (parent.width * 0.11)
                y: parent.height / 2 - height / 2 + Math.sin(lockScreenUi.orbitAngle * 2) * (parent.height * 0.12)
                color: Kirigami.Theme.highlightColor
                opacity: (lockScreenRoot.uiVisible ? 0.05 : 0.09) * lockScreenUi.introState
                Behavior on opacity { NumberAnimation { duration: 600 } }
            }
            Rectangle {
                width: parent.width * 0.55; height: width; radius: width / 2
                x: parent.width / 2 - width / 2 + Math.sin(lockScreenUi.orbitAngle * 1.5) * (-parent.width * 0.11)
                y: parent.height / 2 - height / 2 + Math.cos(lockScreenUi.orbitAngle * 1.5) * (-parent.height * 0.10)
                color: Qt.lighter(Kirigami.Theme.highlightColor, 1.4)
                opacity: (lockScreenRoot.uiVisible ? 0.04 : 0.07) * lockScreenUi.introState
                Behavior on opacity { NumberAnimation { duration: 600 } }
            }
        }

        // Ambient concentric ring halo behind the login (serpantinum signature).
        // Purely decorative; flashes red on a failed unlock. No auth involvement.
        Item {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Kirigami.Units.gridUnit * 2
            z: 0
            Repeater {
                model: 4
                delegate: Rectangle {
                    anchors.centerIn: parent
                    width: Kirigami.Units.gridUnit * (20 + index * 11)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: lockScreenUi.authFailed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    // Subtle ambient by default (but actually perceptible), bold red on failure.
                    opacity: lockScreenUi.authFailed ? (0.5 - index * 0.08) : (0.16 - index * 0.03)
                    Behavior on border.color { ColorAnimation { duration: 500; easing.type: Easing.OutExpo } }
                    Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                }
            }
        }

        DropShadow {
            id: clockShadow
            anchors.fill: clock
            source: clock
            visible: !lockScreenUi.softwareRendering && config.alwaysShowClock && mainStack.opacity < 0.5
            radius: 7
            verticalOffset: 0.8
            samples: 15
            spread: 0.2
            color : Qt.rgba(0, 0, 0, 0.7)
            opacity: 1.0 - mainStack.opacity
            Behavior on opacity {
                OpacityAnimator {
                    duration: Kirigami.Units.veryLongDuration * 2
                    easing.type: Easing.InOutQuad
                }
            }
        }

        // Custom serpantinum-style clock (replaces the stock breeze Clock).
        // Colors come from Kirigami.Theme = KDE Material You (matugen seed). The
        // external clockShadow DropShadow still sources this by id, so the drop
        // shadow keeps working. Exposes `shadow` + a real size like the original.
        Item {
            id: clock
            property Item shadow: clockShadow
            // Hard-gate on the password block's opacity — `visible` can't be
            // detached by the fader's opacity animations the way `opacity` was.
            visible: config.alwaysShowClock && mainStack.opacity < 0.5
            // Centered when idle; fades + slides up as the login UI appears.
            // Coupled directly to the password block's opacity (fader-animated
            // 0→1), so the clock is exactly the inverse of the password showing.
            opacity: (1.0 - mainStack.opacity) * lockScreenUi.introState
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Kirigami.Units.gridUnit * 2
            transform: [
                Translate {
                    y: -Kirigami.Units.gridUnit * 6 * mainStack.opacity
                    Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutExpo } }
                },
                Scale {
                    origin.x: clock.width / 2
                    origin.y: clock.height / 2
                    xScale: 0.92 + 0.08 * lockScreenUi.introState
                    yScale: 0.92 + 0.08 * lockScreenUi.introState
                }
            ]

            implicitWidth: clockCol.implicitWidth
            implicitHeight: clockCol.implicitHeight
            width: implicitWidth
            height: implicitHeight

            property var now: new Date()
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.now = new Date()
            }

            ColumnLayout {
                id: clockCol
                anchors.centerIn: parent
                spacing: -Kirigami.Units.largeSpacing

                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatTime(clock.now, Qt.locale(), Locale.ShortFormat)
                    color: Kirigami.Theme.textColor
                    font.family: "JetBrainsMono Nerd Font"   // exact family; plain "JetBrains Mono" falls back to Noto
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 7)
                    font.weight: Font.Bold
                }
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDate(clock.now, Qt.locale(), Locale.LongFormat)
                    color: Kirigami.Theme.textColor
                    opacity: 0.85
                    font.family: "JetBrainsMono Nerd Font"
                    font.pointSize: 16
                }

            }
        }

        // (Avatar now lives inside MainBlock, beside the password.)

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

        StackView {
            id: mainStack
            anchors {
                left: parent.left
                right: parent.right
            }
            height: lockScreenRoot.height + Kirigami.Units.gridUnit * 3
            focus: true //StackView is an implicit focus scope, so we need to give this focus so the item inside will have it

            // this isn't implicit, otherwise items still get processed for the scenegraph
            visible: opacity > 0

            initialItem: MainBlock {
                id: mainBlock
                lockScreenUiVisible: lockScreenRoot.uiVisible

                showUserList: false   // replaced by our custom avatar block below

                enabled: !graceLockTimer.running

                StackView.onStatusChanged: {
                    // prepare for presenting again to the user
                    if (StackView.status === StackView.Activating) {
                        mainPasswordBox.clear();
                        mainPasswordBox.focus = true;
                        root.notification = "";
                    }
                }
                userListModel: users


                notificationMessage: {
                    const parts = [];
                    if (capsLockState.locked) {
                        parts.push(i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:status", "Caps Lock is on"));
                    }
                    if (root.notification) {
                        parts.push(root.notification);
                    }
                    return parts.join(" • ");
                }

                onPasswordResult: password => {
                    authenticator.respond(password)
                }

                // Session action buttons (Sleep / Hibernate / Switch User) removed —
                // they don't fit the lock aesthetic. Suspend/switch-user remain
                // reachable via the physical power button / normal session controls.

            }
        }

        VirtualKeyboardLoader {
            id: inputPanel

            z: 1

            screenRoot: lockScreenRoot
            mainStack: mainStack
            mainBlock: mainBlock
            passwordField: mainBlock.mainPasswordBox
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

        // Notification count — a single pill in the corner the power button
        // vacated. Deliberately just the number: the full stack was more
        // furniture than a lock screen wants.
        Item {
            id: notifPill
            z: 4
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Kirigami.Units.gridUnit * 1.5
            anchors.rightMargin: Kirigami.Units.gridUnit * 1.5
            height: Kirigami.Units.gridUnit * 2.2
            width: notifRow.width + Kirigami.Units.gridUnit * 1.4
            visible: lockScreenUi.notifCount > 0
            opacity: lockScreenUi.introState

            // Frosted glass, same recipe as the bottom pills.
            ShaderEffectSource {
                id: notifGrab
                anchors.fill: parent
                sourceItem: wallpaper
                sourceRect: Qt.rect(notifPill.mapToItem(wallpaper, 0, 0).x,
                                    notifPill.mapToItem(wallpaper, 0, 0).y,
                                    notifPill.width, notifPill.height)
                visible: false
            }
            FastBlur {
                id: notifBlur
                anchors.fill: parent
                source: notifGrab
                radius: 48
                visible: false
            }
            Rectangle {
                id: notifMask
                anchors.fill: parent
                radius: height / 2
                visible: false
            }
            OpacityMask {
                anchors.fill: parent
                source: notifBlur
                maskSource: notifMask
            }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                               Kirigami.Theme.backgroundColor.g,
                               Kirigami.Theme.backgroundColor.b, 0.28)
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                      Kirigami.Theme.textColor.g,
                                      Kirigami.Theme.textColor.b, 0.14)
            }

            Row {
                id: notifRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // md-bell, or md-bell_badge while the list is open.
                    text: lockScreenUi.notifExpanded ? "\u{f116b}" : "\u{f009a}"
                    font.family: "Iosevka Nerd Font"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize
                    color: Kirigami.Theme.highlightColor
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: lockScreenUi.notifCount
                    font.family: "JetBrainsMono Nerd Font"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize
                    font.bold: true
                    color: Kirigami.Theme.textColor
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // Accepting the click stops it reaching the background handler,
                // which would close the list in the same event that opened it.
                onClicked: lockScreenUi.notifExpanded = !lockScreenUi.notifExpanded
            }

            // The list, hanging under the pill. Right-aligned to it so the two
            // read as one object.
            Column {
                id: notifList
                anchors.top: parent.bottom
                anchors.topMargin: Kirigami.Units.smallSpacing
                anchors.right: parent.right
                width: Kirigami.Units.gridUnit * 16
                spacing: Kirigami.Units.smallSpacing * 0.8

                opacity: lockScreenUi.notifExpanded ? 1.0 : 0.0
                visible: opacity > 0.01
                transform: Translate { y: -Kirigami.Units.gridUnit * (1 - notifList.opacity) }
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                Repeater {
                    model: notifModel
                    delegate: Rectangle {
                        width: notifList.width
                        height: cardCol.implicitHeight + Kirigami.Units.gridUnit
                        radius: Kirigami.Units.gridUnit * 0.6
                        color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                                       Kirigami.Theme.backgroundColor.g,
                                       Kirigami.Theme.backgroundColor.b, 0.62)
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                              Kirigami.Theme.textColor.g,
                                              Kirigami.Theme.textColor.b, 0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                            anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: Kirigami.Units.smallSpacing * 0.6
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                                // Remote icon URLs are blocked in the greeter;
                                // themed names and local paths are fine.
                                source: model.icon !== "" ? model.icon : "dialog-information"
                                fallback: "dialog-information"
                            }

                            ColumnLayout {
                                id: cardCol
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    Layout.fillWidth: true
                                    text: model.summary
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize - 1
                                    font.bold: true
                                    color: Kirigami.Theme.textColor
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: model.body !== ""
                                    text: model.body
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                    wrapMode: Text.WordWrap
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize - 2
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: Kirigami.Units.smallSpacing * 0.6
                                text: lockScreenUi.notifAge(model.time)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize - 3
                                color: Kirigami.Theme.disabledTextColor
                                opacity: 0.7
                            }
                        }
                    }
                }
            }
        }

        // Power menu — bottom-right power button that expands Sleep / Reboot /
        // Shut Down UPWARD through SessionManagement. Aligned to the same
        // baseline as the bottom pills so the two read as one row.
        Item {
            id: powerArea
            z: 5
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.bottomMargin: Kirigami.Units.gridUnit * 1.2
            anchors.rightMargin: Kirigami.Units.gridUnit * 1.5
            width: Kirigami.Units.gridUnit * 8
            height: powerBtn.height + (lockScreenUi.powerMenuOpen ? (powerMenuCol.implicitHeight + Kirigami.Units.smallSpacing) : 0)

            Rectangle {
                id: powerBtn
                // Pinned to the BOTTOM of powerArea: the area grows upward as the
                // menu opens, so the button must not move while it does.
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: Kirigami.Units.gridUnit * 2.2
                height: width
                radius: width / 2
                color: lockScreenUi.powerMenuOpen
                       ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.15)
                       : (powerBtnMa.containsMouse
                          ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                          : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.45))
                border.width: 1
                border.color: lockScreenUi.powerMenuOpen
                              ? Kirigami.Theme.negativeTextColor
                              : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    source: "system-shutdown"
                    isMask: true
                    color: lockScreenUi.powerMenuOpen ? Kirigami.Theme.negativeTextColor
                         : (powerBtnMa.containsMouse ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor)
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                MouseArea {
                    id: powerBtnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: lockScreenUi.powerMenuOpen = !lockScreenUi.powerMenuOpen
                }
            }

            ColumnLayout {
                id: powerMenuCol
                anchors.bottom: powerBtn.top
                anchors.bottomMargin: Kirigami.Units.smallSpacing
                anchors.right: parent.right
                spacing: Kirigami.Units.smallSpacing
                opacity: lockScreenUi.powerMenuOpen ? 1.0 : 0.0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 200 } }

                Repeater {
                    model: [
                        { label: "Sleep",     action: "suspend"  },
                        { label: "Reboot",    action: "reboot"   },
                        { label: "Shut Down", action: "shutdown" }
                    ]
                    delegate: Rectangle {
                        readonly property bool can: modelData.action === "suspend" ? sessionManagement.canSuspend
                                                  : modelData.action === "reboot" ? sessionManagement.canReboot
                                                  : sessionManagement.canShutdown
                        enabled: can
                        opacity: can ? 1.0 : 0.4
                        Layout.alignment: Qt.AlignRight
                        implicitWidth: Kirigami.Units.gridUnit * 7
                        implicitHeight: Kirigami.Units.gridUnit * 2
                        radius: Kirigami.Units.smallSpacing
                        color: entryMa.containsMouse
                               ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.10)
                               : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.4)
                        border.width: 1
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: "JetBrainsMono Nerd Font"
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                            color: entryMa.containsMouse ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            id: entryMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                lockScreenUi.powerMenuOpen = false;
                                // Skip the confirmation: it would open behind the lock.
                                if (modelData.action === "suspend") sessionManagement.suspend();
                                else if (modelData.action === "reboot") sessionManagement.requestReboot(SessionManagement.ConfirmationMode.Skip);
                                else sessionManagement.requestShutdown(SessionManagement.ConfirmationMode.Skip);
                            }
                        }
                    }
                }
            }
        }

        // Keyboard-layout reader for the bottom pill.
        PW.KeyboardLayoutSwitcher {
            id: kbSwitcher
            acceptedButtons: Qt.NoButton
        }

        // Bottom-center status pills (weather + keyboard layout) — serpantinum style.
        Row {
            id: bottomPills
            z: 3
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Kirigami.Units.gridUnit * 1.2
            spacing: Kirigami.Units.smallSpacing

            // Weather pill (frosted glass)
            Item {
                id: wPill
                visible: lockScreenUi.weatherTemp !== ""
                height: Kirigami.Units.gridUnit * 2.2
                width: wRow.implicitWidth + Kirigami.Units.gridUnit * 1.8

                ShaderEffectSource {
                    id: wGrab
                    anchors.fill: parent
                    sourceItem: wallpaper
                    sourceRect: Qt.rect(wPill.mapToItem(lockScreenRoot, 0, 0).x, wPill.mapToItem(lockScreenRoot, 0, 0).y, wPill.width, wPill.height)
                    visible: false
                }
                FastBlur {
                    anchors.fill: parent
                    source: wGrab
                    radius: 48
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: Rectangle { width: wPill.width; height: wPill.height; radius: height / 2 } }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.30)
                    border.width: 1
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
                }
                Row {
                    id: wRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: lockScreenUi.weatherIcon
                        font.family: "Iosevka Nerd Font"
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents3.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: lockScreenUi.weatherTemp
                        color: Kirigami.Theme.textColor
                    }
                }
            }

            // Now-playing media pill (middle) — a Repeater delegate per player, but
            // each hides itself unless it's actually Playing, so the Row skips it and
            // weather/keyboard close up when nothing's on. serpantinum has no media
            // widget; this is a small bonus that only shows while music plays.
            Repeater {
                model: Mpris.MultiplexerModel {}
                delegate: MediaControls {}
            }

            // Keyboard-layout pill (frosted; click to cycle when multiple layouts)
            Item {
                id: kPill
                visible: kbSwitcher.layoutNames.shortName !== ""
                height: Kirigami.Units.gridUnit * 2.2
                width: kbRow.implicitWidth + Kirigami.Units.gridUnit * 1.8

                ShaderEffectSource {
                    id: kGrab
                    anchors.fill: parent
                    sourceItem: wallpaper
                    sourceRect: Qt.rect(kPill.mapToItem(lockScreenRoot, 0, 0).x, kPill.mapToItem(lockScreenRoot, 0, 0).y, kPill.width, kPill.height)
                    visible: false
                }
                FastBlur {
                    anchors.fill: parent
                    source: kGrab
                    radius: 48
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: Rectangle { width: kPill.width; height: kPill.height; radius: height / 2 } }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: kbMa.containsMouse
                           ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                           : Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.30)
                    border.width: 1
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Row {
                    id: kbRow
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "input-keyboard"
                        isMask: true
                        color: Kirigami.Theme.textColor
                        width: Kirigami.Units.iconSizes.small
                        height: width
                    }
                    PlasmaComponents3.Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: kbSwitcher.layoutNames.shortName
                        color: Kirigami.Theme.textColor
                    }
                }
                MouseArea {
                    id: kbMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: kbSwitcher.hasMultipleKeyboardLayouts ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (kbSwitcher.hasMultipleKeyboardLayouts) kbSwitcher.keyboardLayout.switchToNextLayout()
                }
            }
        }

        // Note: Containment masks stretch clickable area of their buttons to
        // the screen edges, essentially making them adhere to Fitts's law.
        // Due to virtual keyboard button having an icon, buttons may have
        // different heights, so fillHeight is required.
        //
        // Note for contributors: Keep this in sync with SDDM Main.qml footer.
        RowLayout {
            id: footer
            visible: false   // desktop: virtual-keyboard/battery unused; layout moved to a bottom pill
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.smallSpacing
            }
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                id: virtualKeyboardButton

                focusPolicy: Qt.TabFocus
                text: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to show/hide virtual keyboard", "Virtual Keyboard")
                icon.name: inputPanel.keyboardActive ? "input-keyboard-virtual-on" : "input-keyboard-virtual-off"
                onClicked: {
                    // Otherwise the password field loses focus and virtual keyboard
                    // keystrokes get eaten
                    mainBlock.mainPasswordBox.forceActiveFocus();
                    inputPanel.showHide()
                }

                visible: inputPanel.status === Loader.Ready

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: virtualKeyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

            PlasmaComponents3.ToolButton {
                id: keyboardButton

                focusPolicy: Qt.TabFocus
                Accessible.description: i18ndc("plasma_shell_org.kde.plasma.desktop", "Button to change keyboard layout", "Switch layout")
                icon.name: "input-keyboard"

                PW.KeyboardLayoutSwitcher {
                    id: keyboardLayoutSwitcher

                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                }

                text: keyboardLayoutSwitcher.layoutNames.longName
                onClicked: keyboardLayoutSwitcher.keyboardLayout.switchToNextLayout()

                visible: keyboardLayoutSwitcher.hasMultipleKeyboardLayouts

                Layout.fillHeight: true
                containmentMask: Item {
                    parent: keyboardButton
                    anchors.fill: parent
                    anchors.leftMargin: virtualKeyboardButton.visible ? 0 : -footer.anchors.margins
                    anchors.bottomMargin: -footer.anchors.margins
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Battery {}
        }
    }
}
