// Network panel chassis: theme, intro, card, header, power morph, tab bar, shortcuts.
// Tab bodies are loaded by URL (never registered in qmldir) so each tab is one file.

import "../../services/audio"
import "../../services/layout"
import "../../services/network"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: window

    Scaler {
        id: scaler
        currentWidth: Screen.width
        currentHeight: Screen.height
    }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base:     _theme.base
    readonly property color crust:    _theme.crust
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color accent:   window.tabAccent
    readonly property color red:      _theme.red
    readonly property color green:    _theme.green

    width: s(860)
    height: s(620)

    // --- Tabs ---------------------------------------------------------------
    // All four tabs always exist. Each tab renders its own "no hardware" plate, so
    // the bar never changes shape underfoot and absent hardware is visible, not inferred.
    readonly property var tabModel: [
        { key: "vpn",      glyph: "\u{f0582}", label: "VPN" },
        { key: "wifi",     glyph: "\u{f05a9}", label: "Wi-Fi" },
        { key: "ethernet", glyph: "\u{f0200}", label: "Ethernet" },
        { key: "servers",  glyph: "\u{f048d}", label: "Servers" }
    ]
    readonly property var tabOrder: tabModel.map(function (t) { return t.key; })
    // NetworkState owns the tab: PopupHost rebuilds the popup on every open, so a
    // popup-local one would reset to "vpn" and `ipc call network openTab` could not work.
    readonly property string activeTab: tabOrder.indexOf(NetworkState.tab) >= 0 ? NetworkState.tab : "vpn"

    // Not teal: matugen maps it onto the same role as green, which this tab spends on
    // "running", so the accent would say both things at once.
    readonly property color tabAccent: activeTab === "wifi" ? _theme.sapphire
                                     : activeTab === "ethernet" ? _theme.peach
                                     : activeTab === "servers" ? _theme.pink : _theme.blue

    function switchTab(k) {
        if (k === NetworkState.tab || window.tabOrder.indexOf(k) < 0) return;
        Sounds.playSfx("network/switch.wav");
        NetworkState.tab = k;
    }
    function cycleTab(d) {
        var order = window.tabOrder;
        if (order.length < 2) return;
        var i = order.indexOf(window.activeTab);
        switchTab(order[(i + d + order.length) % order.length]);
    }

    readonly property var activeTabItem: activeTab === "wifi" ? wifiLoader.item
                                       : activeTab === "ethernet" ? ethLoader.item
                                       : activeTab === "servers" ? serversLoader.item
                                       : vpnLoader.item

    // A focused password field owns the keyboard; Escape belongs to the popup host.
    readonly property bool typing: activeTabItem !== null && activeTabItem.textFocus === true

    Shortcut { sequence: "Tab"; enabled: !window.typing; onActivated: window.cycleTab(1) }
    Shortcut { sequences: ["Backtab", "Shift+Tab"]; enabled: !window.typing; onActivated: window.cycleTab(-1) }
    Shortcut { sequence: "1"; enabled: !window.typing; onActivated: window.switchTab("vpn") }
    Shortcut { sequence: "2"; enabled: !window.typing; onActivated: window.switchTab("wifi") }
    Shortcut { sequence: "3"; enabled: !window.typing; onActivated: window.switchTab("ethernet") }
    Shortcut { sequence: "4"; enabled: !window.typing; onActivated: window.switchTab("servers") }

    function handleEscape() {
        var it = window.activeTabItem;
        return !!(it && typeof it.handleEscape === "function" && it.handleEscape());
    }

    // setSource carries `popup` in at construction, so no tab binding ever sees it null.
    // A tab that fails to compile leaves item null and the Loader logs the reason itself.
    function ensureTab(loader, file) {
        if (loader.source.toString() !== "") return;
        loader.setSource(Qt.resolvedUrl(file), { popup: window, active: true });
    }
    function syncTabs() {
        if (activeTab === "wifi") ensureTab(wifiLoader, "WifiTab.qml");
        else if (activeTab === "ethernet") ensureTab(ethLoader, "EthernetTab.qml");
        else if (activeTab === "servers") ensureTab(serversLoader, "ServersTab.qml");
        else ensureTab(vpnLoader, "VpnTab.qml");
    }
    onActiveTabChanged: {
        window.powerAnimAllowed = false;
        powerAnimBlocker.restart();
        syncTabs();
    }
    Component.onCompleted: syncTabs()

    // The morph must not replay when the panel opens or when a tab switch flips power.
    property bool powerAnimAllowed: false
    Timer { id: powerAnimBlocker; interval: 250; running: true; onTriggered: window.powerAnimAllowed = true }

    // --- Ambient + intro ----------------------------------------------------
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 120000; loops: Animation.Infinite; running: true
    }
    property real introMain: 0
    NumberAnimation on introMain {
        from: 0; to: 1; duration: 600; easing.type: Easing.OutExpo; running: true
    }

    Rectangle {
        id: cardMask
        anchors.fill: parent
        radius: Radius.outer(s(20))
        color: "white"
        visible: false
        layer.enabled: true
    }

    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * introMain)
        opacity: introMain

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Radius.outer(s(20))
            color: window.base
            border.color: window.surface0
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
            }

            Rectangle {
                width: parent.width * 0.6; height: width; radius: width / 2
                x: (parent.width * 0.5 - width / 2) + Math.cos(window.globalOrbitAngle) * window.s(120)
                y: (parent.height * 0.5 - height / 2) + Math.sin(window.globalOrbitAngle) * window.s(90)
                color: window.accent
                opacity: 0.05
            }

            // --- Header ---------------------------------------------------
            RowLayout {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: window.s(24)
                spacing: window.s(12)

                Text {
                    text: (window.activeTabItem && window.activeTabItem.headerGlyph)
                          ? window.activeTabItem.headerGlyph : "\u{f0582}"
                    font.family: Fonts.icons
                    font.pixelSize: window.s(22)
                    color: (window.activeTabItem && window.activeTabItem.headerLit)
                           ? window.accent : window.overlay0
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
                Text {
                    Layout.fillWidth: true
                    text: "NETWORK"
                    font.family: Fonts.ui
                    font.weight: Font.Black
                    font.pixelSize: window.s(16)
                    color: window.text
                }

                Text {
                    text: window.activeTabItem ? (window.activeTabItem.headerStatus || "") : ""
                    font.family: Fonts.ui
                    font.pixelSize: window.s(10)
                    color: window.overlay0
                }
            }

            // --- Tab router -----------------------------------------------
            Item {
                id: orbitContainer
                anchors.top: header.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: footer.top
                anchors.margins: window.s(12)

                Loader {
                    id: vpnLoader
                    anchors.fill: parent
                    visible: opacity > 0.01
                    opacity: window.activeTab === "vpn" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Binding {
                        target: vpnLoader.item; property: "active"
                        value: window.activeTab === "vpn"; when: vpnLoader.item !== null
                    }
                }

                Loader {
                    id: wifiLoader
                    anchors.fill: parent
                    visible: opacity > 0.01
                    opacity: window.activeTab === "wifi" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Binding {
                        target: wifiLoader.item; property: "active"
                        value: window.activeTab === "wifi"; when: wifiLoader.item !== null
                    }
                    Binding {
                        target: wifiLoader.item; property: "coreHidden"
                        value: powerMorph.shown && powerMorph.morph < 0.5
                        when: wifiLoader.item !== null && wifiLoader.item.hasPower === true
                    }
                }

                Loader {
                    id: ethLoader
                    anchors.fill: parent
                    visible: opacity > 0.01
                    opacity: window.activeTab === "ethernet" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Binding {
                        target: ethLoader.item; property: "active"
                        value: window.activeTab === "ethernet"; when: ethLoader.item !== null
                    }
                    Binding {
                        target: ethLoader.item; property: "coreHidden"
                        value: powerMorph.shown && powerMorph.morph < 0.5
                        when: ethLoader.item !== null && ethLoader.item.hasPower === true
                    }
                }

                Loader {
                    id: serversLoader
                    anchors.fill: parent
                    visible: opacity > 0.01
                    opacity: window.activeTab === "servers" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Binding {
                        target: serversLoader.item; property: "active"
                        value: window.activeTab === "servers"; when: serversLoader.item !== null
                    }
                }
            }

            // --- Footer: tab bar --------------------------------------------
            Item {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: window.s(20)
                height: window.s(40)

                // Centred on the footer so it stays put whether or not the readout has content.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: tabRow.implicitWidth + window.s(8)
                    height: window.s(38)
                    radius: Radius.outer(window.s(12))
                    color: Qt.alpha(window.surface0, 0.6)

                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: window.s(4)

                        Repeater {
                            model: window.tabModel
                            delegate: Rectangle {
                                id: tabBtn
                                required property var modelData
                                readonly property bool isActive: window.activeTab === modelData.key
                                width: tabContent.implicitWidth + window.s(28)
                                height: window.s(30)
                                radius: Radius.outer(window.s(9))
                                color: tabBtn.isActive ? window.accent
                                     : (tabMa.containsMouse ? window.surface1 : "transparent")
                                Behavior on color { ColorAnimation { duration: 180 } }

                                // Upstream animates `scale` on its buttons too;
                                // the press dip is what makes a tab feel clicked.
                                scale: tabMa.pressed ? 0.94
                                     : (tabMa.containsMouse && !tabBtn.isActive ? 1.04 : 1.0)
                                Behavior on scale {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutBack }
                                }

                                Row {
                                    id: tabContent
                                    anchors.centerIn: parent
                                    spacing: window.s(7)
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tabBtn.modelData.glyph
                                        font.family: Fonts.icons
                                        font.pixelSize: window.s(15)
                                        color: tabBtn.isActive ? window.crust : window.subtext0
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tabBtn.modelData.label
                                        font.family: Fonts.ui
                                        font.weight: Font.Black
                                        font.pixelSize: window.s(13)
                                        color: tabBtn.isActive ? window.crust : window.text
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }
                                }

                                MouseArea {
                                    id: tabMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: window.switchTab(tabBtn.modelData.key)
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    // Only the DOCKED power button lands in this corner; off-tabs get the edge.
                    anchors.rightMargin: powerMorph.shown ? window.s(54) * powerMorph.morph : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: window.activeTabItem ? (window.activeTabItem.footerText || "") : ""
                    font.family: Fonts.ui
                    font.pixelSize: window.s(10)
                    color: window.overlay0
                }
            }

            // --- Power: v2's centre disc that morphs into a corner button ----
            Item {
                id: powerMorph
                z: 100

                readonly property var tabItem: window.activeTabItem
                readonly property bool on: tabItem !== null && tabItem.powerOn === true
                readonly property bool usable: tabItem !== null && tabItem.powerEnabled === true
                // A switch you cannot throw is noise; the tab's own plate says why it is absent.
                readonly property bool shown: tabItem !== null && tabItem.hasPower === true && (usable || on)
                // Tabs may expose powerPending; the Wi-Fi radio latch is the only one today.
                readonly property bool pending: (tabItem && tabItem.powerPending !== undefined)
                                              ? tabItem.powerPending === true
                                              : (window.activeTab === "wifi" && Net.radioPending)

                enabled: powerMorph.shown
                visible: opacity > 0.01
                opacity: powerMorph.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                property real morph: powerMorph.on ? 1 : 0
                Behavior on morph {
                    enabled: window.powerAnimAllowed
                    NumberAnimation { duration: 800; easing.type: Easing.InOutQuint }
                }

                readonly property real homeX: orbitContainer.x + orbitContainer.width / 2 - window.s(70)
                readonly property real homeY: orbitContainer.y + orbitContainer.height / 2 - window.s(70)
                readonly property real dockX: card.width - window.s(24) - window.s(42)
                readonly property real dockY: card.height - window.s(24) - window.s(42)

                width: window.s(140) + (window.s(42) - window.s(140)) * powerMorph.morph
                height: width
                x: powerMorph.homeX + (powerMorph.dockX - powerMorph.homeX) * powerMorph.morph
                y: powerMorph.homeY + (powerMorph.dockY - powerMorph.homeY) * powerMorph.morph

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: window.s(2)
                    anchors.bottomMargin: -window.s(2)
                    radius: width / 2
                    color: Qt.alpha(window.crust, 0.35)
                    z: -1
                }

                Rectangle {
                    id: powerFace
                    anchors.fill: parent
                    radius: width / 2

                    scale: powerMa.pressed ? 0.95 : (powerMa.containsMouse ? 1.05 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

                    color: powerMorph.on ? "transparent"
                         : (powerMa.containsMouse ? window.surface1 : window.surface0)
                    Behavior on color { ColorAnimation { duration: 200 } }

                    border.width: 1
                    border.color: powerMorph.pending ? window.accent
                                : powerMorph.on ? "transparent"
                                : (powerMa.containsMouse ? window.surface2 : window.surface1)
                    Behavior on border.color {
                        enabled: window.powerAnimAllowed
                        ColorAnimation { duration: 800; easing.type: Easing.InOutQuint }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: powerFace.radius
                        opacity: powerMorph.on ? 1 : 0
                        Behavior on opacity {
                            enabled: window.powerAnimAllowed
                            NumberAnimation { duration: 800; easing.type: Easing.InOutQuint }
                        }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.lighter(window.accent, 1.15) }
                            GradientStop { position: 1.0; color: window.accent }
                        }
                    }

                    Text {
                        id: powerIcon
                        anchors.centerIn: parent
                        font.family: Fonts.icons
                        font.pixelSize: window.s(54)
                        scale: 1.0 + ((20.0 / 54.0) - 1.0) * powerMorph.morph
                        color: powerMorph.on ? window.crust : window.subtext0
                        Behavior on color {
                            enabled: window.powerAnimAllowed
                            ColorAnimation { duration: 800; easing.type: Easing.InOutQuint }
                        }
                        text: powerMorph.pending ? "\u{f0772}"
                            : (powerMorph.tabItem && powerMorph.tabItem.powerGlyph)
                              ? powerMorph.tabItem.powerGlyph : "\u{f0425}"

                        RotationAnimation {
                            target: powerIcon
                            property: "rotation"
                            from: 0
                            to: 360
                            duration: 800
                            loops: Animation.Infinite
                            running: powerMorph.pending
                            onRunningChanged: if (!running) powerIcon.rotation = 0
                        }
                    }

                    MouseArea {
                        id: powerMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (powerMorph.usable) powerMorph.tabItem.togglePower()
                    }
                }
            }
        }
    }
}
