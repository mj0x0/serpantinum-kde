// The toasts, serpantinum v2's notifications/NotificationPopups.qml on our stores:
// one full-height layer window masked to the stack, placed by notifications.position,
// clear of the bar on whichever edge it sits (BarState), silent under DND except critical.
import "../../services/bar"
import "../../services/dnd"
import "../../services/layout"
import "../../services/notifications"
import "../../services/settings"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popupWindow

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(val) { return scaler.s(val); }

    readonly property bool hasCriticalPopup: {
        let m = NotificationManager.popups;
        for (let i = 0; i < m.count; i++) {
            let p = m.get(i);
            if (p && p.urgency === 2) return true;
        }
        return false;
    }

    visible: (!DndState.enabled || hasCriticalPopup) && !NotificationManager.panelOpen
             && NotificationManager.popups.count > 0

    // top|bottom x left|center|right, or custom percentages.
    readonly property string position: "" + ShellSettings.value("notifications.position", "top right")
    readonly property real horizontalPosition: Number(ShellSettings.value("notifications.horizontalPosition", 95))
    readonly property real verticalPosition: Number(ShellSettings.value("notifications.verticalPosition", 5))
    readonly property bool isPreset: position !== "custom"
    readonly property bool isTop: position.indexOf("top") !== -1
    readonly property bool isBottom: position.indexOf("bottom") !== -1
    readonly property bool isCenter: position.indexOf("center") !== -1
    readonly property bool isLeft: position.indexOf("left") !== -1
    readonly property bool isRight: position.indexOf("right") !== -1 || (!isLeft && !isCenter)
    readonly property bool stackUpward: isPreset ? isBottom : (verticalPosition > 50)

    // The bar's own edge needs its clearance; the rest a sliver. Hidden = autohide or fullscreen.
    function edgeMargin(edge, fallback) {
        return (BarState.position === edge && !BarState.hidden) ? BarState.edgeGap : fallback;
    }

    WlrLayershell.namespace: "qs-popups"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: true
        bottom: true
        left: isPreset ? (popupWindow.isCenter || popupWindow.isLeft) : true
        right: isPreset ? (popupWindow.isCenter || popupWindow.isRight) : true
    }

    margins {
        top: isPreset ? popupWindow.edgeMargin("top", popupWindow.s(12)) : 0
        bottom: isPreset ? popupWindow.edgeMargin("bottom", popupWindow.s(12)) : 0
        left: isPreset ? (popupWindow.isLeft ? popupWindow.edgeMargin("left", popupWindow.s(16)) : 0) : 0
        right: isPreset ? (popupWindow.isRight ? popupWindow.edgeMargin("right", popupWindow.s(16)) : 0) : 0
    }

    exclusionMode: ExclusionMode.Ignore
    focusable: false
    color: "transparent"

    implicitWidth: s(350)

    mask: Region { item: popupContainer }

    Item {
        id: popupRoot
        anchors.fill: parent

        function s(val) { return popupWindow.s(val); }

        Item {
            id: popupContainer
            width: popupWindow.s(350)
            height: popupList.height

            x: popupWindow.isPreset
               ? (popupWindow.isCenter ? (popupWindow.width - width) / 2 : (popupWindow.isLeft ? 0 : (popupWindow.width - width)))
               : ((popupWindow.width - width) * (popupWindow.horizontalPosition / 100.0))
            y: popupWindow.isPreset
               ? (popupWindow.isTop ? 0 : (popupWindow.height - height))
               : ((popupWindow.height - height) * (popupWindow.verticalPosition / 100.0))

            // -1 left, 0 centre, 1 right: which way a toast slides in and out.
            readonly property int slideDir: popupWindow.isPreset
                ? (popupWindow.isCenter ? 0 : (popupWindow.isLeft ? -1 : 1))
                : (popupWindow.horizontalPosition < 33 ? -1 : (popupWindow.horizontalPosition > 66 ? 1 : 0))
            readonly property real slideY: popupWindow.isPreset
                ? (popupWindow.isCenter ? (popupWindow.isBottom ? popupWindow.s(24) : -popupWindow.s(24)) : 0)
                : (popupWindow.stackUpward ? popupWindow.s(24) : -popupWindow.s(24))

            ListView {
                id: popupList
                width: parent.width
                height: Math.min(popupWindow.height, contentHeight)
                verticalLayoutDirection: popupWindow.stackUpward ? ListView.BottomToTop : ListView.TopToBottom
                model: NotificationManager.popups
                spacing: popupWindow.s(12)
                interactive: false
                clip: false
                boundsBehavior: Flickable.StopAtBounds

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "x"; from: popupContainer.slideDir * popupWindow.s(350) * 0.35; to: 0; duration: 250; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "y"; from: popupContainer.slideY; to: 0; duration: 250; easing.type: Easing.OutCubic }
                    }
                }

                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0.0; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "x"; to: popupContainer.slideDir * popupWindow.s(350) * 0.35; duration: 200; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "y"; to: popupContainer.slideY; duration: 200; easing.type: Easing.OutCubic }
                    }
                }

                displaced: Transition {
                    NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
                }

                removeDisplaced: Transition {
                    NumberAnimation { property: "y"; duration: 220; easing.type: Easing.OutCubic }
                }

                delegate: Item {
                    id: delegateWrapper
                    width: ListView.view.width

                    // DND switched on mid-flight: everything but critical folds away.
                    property bool isSuppressedByDnd: DndState.enabled && model.urgency !== 2

                    implicitHeight: isSuppressedByDnd ? 0 : (typeLoader.item ? typeLoader.item.implicitHeight : popupWindow.s(70))
                    height: implicitHeight
                    visible: !isSuppressedByDnd

                    property int popupUid: model.uid
                    property var realNotif: NotificationManager.liveNotifs[popupUid] || model.notif || null
                    property bool isPopupContext: true
                    property var msgModel: model
                    property bool isExpanded: typeLoader.item && typeLoader.item.expanded && !typeLoader.item.autoExpanded ? true : false
                    property bool isHovered: typeLoader.item && typeLoader.item.isHovered ? true : false
                    property bool isDragging: typeLoader.item && typeLoader.item.isDragging ? true : false

                    property var actionArray: {
                        try { return model.actionsJson ? JSON.parse(model.actionsJson) : [] }
                        catch (e) { return [] }
                    }

                    // Critical never expires; otherwise the app's expireTimeout, else 5 s.
                    property int effectiveTimeout: {
                        if (model.urgency === 2) return 0;
                        var n = delegateWrapper.realNotif;
                        if (!n) return 5000;
                        var t = typeof n.expireTimeout === "number" ? n.expireTimeout : -1;
                        if (t === 0) return 0;
                        if (t > 0) return t;
                        return 5000;
                    }

                    // Pauses while hovered, expanded or dragged. Drops the toast only:
                    // the live object stays for the history card's actions.
                    Timer {
                        interval: delegateWrapper.effectiveTimeout > 0 ? delegateWrapper.effectiveTimeout : 5000
                        running: delegateWrapper.effectiveTimeout > 0 && !delegateWrapper.isHovered
                                 && !delegateWrapper.isExpanded && !delegateWrapper.isDragging
                        onTriggered: NotificationManager.removePopup(delegateWrapper.popupUid)
                    }

                    function removeThisNotif() { NotificationManager.removePopup(delegateWrapper.popupUid); }

                    Loader {
                        id: typeLoader
                        width: parent.width
                        source: {
                            let app = (model.appName || "").toLowerCase();
                            if (app === "weather") return "types/Weather.qml";
                            if (app === "screenshot" || app === "screen recorder" || app === "spectacle") return "types/Screenshot.qml";
                            return "types/Default.qml";
                        }
                        onLoaded: {
                            if (item) {
                                item.model = delegateWrapper.msgModel;
                                item.root = popupRoot;
                                item.delegateWrapper = delegateWrapper;
                            }
                        }
                    }
                }
            }
        }
    }
}
