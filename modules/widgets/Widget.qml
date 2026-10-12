import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    color: "transparent"

    property string wId: Quickshell.env("QS_WIDGET_ID") || "preview"
    property string wType: "time"
    property string wVariant: ""
    property string wImagePath: ""
    property real wX: 0
    property real wY: 0
    property real wWidth: 250
    property real wHeight: 120
    property real wOpacity: 1.0
    property real wRotation: 0

    property var customProps: ({})

    // The 8px halo stays in the geometry; on KDE the selection outline lives in the redactor.
    readonly property real auraMargin: 8

    readonly property string safeMonitorName: ((root.screen && root.screen.name) ? root.screen.name : "default").replace(/[^a-zA-Z0-9_-]/g, "_")

    function applyCustomProps() {
        let it = faceLoader.item;
        if (!it || !customProps) return;
        let ignoredProps = [
            "objectName", "destroyed", "deleteLater", "parent", "data",
            "resources", "children", "visible", "enabled", "x", "y", "z",
            "width", "height", "opacity", "rotation", "scale"
        ];
        for (let k in customProps) {
            if (!k || typeof k !== "string") continue;
            if (k.endsWith("Changed") || k.startsWith("on") || typeof customProps[k] === "function" || customProps[k] === undefined) continue;
            if (ignoredProps.includes(k)) continue;
            try {
                if (it[k] !== undefined && it[k] !== customProps[k]) {
                    it[k] = customProps[k];
                }
            } catch (e) {}
        }
    }

    onCustomPropsChanged: applyCustomProps()

    property bool isRedacting: false
    property bool initialized: false

    property bool wantsKeyboardFocus: false
    readonly property bool effectiveKeyboardFocus: wantsKeyboardFocus || (faceLoader.item && (faceLoader.item.wantsKeyboardFocus || faceLoader.item.keyboardFocus || faceLoader.item.isEditingUser)) || false

    property real animX: wX
    property real animY: wY
    Behavior on animX {
        enabled: root.initialized && !root.isRedacting
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    Behavior on animY {
        enabled: root.initialized && !root.isRedacting
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    property real effectiveWidth: wWidth
    property real effectiveHeight: wHeight

    onWWidthChanged: updateEffectiveSize()
    onWHeightChanged: updateEffectiveSize()
    onWVariantChanged: updateEffectiveSize()
    onWTypeChanged: updateEffectiveSize()

    // KWin types a layer-shell surface by its namespace: as a desktop window the Slide effect moves it
    // with the wallpaper instead of painting it over the sliding windows (sticky normal windows go last).
    WlrLayershell.namespace: "desktop"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: effectiveKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore
    focusable: effectiveKeyboardFocus

    onEffectiveKeyboardFocusChanged: {
        if (effectiveKeyboardFocus && typeof root.requestActivate === "function") {
            root.requestActivate();
        }
    }

    anchors.top: true
    anchors.left: true
    margins.left: animX - root.auraMargin
    margins.top: animY - root.auraMargin

    implicitWidth: ((Math.round(wRotation || 0) % 180 === 0) ? effectiveWidth : effectiveHeight) + (root.auraMargin * 2)
    implicitHeight: ((Math.round(wRotation || 0) % 180 === 0) ? effectiveHeight : effectiveWidth) + (root.auraMargin * 2)

    Component.onCompleted: {
        Qt.callLater(() => {
            root.initialized = true;
        });
    }

    Component.onDestruction: {
        visible = false;
        faceLoader.active = false;
        faceLoader.source = "";
    }

    function updateEffectiveSize() {
        if (!faceLoader.item) {
            root.effectiveWidth = root.wWidth;
            root.effectiveHeight = root.wHeight;
            return;
        }
        let item = faceLoader.item;
        let c = {
            minW: item.minWidth !== undefined ? item.minWidth : 10,
            minH: item.minHeight !== undefined ? item.minHeight : 10,
            maxW: item.maxWidth !== undefined ? item.maxWidth : 9999,
            maxH: item.maxHeight !== undefined ? item.maxHeight : 9999,
            minA: item.minAspect !== undefined ? item.minAspect : 0,
            maxA: item.maxAspect !== undefined ? item.maxAspect : 9999
        };
        let w = Math.max(c.minW, Math.min(c.maxW, root.wWidth));
        let h = Math.max(c.minH, Math.min(c.maxH, root.wHeight));

        let ratio = w / h;
        if (ratio < c.minA && c.minA > 0) {
            let mA = c.minA;
            let hProj = (w * mA + h) / (mA * mA + 1);
            let hMin = Math.max(c.minH, c.minW / mA);
            let hMax = Math.min(c.maxH, c.maxW / mA);
            h = Math.max(hMin, Math.min(hMax, hProj));
            w = h * mA;
        } else if (ratio > c.maxA && c.maxA > 0) {
            let mA = c.maxA;
            let hProj = (w * mA + h) / (mA * mA + 1);
            let hMin = Math.max(c.minH, c.minW / mA);
            let hMax = Math.min(c.maxH, c.maxW / mA);
            h = Math.max(hMin, Math.min(hMax, hProj));
            w = h * mA;
        }

        w = Math.max(c.minW, Math.min(c.maxW, w));
        h = Math.max(c.minH, Math.min(c.maxH, h));

        root.effectiveWidth = w;
        root.effectiveHeight = h;
    }

    Loader {
        id: faceLoader
        property string wImagePath: root.wImagePath
        property string imagePath: root.wImagePath
        property string path: root.wImagePath
        visible: root.visible && !root.isRedacting
        source: WidgetRegistry.faceFile(root.wType, root.wVariant)
        width: root.effectiveWidth
        height: root.effectiveHeight
        anchors.centerIn: parent
        rotation: root.wRotation || 0
        opacity: root.wOpacity
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        onLoaded: {
            if (item) {
                try {
                    item.visible = Qt.binding(() => root.visible && !root.isRedacting);
                    if (item.imagePath !== undefined) {
                        item.imagePath = Qt.binding(() => root.wImagePath);
                    }
                    if (item.wImagePath !== undefined) {
                        item.wImagePath = Qt.binding(() => root.wImagePath);
                    }
                    if (item.path !== undefined) {
                        item.path = Qt.binding(() => root.wImagePath);
                    }
                    if (item.source !== undefined && typeof item.source === "string") {
                        item.source = Qt.binding(() => root.wImagePath);
                    }
                } catch (e) {}
            }
            root.applyCustomProps();
            root.updateEffectiveSize();
        }
    }

    MouseArea {
        id: widgetMenuArea
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        enabled: !root.isRedacting
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                WidgetSync.openRedactor(root.safeMonitorName, String(root.wId));
            }
        }
    }
}
