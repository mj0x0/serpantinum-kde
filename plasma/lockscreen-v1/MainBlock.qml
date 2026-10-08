/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import "rpoly"
import "rpoly/material-shapes.js" as MaterialShapes
import QtQuick
import Qt5Compat.GraphicalEffects

import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kscreenlocker as ScreenLocker

import org.kde.breeze.components

SessionManagementScreen {
    id: sessionManager

    readonly property alias mainPasswordBox: passwordBox
    property bool lockScreenUiVisible: false
    property alias showPassword: passwordBox.showPassword

    // Red-border feedback on a failed unlock (matches the ring halo). The driving
    // Connections/Timer live INSIDE passwordBox — SessionManagementScreen's default
    // property only accepts visual Items, so non-Item children can't sit here.
    property bool failed: false

    //the y position that should be ensured visible when the on screen keyboard is visible
    property int visibleBoundary: mapFromItem(passwordBox, 0, 0).y
    onHeightChanged: visibleBoundary = mapFromItem(passwordBox, 0, 0).y + passwordBox.height + Kirigami.Units.smallSpacing
    /*
     * Login has been requested with the following username and password
     * If username field is visible, it will be taken from that, otherwise from the "name" property of the currentIndex
     */
    signal passwordResult(string password)

    onUserSelected: {
        // Escape is also wired to this signal, so don't startLogin() here.
        passwordBox.forceActiveFocus(Qt.TabFocusReason);
    }

    function startLogin() {
        const password = passwordBox.text

        // Move focus off the TextField before the app closes — works round a Qt
        // bug (QTBUG-55460). No login button anymore, so focus the screen root.
        sessionManager.forceActiveFocus();
        passwordResult(password);
    }

    // Horizontal block: avatar (left) + username / hint / password (right).
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        // --- Avatar (circular; ring turns red on a failed unlock) ---
        Item {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6

            Image {
                id: avatarImg
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                source: kscreenlocker_userImage !== "" ? "file://" + kscreenlocker_userImage : ""
                fillMode: Image.PreserveAspectCrop
                visible: false
                asynchronous: true
                sourceSize.width: width * Screen.devicePixelRatio
            }
            Rectangle { id: avatarMask; anchors.fill: avatarImg; radius: width / 2; visible: false }
            OpacityMask {
                anchors.fill: avatarImg
                source: avatarImg
                maskSource: avatarMask
                visible: avatarImg.status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: avatarImg
                anchors.margins: Kirigami.Units.gridUnit
                source: "user-identity"
                visible: avatarImg.status !== Image.Ready
            }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 3
                border.color: sessionManager.failed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
                Behavior on border.color { ColorAnimation { duration: 400 } }
            }
        }

        // --- Username / hint / password (right) ---
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: kscreenlocker_userName
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 4
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    source: "lock"
                    isMask: true
                    color: Kirigami.Theme.highlightColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents3.Label {
                    text: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "Enter password")
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }

            RowLayout {
                Layout.fillWidth: true

        PlasmaExtras.PasswordField {
            id: passwordBox
            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 3
            Layout.fillWidth: true
            text: PasswordSync.password

            // While masked, hide the native echo (we draw our own glyph bullets
            // below); revealing (eye button) shows the real text again.
            color: passwordBox.showPassword ? Kirigami.Theme.textColor : "transparent"

            // Chunkier pill field (vertical padding only — leave horizontal padding
            // to the component so the reveal-password button stays put).
            topPadding: Kirigami.Units.gridUnit
            bottomPadding: Kirigami.Units.gridUnit

            background: Rectangle {
                radius: height / 2
                color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.55)
                border.width: 2
                border.color: sessionManager.failed ? Kirigami.Theme.negativeTextColor
                            : (passwordBox.activeFocus ? Kirigami.Theme.highlightColor
                            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25))
                Behavior on border.color { ColorAnimation { duration: 300 } }
            }

            placeholderText: ""   // redundant — the "Enter password" hint sits right above
            focus: true
            enabled: !authenticator.graceLocked

            // In Qt this is implicitly active based on focus rather than visibility
            // in any other application having a focussed invisible object would be weird
            // but here we are using to wake out of screensaver mode
            // We need to explicitly disable cursor flashing to avoid unnecessary renders.
            // While masked we hide the native caret and draw our own after the glyphs.
            cursorVisible: visible && passwordBox.showPassword

            onAccepted: {
                if (sessionManager.lockScreenUiVisible) {
                    sessionManager.startLogin();
                }
            }

            //if empty and left or right is pressed change selection in user switch
            //this cannot be in keys.onLeftPressed as then it doesn't reach the password box
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left && !text) {
                    sessionManager.userList.decrementCurrentIndex();
                    event.accepted = true
                }
                if (event.key === Qt.Key_Right && !text) {
                    sessionManager.userList.incrementCurrentIndex();
                    event.accepted = true
                }
            }

            Connections {
                target: root
                function onClearPassword() {
                    passwordBox.forceActiveFocus()
                    passwordBox.text = "";
                    passwordBox.text = Qt.binding(() => PasswordSync.password);
                }
                function onNotificationRepeated() {
                    sessionManager.playHighlightAnimation();
                }
            }

            // Failure feedback (nested here so they're not direct children of
            // SessionManagementScreen, whose default property rejects non-Items).
            Connections {
                target: authenticator
                function onFailed(kind) { if (kind === 0) { sessionManager.failed = true; failResetTimer.restart(); } }
                function onSucceeded() { sessionManager.failed = false; }
            }
            Timer { id: failResetTimer; interval: 3000; onTriggered: sessionManager.failed = false }

            // Custom masked echo: render each typed character as a cycling
            // material-ish glyph that pops in (accent → text colour), emulating
            // end-4's PasswordChars. We can't import theirs (Quickshell/MaterialShape),
            // but it's just glyphs — plain Unicode symbols so nothing can tofu in
            // the greeter. Only active while masked; revealed mode shows real text.
            Item {
                id: glyphEcho
                visible: !passwordBox.showPassword
                clip: true
                anchors.left: parent.left
                anchors.leftMargin: passwordBox.leftPadding
                anchors.right: parent.right
                anchors.rightMargin: Kirigami.Units.gridUnit * 2.4   // clear the reveal eye
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height

                // Same 12-shape cycle as the polkit dialog's PasswordInput, so the
                // two auth surfaces match. Getters are stored, not results.
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

                // A Repeater on an int model REGENERATES every delegate when the
                // int changes, so each keystroke rebuilt every Canvas and replayed
                // every pop-in. Append/remove the difference instead, as the polkit
                // PasswordInput does, and existing shapes are left alone.
                ListModel { id: echoModel }
                readonly property int charCount: passwordBox.text.length
                onCharCountChanged: glyphEcho.syncEcho()
                Component.onCompleted: glyphEcho.syncEcho()

                function syncEcho() {
                    var n = glyphEcho.charCount;
                    while (echoModel.count > n) echoModel.remove(echoModel.count - 1);
                    while (echoModel.count < n) echoModel.append({ slot: echoModel.count });
                }
                readonly property real cell: Kirigami.Units.gridUnit * 0.9

                Row {
                    id: glyphRow
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Kirigami.Units.smallSpacing * 0.7

                    Repeater {
                        model: echoModel
                        delegate: Item {
                            id: cellItem
                            required property int index
                            width: glyphEcho.cell
                            height: glyphEcho.cell
                            opacity: 0
                            scale: 0.5

                            // Alternate where each glyph settles, accent then text.
                            readonly property color settleColor: (cellItem.index % 2 === 0)
                                ? Kirigami.Theme.highlightColor
                                : Kirigami.Theme.textColor

                            ShapeCanvas {
                                id: glyphShape
                                anchors.centerIn: parent
                                width: Math.round(glyphEcho.cell * 0.74)
                                height: width
                                roundedPolygon: glyphEcho.shapeFor(cellItem.index)
                                polygonIsNormalized: true
                                color: Kirigami.Theme.highlightColor
                                antialiasing: true
                            }

                            Component.onCompleted: popIn.start()
                            ParallelAnimation {
                                id: popIn
                                NumberAnimation { target: cellItem; property: "opacity"; to: 1.0; duration: 120 }
                                NumberAnimation { target: cellItem; property: "scale"; from: 0.5; to: 1.0; duration: 240; easing.type: Easing.OutBack }
                                ColorAnimation { target: glyphShape; property: "color"; from: Kirigami.Theme.highlightColor; to: cellItem.settleColor; duration: 900 }
                            }
                        }
                    }
                }

                // Blinking caret trailing the glyphs (native caret is off while masked).
                Rectangle {
                    id: echoCaret
                    visible: passwordBox.activeFocus
                    width: Math.max(2, Math.round(glyphEcho.cell * 0.12))
                    radius: width / 2
                    height: Math.round(glyphEcho.cell * 0.95)
                    anchors.verticalCenter: parent.verticalCenter
                    x: glyphRow.width + (passwordBox.text.length > 0 ? Kirigami.Units.smallSpacing * 0.7 : 0)
                    color: Kirigami.Theme.highlightColor
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
        Binding {
            target: PasswordSync
            property: "password"
            value: passwordBox.text
        }

            }  // inner RowLayout (password field; Enter submits — no button)
        }      // ColumnLayout (username / hint / password)
    }          // outer RowLayout (avatar | column)

    component FailableLabel : PlasmaComponents3.Label {
        id: _failableLabel
        required property int kind
        required property string label

        visible: authenticator.authenticatorTypes & kind
        text: label
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        Layout.fillWidth: true

        RejectPasswordAnimation {
            id: _rejectAnimation
            target: _failableLabel
            onFinished: _timer.restart()
        }

        Connections {
            target: authenticator
            function onNoninteractiveError(kind, authenticator) {
                if (kind & _failableLabel.kind) {
                    _failableLabel.text = Qt.binding(() => authenticator.errorMessage)
                    _rejectAnimation.start()
                }
            }
        }
        Timer {
            id: _timer
            interval: Kirigami.Units.humanMoment
            onTriggered: {
                _failableLabel.text = Qt.binding(() => _failableLabel.label)
            }
        }
    }

    FailableLabel {
        kind: ScreenLocker.Authenticator.Fingerprint
        label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your fingerprint on the reader)")
    }
    FailableLabel {
        kind: ScreenLocker.Authenticator.Smartcard
        label: i18ndc("plasma_shell_org.kde.plasma.desktop", "@info:usagetip", "(or scan your smartcard)")
    }
}
