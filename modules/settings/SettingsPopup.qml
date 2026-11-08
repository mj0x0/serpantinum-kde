// Settings in serpantinum v2's guide look (guide/GuidePopup.qml): a centred card, the
// sidebar with a gliding highlight, one page of card rows per tab, v2's own controls.

import "pages"
import "../../services/dnd"
import "../../services/reusables" as V2
import "../../services/layout"
import "../../services/polkit"
import "../../services/settings"
import "../../services/theme"
import "../../services/tray"
import "../../services/wallpaper"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

Item {
    id: window

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    MatugenColors { id: _theme }

    function s(v) { return scaler.s(v) }

    readonly property color base:     _theme.base
    readonly property color mantle:   _theme.mantle
    readonly property color crust:    _theme.crust
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color accent:   _theme.mauve

    // Accent roles offered as pickable tints.
    readonly property color mauve:    _theme.mauve
    readonly property color sapphire: _theme.sapphire
    readonly property color green:    _theme.green
    readonly property color yellow:   _theme.yellow
    readonly property color peach:    _theme.peach
    readonly property color pink:     _theme.pink
    readonly property color red:      _theme.red

    readonly property string fontFamily: Fonts.ui
    readonly property string glyphFamily: "Iosevka Nerd Font"

    // Nerd Font MDI glyphs keep a one-cell advance but ink past it, so centring the
    // advance box lands them right of centre. boundingRect IS the advance box (always
    // centred, i.e. no nudge at all) — the ink is tightBoundingRect.
    FontMetrics { id: glyphMetrics; font.family: window.glyphFamily; font.pixelSize: window.s(16) }
    function glyphNudge(g, px) {
        if (!g) return 0;
        var br = glyphMetrics.tightBoundingRect(g);
        var dx = glyphMetrics.advanceWidth(g) / 2 - (br.x + br.width / 2);
        return Math.round(dx * (px === undefined ? 1 : px / window.s(16)));
    }

    property int currentTab: 0

    // Deep link: SettingsState.section names a tab, matched case-insensitively.
    // A child tab only shows while its parent is the current page, or it is.
    function tabShown(i) {
        var t = window.tabs[i];
        if (!t || !t.under) return true;
        var cur = window.tabs[window.currentTab];
        // The whole group stays open while the parent or any sibling is current.
        return !!cur && (cur.name === t.under || cur.under === t.under);
    }
    function shownBefore(i) {
        var n = 0;
        for (var k = 0; k < i; k++) if (window.tabShown(k)) n++;
        return n;
    }
    function tabIsChild(i) {
        var t = window.tabs[i];
        return !!(t && t.under);
    }

    function tabIndexOf(name) {
        for (var i = 0; i < tabs.length; i++)
            if (tabs[i].name.toLowerCase() === ("" + name).toLowerCase()) return i;
        return -1;
    }
    function syncSection() {
        var i = tabIndexOf(SettingsState.section);
        if (i >= 0) currentTab = i;
    }
    Component.onCompleted: { syncSection(); intro.start(); }
    Connections {
        target: SettingsState
        function onSectionChanged() { window.syncSection() }
    }

    readonly property var tabs: [
        { name: "General",    icon: "\u{f0493}" },
        { name: "Appearance", icon: "\u{f0765}" },
        { name: "Bar",        icon: "\u{f0309}" },
        { name: "Modules",     icon: "\u{f12a8}", under: "Bar" },
        { name: "Tray",       icon: "\u{f0f1d}", under: "Bar" },
        { name: "Notifications", icon: "\u{f009a}" },
        { name: "Launcher",   icon: "\u{f0349}" },
        { name: "Dock",       icon: "\u{f10a9}" },
        { name: "On-Screen Display", icon: "\u{f057e}" },
        { name: "Wallpaper",  icon: "\u{f05e2}" },
        { name: "Capture",    icon: "\u{f0100}" },
        { name: "Text recognition", icon: "\u{f113d}", under: "Capture" },
        { name: "Recording",  icon: "\u{f0567}", under: "Capture" },
        { name: "Music",      icon: "\u{f075a}" },
        { name: "Calendar",   icon: "\u{f00ed}" },
        { name: "Weather",    icon: "\u{f0590}" },
        { name: "Network",    icon: "\u{f0317}" },
        { name: "System",     icon: "\u{f0ad1}" }
    ]

    // v2's guide intro: the card settles, the sidebar slides in, tabs stagger, content rises.
    property real introBase: 0
    property real introSidebar: 0
    property real introTabs: 0
    property real introContent: 0

    function tabProgress(i) {
        if (introTabs >= 1) return 1;
        if (introTabs <= 0) return 0;
        var p = Math.min(1, Math.max(0, (introTabs - i * 0.04) / 0.42));
        if (p <= 0) return 0;
        if (p >= 1) return 1;
        var c1 = 0.85, c3 = c1 + 1;
        return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2);
    }
    function tabOpacity(i) {
        if (introTabs >= 1) return 1;
        if (introTabs <= 0) return 0;
        return Math.min(1, Math.max(0, (introTabs - i * 0.04) / 0.28));
    }

    ParallelAnimation {
        id: intro
        NumberAnimation { target: window; property: "introBase"; from: 0; to: 1; duration: 650; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: window; property: "introSidebar"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTabs"; from: 0; to: 1; duration: 550 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: window; property: "introContent"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
        }
    }

    Item {
        anchors.fill: parent
        opacity: window.introBase
        scale: 0.95 + 0.05 * window.introBase

        Rectangle {
            anchors.fill: parent
            color: window.base
            radius: Radius.eased(window.s(18))
            border.color: window.surface0
            border.width: 1

            // --- sidebar ---
            Rectangle {
                id: sidebar
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: window.s(260)
                topLeftRadius: Radius.eased(window.s(18))
                bottomLeftRadius: Radius.eased(window.s(18))
                color: Qt.alpha(window.surface0, 0.4)
                opacity: window.introSidebar
                transform: Translate { x: window.s(-30) * (1.0 - window.introSidebar) }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(15)
                    spacing: window.s(10)

                Flickable {
                    id: tabsFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: tabsCol.implicitHeight + window.s(20)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    // One highlight glides between tabs instead of each tab colouring itself.
                    Rectangle {
                        z: 0
                        radius: Radius.outer(window.s(8))
                        color: window.accent
                        y: window.shownBefore(window.currentTab) * (window.s(44) + window.s(4))
                        x: window.tabIsChild(window.currentTab) ? window.s(16) : 0
                        width: tabsCol.width - x
                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                        height: window.s(44)
                        opacity: window.tabOpacity(window.currentTab)
                        transform: Translate { x: window.s(-24) * (1.0 - window.tabProgress(window.currentTab)) }
                        Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                    }

                    ColumnLayout {
                        id: tabsCol
                        width: tabsFlick.width
                        spacing: window.s(4)
                        z: 1

                        Repeater {
                            model: window.tabs
                            delegate: NavItem {
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: modelData.under ? window.s(16) : 0
                                visible: window.tabShown(index)
                                slot: index
                                label: modelData.name
                                glyph: modelData.icon
                                active: window.currentTab === index
                                onPicked: window.currentTab = index
                            }
                        }
                    }
                }

                NavItem {
                    Layout.fillWidth: true
                    slot: window.tabs.length
                    label: "Close"
                    hint: "Esc"
                    glyph: "\u{f0156}"
                    onPicked: SettingsState.hide()
                }
                }
            }

            // --- content ---
            Item {
                anchors.left: sidebar.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                anchors.topMargin: 4
                anchors.bottomMargin: 4
                opacity: window.introContent
                scale: 0.95 + 0.05 * window.introContent
                transform: Translate { y: window.s(20) * (1.0 - window.introContent) }

                StackLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(8)
                    currentIndex: window.currentTab

                    GeneralPage { host: window }
                    AppearancePage { host: window }
                    BarPage { host: window }
                    BarModulesPage { host: window }
                    TrayPage { host: window }
                    NotificationsPage { host: window }
                    LauncherPage { host: window }
                    DockPage { host: window }
                    OsdPage { host: window }
                    WallpaperPage { host: window }
                    CapturePage { host: window }
                    OcrPage { host: window }
                    RecordingPage { host: window }
                    MusicPage { host: window }
                    CalendarPage { host: window }
                    WeatherPage { host: window }
                    NetworkPage { host: window }
                    SystemPage { host: window }
                }
            }

        }
    }

    // --- building blocks (serpantinum v2's guide look on the same page API) ---

    component NavItem : Rectangle {
        id: nav
        property string label
        property string glyph
        property bool active: false
        property int slot: 0
        property string hint: ""
        signal picked()

        implicitHeight: window.s(44)
        radius: Radius.outer(window.s(8))
        color: navMa.containsMouse && !nav.active ? Qt.alpha(window.surface1, 0.5) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: navMa.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
        opacity: window.tabOpacity(nav.slot)
        transform: Translate { x: window.s(-24) * (1.0 - window.tabProgress(nav.slot)) }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: window.s(10) + (nav.active ? window.s(4) : 0)
            anchors.rightMargin: window.s(14)
            spacing: window.s(10)
            Behavior on anchors.leftMargin { NumberAnimation { duration: 400; easing.type: Easing.OutQuint } }

            V2.IconButton {
                enabled: false
                size: window.s(32)
                Layout.preferredWidth: window.s(32)
                Layout.preferredHeight: window.s(32)
                Layout.alignment: Qt.AlignVCenter
                cornerRadius: Radius.outer(window.s(8))
                buttonIcon: nav.glyph
                centerInk: true
                iconFontSize: window.s(16)
                accentColor: window.surface0
                textColor: window.text
            }
            Text {
                Layout.fillWidth: true
                text: nav.label
                font.family: window.fontFamily
                font.weight: nav.active ? Font.Bold : Font.Medium
                font.pixelSize: window.s(13)
                color: nav.active ? window.crust : (navMa.containsMouse ? window.text : window.subtext0)
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                visible: nav.hint !== ""
                text: nav.hint
                font.family: window.fontFamily
                font.pixelSize: window.s(10)
                color: window.overlay0
            }
        }
        MouseArea {
            id: navMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.picked()
        }
    }
}
