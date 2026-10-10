//@ pragma UseQApplication
//@ pragma Env QSG_RHI_BACKEND=vulkan
// NVIDIA's OpenGL path leaks per rendered frame under Wayland explicit sync; Vulkan does not.
// The one shell instance: bar, dock, launcher, popups, Floating, notifications,
// polkit and every IPC target. UseQApplication is required for the tray's context menus.

import "modules/bar"
import "modules/bluetooth"
import "modules/calendar"
import "modules/cheatsheet"
import "modules/clipboard"
import "modules/dock"
import "modules/floating"
import "modules/focustime"
import "modules/launcher"
import "modules/miniplayer"
import "modules/music"
import "modules/network"
import "modules/settings"
import "modules/traydrawer"
import "modules/traymenu"
import "modules/notifcenter"
import "modules/notifications"
import "modules/popups"
import "modules/power"
import "modules/volume"
import "modules/wallpaper"
import "modules/widgets"
import "services/dnd"
import "services/dock"
import "services/keepawake"
import "services/layout"
import "services/notifications"
import "services/polkit"
import "services/settings"
import "services/wallpaper"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    TopBar {}

    // The dock floats over windows on its edge without reserving space (macOS-style).
    // Anchored to one edge only, so the surface centres and stays click-through.
    // On the bar's edge it simply draws over the bar (user's call).
    PanelWindow {
        id: dockWindow

        anchors {
            top:    dock.position === "top"
            bottom: dock.position === "bottom"
            left:   dock.position === "left"
            right:  dock.position === "right"
        }
        exclusiveZone: 0

        WlrLayershell.layer: WlrLayershell.Top
        WlrLayershell.namespace: "quickshell-dock"
        color: "transparent"

        implicitWidth: dock.implicitWidth
        implicitHeight: dock.implicitHeight

        // Only the dock (revealed) or its thin edge strip (hidden) takes input.
        mask: Region { item: dock.maskItem }

        // Quickshell's parser rejects an inline Region {} as a ternary operand; use an id.
        BackgroundEffect.blurRegion: dock.frosted ? dockBlurRegion : null
        Region {
            id: dockBlurRegion
            item: dock.blurItem
            radius: dock.islandRadius
        }

        Dock {
            id: dock
            anchors.centerIn: parent
            panelWindow: dockWindow
        }

        // Published for Floating, which leaves the dock's span of its edge alone.
        readonly property real spanStart: {
            let scr = dockWindow.screen;
            if (!scr) return 0;
            return dock.vertical ? scr.y + Math.round((scr.height - dockWindow.height) / 2)
                                 : scr.x + Math.round((scr.width - dockWindow.width) / 2);
        }
        Binding { target: DockState; property: "position";  value: dock.position }
        Binding { target: DockState; property: "active";    value: dockWindow.visible }
        Binding { target: DockState; property: "screen";    value: dockWindow.screen }
        Binding { target: DockState; property: "start";     value: dockWindow.spanStart }
        Binding { target: DockState; property: "length";    value: dock.vertical ? dockWindow.height : dockWindow.width }
        Binding { target: DockState; property: "thickness"; value: dock.islandThickness }
    }

    // App launcher (ported serpantinum appLauncher on our AppSearchService).
    // Toggled by the TopBar Search button (LauncherState.toggle) or IPC.
    Launcher {}
    // Tray app menus drawn by the shell instead of Qt's native popup.
    TrayMenu {}
    // Every tray icon in one card, opened from the bar's tray button.
    TrayDrawer {}
    // The bar mini player's popout (hover or click the mini player).
    MiniPlayerPopout {}
    IpcHandler {
        target: "launcher"
        function toggle(): void { LauncherState.toggle() }
        function show(): void { LauncherState.show() }
        function hide(): void { LauncherState.hide() }
    }

    // qs -p <this file> ipc call settings toggle
    IpcHandler {
        target: "settings"
        function toggle(): void { SettingsState.toggle() }
        function show(): void { SettingsState.show("") }
        function open(name: string): void { SettingsState.show(name) }
        function hide(): void { SettingsState.hide() }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { WallpaperState.toggle() }
        function show(): void { WallpaperState.show() }
        function hide(): void { WallpaperState.hide() }
    }

    // Gated: a QML singleton is constructed on FIRST USE, so with this Loader inactive
    // nothing references PolkitService and KDE keeps the agent slot.
    Scaler {
        id: polkitScale
        currentWidth: Screen.width
        currentHeight: Screen.height
    }
    Loader {
        active: ShellSettings.polkitEnabled
        sourceComponent: Polkit { rootObj: polkitScale }
    }

    Notifications {}

    // Every popup lives in this one window and morphs between slots (modules/popups).
    // The per-feature IPC targets below still work; `main` is the v2-style front door.
    PopupHost {}
    IpcHandler {
        target: "main"
        // qs ipc call main handleCommand toggle calendar ""   (cmd: toggle|open|close)
        function handleCommand(cmd: string, target: string, arg: string): void {
            if (cmd === "close") Popups.hide();
            else if (cmd === "open") Popups.show(target, arg);
            else Popups.toggle(target, arg);
        }
        function hide(): void { Popups.hide() }
        function current(): string { return Popups.current }
    }

    // Toggle the notification center from a KDE global shortcut:
    //   qs -p <this file> ipc call notifcenter toggle
    IpcHandler {
        target: "notifcenter"
        function toggle(): void { NotifCenterState.toggle() }
        function show(): void { NotifCenterState.show() }
        function hide(): void { NotifCenterState.hide() }
        // Clears the on-screen toasts AND the centre's history in one go.
        function clearAll(): void { NotificationManager.clearAll() }
        // Recent notifications as JSON — read by the lock screen greeter, which
        // is a separate process and cannot see the model.
        function list(): string { return NotificationManager.recentJson() }
    }

    // Keep awake — holds a screen inhibition until switched off.
    //   qs -p <this file> ipc call keepawake toggle
    IpcHandler {
        target: "keepawake"
        function toggle(): void { KeepAwakeState.toggle() }
        function on(): void { KeepAwakeState.enable() }
        function off(): void { KeepAwakeState.disable() }
    }

    // Do Not Disturb — bind `qs ipc call dnd toggle` to a KDE global shortcut.
    //   forMinutes(30) → timed DND that auto-clears; on()/off() are indefinite.
    IpcHandler {
        target: "dnd"
        function toggle(): void { DndState.toggle() }
        function on(): void { DndState.enable() }
        function off(): void { DndState.disable() }
        function forMinutes(m: int): void { DndState.enableFor(m) }
    }

    // qs -p <this file> ipc call bluetooth toggle
    IpcHandler {
        target: "bluetooth"
        function toggle(): void { BluetoothState.toggle() }
        function show(): void { BluetoothState.show() }
        function hide(): void { BluetoothState.hide() }
    }

    // qs -p <this file> ipc call power toggle
    IpcHandler {
        target: "power"
        function toggle(): void { PowerState.toggle() }
        function show(): void { PowerState.show() }
        function hide(): void { PowerState.hide() }
    }

    // qs -p <this file> ipc call network toggle
    IpcHandler {
        target: "network"
        function toggle(): void { NetworkState.toggle() }
        function show(): void { NetworkState.show() }
        function hide(): void { NetworkState.hide() }
        function vpn(): void { NetworkState.toggleTab("vpn") }
        function wifi(): void { NetworkState.toggleTab("wifi") }
        function ethernet(): void { NetworkState.toggleTab("ethernet") }
        function servers(): void { NetworkState.toggleTab("servers") }
        // vpn | wifi | ethernet | servers — open on that tab without toggling
        function openTab(t: string): void { NetworkState.openTab(t) }
    }

    // qs -p <this file> ipc call tray toggle
    IpcHandler {
        target: "tray"
        function toggle(): void { TrayDrawerState.toggleAny() }
        function show(): void { if (!TrayDrawerState.open) TrayDrawerState.toggleAny() }
        function hide(): void { TrayDrawerState.hide() }
    }

    // qs -p <this file> ipc call cheatsheet toggle
    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { CheatsheetState.toggle() }
        function show(): void { CheatsheetState.show() }
        function hide(): void { CheatsheetState.hide() }
    }

    // qs -p <this file> ipc call clipboard toggle
    Clipboard {}
    IpcHandler {
        target: "clipboard"
        function toggle(): void { ClipboardState.toggle() }
        function show(): void { ClipboardState.show() }
        function hide(): void { ClipboardState.hide() }
    }

    // qs -p <this file> ipc call calendar toggle
    IpcHandler {
        target: "calendar"
        function toggle(): void { CalendarState.toggle() }
        function show(): void { CalendarState.show() }
        function hide(): void { CalendarState.hide() }
    }

    // qs -p <this file> ipc call volume toggle
    IpcHandler {
        target: "volume"
        function toggle(): void { VolumeState.toggle() }
        function show(): void { VolumeState.show() }
        function hide(): void { VolumeState.hide() }
        // outputs | inputs | apps
        function openTab(t: string): void { VolumeState.openTab(t) }
    }

    // qs -p <this file> ipc call music toggle
    IpcHandler {
        target: "music"
        function toggle(): void { MusicState.toggle() }
        function show(): void { MusicState.show() }
        function hide(): void { MusicState.hide() }
    }

    // Edge-reveal quick actions (SystemUsage / Timer / ColorPicker); IPC target `floating`.
    Floating {}

    // qs -p <this file> ipc call focustime toggle
    IpcHandler {
        target: "focustime"
        function toggle(): void { FocusTimeState.toggle() }
        function show(): void { FocusTimeState.show() }
        function hide(): void { FocusTimeState.hide() }
    }

    // Desktop widgets: one layer-shell window per widget, laid out by the redactor
    // (`ipc call redactor toggle`, or right-click a widget).
    WidgetRedactor {}
    Variants {
        model: Quickshell.screens
        delegate: WidgetLoader {
            required property var modelData
            screen: modelData
            monitorName: modelData.name
        }
    }
}
