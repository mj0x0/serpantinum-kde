// serpantinum v2's grouped notification list (reusables/NotificationBox.qml) on our
// NotificationManager: stacked group headers with a count badge, swipe to dismiss a
// group, staggered clear sweep, DND button, mascot empty state.
import "../dnd"
import "../layout"
import "../notifications"
import "../settings"
import "../shims"
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

Item {
    id: root
    implicitWidth: 320
    implicitHeight: 300

    function s(val) {
        return (rootContext && typeof rootContext.s === "function") ? rootContext.s(val) : val;
    }

    property var rootContext: null
    property real cornerRadius: Math.min(ThemeBackend.borderRadius, root.s(20))
    property real cardRadius: Math.min(ThemeBackend.borderRadius, root.s(14))
    property color baseColor: Qt.darker(ThemeBackend.surface0, 1.04)
    property color borderColor: "transparent"
    property real borderWidth: 0
    property bool hasShadow: false
    property color shadowColor: Qt.rgba(0, 0, 0, 0.22)
    property real emptyGraphicSize: root.s(148)
    property real contentMargins: root.s(12)
    property string titleText: "Notifications"

    readonly property bool dndEnabled: DndState.enabled
    readonly property bool showEmptyGraphic: ShellSettings.value("notifications.showEmptyGraphic", true) !== false

    property bool isClearingNotifs: false

    // Keyboard selection over the top-level rows (a card, or an app's group), driven by the System Panel.
    property bool keyActive: false
    property int keyIndex: -1
    readonly property Item keyItem: keyIndex >= 0 ? notifList.itemAtIndex(keyIndex) : null
    onKeyActiveChanged: if (keyActive) selectFirst()

    function selectFirst() {
        if (keyIndex < 0 && notifList.count > 0) { keyIndex = 0; notifList.positionViewAtIndex(0, ListView.Contain); }
    }
    function moveSelection(step) {
        let n = notifList.count;
        if (n === 0) { keyIndex = -1; return; }
        keyIndex = keyIndex < 0 ? (step > 0 ? 0 : n - 1) : Math.max(0, Math.min(n - 1, keyIndex + step));
        notifList.positionViewAtIndex(keyIndex, ListView.Contain);
    }
    function setSelectedExpanded(open) {
        let it = keyItem;
        if (!it || it.isSingle) return;
        it.isExpanded = open;
        if (open) NotificationManager.markGroupRead(it.gKey);
    }
    function activateSelected() {
        let it = keyItem;
        if (!it) { selectFirst(); return; }
        if (it.isSingle) it.invokeDefault();
        else setSelectedExpanded(!it.isExpanded);
    }
    // Never deletes blind: with nothing selected yet, the first press only selects.
    function dismissSelected() {
        let it = keyItem;
        if (!it) { selectFirst(); return; }
        if (it.isSingle) it.dismissSingle();
        else NotificationManager.dismissGroup(it.gKey);
    }

    function clearAllNotifs() {
        NotificationManager.clearAll();
    }

    Timer {
        id: clearFinishTimer
        interval: 300
        repeat: false
        onTriggered: {
            root.clearAllNotifs();
            root.isClearingNotifs = false;
        }
    }

    function animateClear() {
        if (root.isClearingNotifs || !NotificationManager.groupedHistory || NotificationManager.groupedHistory.count === 0) return;
        root.isClearingNotifs = true;

        let visibleDelegates = [];
        for (let i = 0; i < notifList.contentItem.children.length; i++) {
            let child = notifList.contentItem.children[i];
            if (child && typeof child.triggerClearSlide === "function") {
                if (child.y + child.height >= notifList.contentY && child.y <= notifList.contentY + notifList.height) {
                    visibleDelegates.push(child);
                }
            }
        }

        visibleDelegates.sort((a, b) => a.y - b.y);

        if (visibleDelegates.length === 0) {
            root.clearAllNotifs();
            root.isClearingNotifs = false;
            return;
        }

        let step = 50;
        let totalTime = 0;
        for (let i = 0; i < visibleDelegates.length; i++) {
            let d = i * step;
            visibleDelegates[i].triggerClearSlide(d);
            totalTime = d + 220;
        }

        clearFinishTimer.interval = totalTime + 40;
        clearFinishTimer.start();
    }

    Rectangle {
        id: shadowRect
        anchors.fill: parent
        anchors.topMargin: root.s(2)
        anchors.bottomMargin: -root.s(2)
        radius: root.cornerRadius
        color: root.shadowColor
        visible: root.hasShadow
    }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.baseColor
        border.color: root.borderColor
        border.width: root.borderWidth
        clip: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.contentMargins
        spacing: root.s(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(8)

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: root.s(4)
                text: root.titleText
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: root.s(12)
                color: ThemeBackend.subtext0
            }

            Item { Layout.fillWidth: true }

            ClickButton {
                id: clearBtn
                Layout.preferredWidth: root.s(80)
                Layout.preferredHeight: root.s(32)
                horizontalPadding: root.s(10)
                cornerRadius: Radius.inner(root.s(10), root.s(16))
                buttonText: "Clear"
                textFontSize: root.s(11)
                buttonIcon: "󰅖"
                iconFontSize: root.s(14)
                accentColor: ThemeBackend.surface1
                textColor: ThemeBackend.text
                visible: NotificationManager.groupedHistory && NotificationManager.groupedHistory.count > 0
                enabled: !root.isClearingNotifs

                onTriggered: {
                    root.animateClear();
                }
            }

            ClickButton {
                id: dndBtn
                Layout.preferredWidth: root.s(86)
                Layout.preferredHeight: root.s(32)
                horizontalPadding: root.s(10)
                cornerRadius: Radius.inner(root.s(10), root.s(16))
                buttonText: root.dndEnabled ? "Silent" : "Mute"
                textFontSize: root.s(11)
                buttonIcon: root.dndEnabled ? "󰂛" : "󰂚"
                iconFontSize: root.s(14)
                accentColor: root.dndEnabled ? ThemeBackend.blue : ThemeBackend.surface1
                textColor: root.dndEnabled ? ThemeBackend.crust : ThemeBackend.text

                onTriggered: DndState.toggle()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: root.s(8)
                visible: !NotificationManager.groupedHistory || NotificationManager.groupedHistory.count === 0

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: root.showEmptyGraphic ? root.emptyGraphicSize : root.s(48)
                    Layout.preferredHeight: root.showEmptyGraphic ? root.emptyGraphicSize : root.s(48)
                    visible: true

                    ImageBox {
                        id: pushyImg
                        anchors.fill: parent
                        size: root.emptyGraphicSize
                        cornerRadius: root.s(0)
                        imageRadius: root.s(0)
                        source: Qt.resolvedUrl("assets/pushy.gif")
                        isGif: true
                        playing: true
                        fillMode: Image.PreserveAspectFit
                        interactive: false
                        visible: root.showEmptyGraphic
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.showEmptyGraphic
                        text: "󰂚"
                        font.family: "Iosevka Nerd Font"
                        font.pixelSize: root.s(40)
                        color: ThemeBackend.surface2
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "All caught up"
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Medium
                    font.pixelSize: root.s(12)
                    color: ThemeBackend.overlay0
                }
            }

            ListView {
                id: notifList
                anchors.fill: parent
                onCountChanged: if (root.keyIndex >= count) root.keyIndex = count - 1
                model: NotificationManager.groupedHistory
                spacing: root.s(12)
                clip: true
                interactive: !root.isClearingNotifs && (contentHeight > height)
                boundsBehavior: Flickable.StopAtBounds

                add: Transition {
                    NumberAnimation { property: "scale"; from: 0.96; to: 1.0; duration: 250; easing.type: Easing.OutQuint }
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutQuint }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0.0; duration: 200; easing.type: Easing.OutQuint }
                }

                delegate: Item {
                    id: groupWrapper
                    width: ListView.view ? ListView.view.width : 0
                    height: isSingle ? (singleNotifLoader.item ? singleNotifLoader.item.implicitHeight : 0) : groupTransformItem.implicitHeight
                    implicitHeight: height

                    property var memberList: []
                    property string currentItemsJson: typeof itemsJson !== "undefined" ? itemsJson : "[]"

                    property string customType: {
                        let appn = "";
                        if (memberList && memberList.length > 0 && memberList[0] && memberList[0].appName) {
                            appn = memberList[0].appName;
                        } else if (typeof displayName !== "undefined" && displayName) {
                            appn = displayName;
                        }
                        let app = (appn || "").toLowerCase().trim();
                        if (app === "weather") return "weather";
                        if (app === "screenshot" || app === "screen recorder" || app === "spectacle") return "screenshot";
                        return "default";
                    }

                    onCurrentItemsJsonChanged: {
                        let arr = [];
                        try { arr = JSON.parse(currentItemsJson); } catch(e) {}
                        
                        let canReuse = (arr.length === memberList.length);
                        if (canReuse) {
                            for (let i = 0; i < arr.length; i++) {
                                if (arr[i].uid !== memberList[i].uid) { canReuse = false; break; }
                            }
                        }

                        if (canReuse) {
                            if (isSingle && singleNotifLoader.item && typeof singleNotifLoader.item.forceRead === "function") {
                                singleNotifLoader.item.forceRead(arr[0].read);
                            } else if (!isSingle && typeof memberRepeater !== "undefined") {
                                for (let i = 0; i < memberRepeater.count; i++) {
                                    let loader = memberRepeater.itemAt(i);
                                    if (loader && loader.item && typeof loader.item.forceRead === "function") {
                                        loader.item.forceRead(arr[i].read);
                                    }
                                }
                            }
                        } else {
                            memberList = arr;
                        }
                    }

                    Component.onCompleted: {
                        let arr = [];
                        try { arr = JSON.parse(currentItemsJson); } catch(e) {}
                        memberList = arr;
                    }

                    property int memberCount: typeof count !== "undefined" ? count : memberList.length
                    property bool isSingle: memberCount === 1
                    property bool isExpanded: false
                    property real groupExpandProgress: isExpanded ? 1.0 : 0.0
                    Behavior on groupExpandProgress {
                        enabled: !groupHeaderMa.draggingV
                        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }

                    property real dragX: 0
                    property real dragY: 0
                    property bool isDismissing: false

                    readonly property string gKey: typeof groupKey !== "undefined" ? groupKey : ""
                    function dismissSingle() { singleDelegateWrapper.removeThisNotif(); }
                    function invokeDefault() {
                        let d = memberList.length > 0 ? memberList[0] : null;
                        if (d && d.uid !== undefined) NotificationManager.markAsRead(d.uid);
                        let n = singleDelegateWrapper.realNotif;
                        if (!n || !n.actions || n.actions.length === 0) return;
                        let a = n.actions[0];
                        for (let i = 0; i < n.actions.length; i++) {
                            if (n.actions[i].identifier === "default") { a = n.actions[i]; break; }
                        }
                        a.invoke();
                    }

                    Rectangle {
                        z: 100
                        anchors.fill: parent
                        visible: root.keyActive && index === root.keyIndex
                        color: "transparent"
                        radius: ThemeBackend.borderRadius
                        border.width: root.s(2)
                        border.color: ThemeBackend.text
                    }

                    property real clearDelay: 0
                    NumberAnimation {
                        id: clearSlideAnim
                        target: groupWrapper
                        property: "dragX"
                        to: notifList.width * 1.2
                        duration: 220
                        easing.type: Easing.OutQuad
                    }
                    Timer {
                        id: clearSlideTimer
                        interval: groupWrapper.clearDelay
                        onTriggered: clearSlideAnim.start()
                    }
                    function triggerClearSlide(delayMs) {
                        clearDelay = delayMs;
                        clearSlideTimer.start();
                    }

                    transform: Translate {
                        x: groupWrapper.dragX
                        y: groupWrapper.dragY
                    }
                    opacity: Math.max(0.0, 1.0 - (Math.abs(groupWrapper.dragX) / (groupWrapper.width * 0.75)))

                    NumberAnimation {
                        id: groupResetAnim
                        target: groupWrapper
                        property: "dragX"
                        from: groupWrapper.dragX
                        to: 0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        id: groupResetAnimY
                        target: groupWrapper
                        property: "dragY"
                        from: groupWrapper.dragY
                        to: 0
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        id: groupDismissAnim
                        target: groupWrapper
                        property: "dragX"
                        from: groupWrapper.dragX
                        to: 0
                        duration: 200
                        easing.type: Easing.OutQuad
                        onFinished: NotificationManager.dismissGroup(groupKey)
                    }

                    QtObject {
                        id: singleDelegateWrapper
                        property var nData: memberList.length > 0 ? memberList[0] : null
                        property var nUid: nData && nData.uid !== undefined ? nData.uid : -1
                        property var realNotif: NotificationManager.liveNotifs && nUid !== -1 ? NotificationManager.liveNotifs[nUid] : null
                        property bool isPopupContext: false
                        property var actionArray: {
                            try {
                                let aj = nData ? nData.actionsJson : "";
                                return aj ? JSON.parse(aj) : [];
                            } catch (e) {
                                return [];
                            }
                        }
                        function removeThisNotif() {
                            if (nUid !== -1) {
                                NotificationManager.dismissNotification(nUid);
                            }
                        }
                    }

                    Loader {
                        id: singleNotifLoader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        visible: isSingle
                        active: isSingle
                        source: {
                            if (!isSingle) return "";
                            let nData = memberList.length > 0 ? memberList[0] : null;
                            let appn = nData ? (nData.appName || "") : (displayName || "");
                            let app = appn.toLowerCase().trim();
                            if (app === "weather") return "../../modules/notifications/types/Weather.qml";
                            if (app === "screenshot" || app === "screen recorder" || app === "spectacle") return "../../modules/notifications/types/Screenshot.qml";
                            return "../../modules/notifications/types/Default.qml";
                        }
                        onLoaded: {
                            if (item) {
                                item.root = root.rootContext ? root.rootContext : root;
                                item.delegateWrapper = singleDelegateWrapper;
                                item.model = memberList.length > 0 ? memberList[0] : null;
                                if (item.hasOwnProperty("showIcon")) item.showIcon = true;
                            }
                        }
                    }

                    Binding {
                        target: singleNotifLoader.item
                        property: "model"
                        value: memberList.length > 0 ? memberList[0] : null
                        when: singleNotifLoader.item !== null
                    }

                    Item {
                        id: groupTransformItem
                        visible: !isSingle
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: groupCol.implicitHeight
                        Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            id: groupCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            spacing: root.s(8)

                            Item {
                                id: groupHeaderWrapper
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(60)

                                Rectangle {
                                    id: groupUnderShadow
                                    visible: !groupWrapper.isExpanded && groupWrapper.memberCount > 1
                                    anchors.fill: groupHeaderCard
                                    anchors.topMargin: root.s(1.5)
                                    anchors.bottomMargin: -root.s(1.5)
                                    radius: root.cardRadius
                                    color: Qt.rgba(0, 0, 0, 0.15)
                                    z: -2
                                    opacity: Math.max(0.0, 1.0 - groupWrapper.groupExpandProgress * 2.0)
                                }

                                Rectangle {
                                    id: stackCard1
                                    visible: !groupWrapper.isExpanded && groupWrapper.memberCount > 1
                                    anchors.left: groupHeaderCard.left
                                    anchors.right: groupHeaderCard.right
                                    anchors.top: groupHeaderCard.top
                                    anchors.leftMargin: root.s(4)
                                    anchors.rightMargin: root.s(4)
                                    anchors.topMargin: root.s(4)
                                    height: groupHeaderCard.height
                                    radius: root.cardRadius
                                    color: Qt.darker(ThemeBackend.surface1, 1.08)
                                    z: -1
                                    opacity: Math.max(0.0, 1.0 - groupWrapper.groupExpandProgress * 2.0)
                                }

                                Rectangle {
                                    id: groupCardShadow
                                    anchors.fill: groupHeaderCard
                                    anchors.topMargin: Math.max(0, groupWrapper.dragY * 0.4)
                                    anchors.bottomMargin: -Math.max(0, groupWrapper.dragY * 0.4)
                                    radius: root.cardRadius
                                    color: Qt.rgba(0, 0, 0, Math.min(0.18, Math.max(0, groupWrapper.dragY / root.s(3.5)) * 0.18))
                                    visible: groupWrapper.dragY > 0
                                    z: -1
                                }

                                Rectangle {
                                    id: groupHeaderCard
                                    anchors.fill: parent
                                    radius: root.cardRadius
                                    property color baseColor: (typeof unreadCount !== "undefined" && unreadCount > 0) ? Qt.lighter(ThemeBackend.surface1, 1.05) : ThemeBackend.surface1
                                    color: (groupHeaderMa.pressed && !groupHeaderMa.draggingH && !groupHeaderMa.draggingV) ? Qt.darker(baseColor, 1.1) : (groupHeaderMa.containsMouse && !groupHeaderMa.draggingH && !groupHeaderMa.draggingV ? Qt.lighter(baseColor, 1.05) : baseColor)
                                    scale: (groupHeaderMa.pressed && !groupHeaderMa.draggingH && !groupHeaderMa.draggingV) ? 0.98 : 1.0
                                    Behavior on color { enabled: !groupHeaderMa.draggingH && !groupHeaderMa.draggingV; ColorAnimation { duration: 150 } }
                                    Behavior on scale { enabled: !groupHeaderMa.draggingH && !groupHeaderMa.draggingV; NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
                                    clip: true

                                    MouseArea {
                                        id: groupHeaderMa
                                        anchors.fill: parent
                                        z: 0
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        acceptedButtons: Qt.LeftButton
                                        property real startRootX: 0
                                        property real startRootY: 0
                                        property bool draggingH: false
                                        property bool draggingV: false

                                        onPressed: (mouse) => {
                                            let pt = mapToItem(root, mouse.x, mouse.y);
                                            startRootX = pt.x;
                                            startRootY = pt.y;
                                            draggingH = false;
                                            draggingV = false;
                                            groupResetAnim.stop();
                                            groupResetAnimY.stop();
                                        }

                                        onPositionChanged: (mouse) => {
                                            if (!pressed) return;
                                            let pt = mapToItem(root, mouse.x, mouse.y);
                                            let dx = pt.x - startRootX;
                                            let dy = pt.y - startRootY;

                                            if (!draggingH && !draggingV) {
                                                if (Math.abs(dx) > root.s(6) && Math.abs(dx) > Math.abs(dy)) {
                                                    draggingH = true;
                                                    groupHeaderMa.preventStealing = true;
                                                } else if (Math.abs(dy) > root.s(6) && Math.abs(dy) >= Math.abs(dx)) {
                                                    draggingV = true;
                                                    groupHeaderMa.preventStealing = true;
                                                }
                                            }

                                            if (draggingH) {
                                                groupWrapper.dragX = dx;
                                            } else if (draggingV) {
                                                groupWrapper.dragY = dy > 0 ? Math.min(root.s(3.5), Math.sqrt(dy) * root.s(0.5)) : 0;
                                                let targetProg = groupWrapper.isExpanded ? Math.max(0.0, Math.min(1.0, 1.0 + (dy / root.s(90)))) : Math.max(0.0, Math.min(1.0, dy / root.s(90)));
                                                groupWrapper.groupExpandProgress = targetProg;
                                            }
                                        }

                                        onReleased: (mouse) => {
                                            groupHeaderMa.preventStealing = false;
                                            if (draggingH) {
                                                let threshold = groupHeaderCard.width * 0.18;
                                                if (Math.abs(groupWrapper.dragX) > threshold) {
                                                    groupWrapper.isDismissing = true;
                                                    groupDismissAnim.from = groupWrapper.dragX;
                                                    groupDismissAnim.to = groupWrapper.dragX > 0 ? groupHeaderCard.width * 1.2 : -groupHeaderCard.width * 1.2;
                                                    groupDismissAnim.start();
                                                } else {
                                                    groupResetAnim.from = groupWrapper.dragX;
                                                    groupResetAnim.start();
                                                }
                                                draggingH = false;
                                            } else if (draggingV) {
                                                groupResetAnimY.from = groupWrapper.dragY;
                                                groupResetAnimY.start();
                                                if (!groupWrapper.isExpanded && groupWrapper.groupExpandProgress > 0.35) {
                                                    groupWrapper.isExpanded = true;
                                                    NotificationManager.markGroupRead(groupKey);
                                                } else if (groupWrapper.isExpanded && groupWrapper.groupExpandProgress < 0.65) {
                                                    groupWrapper.isExpanded = false;
                                                }
                                                groupWrapper.groupExpandProgress = Qt.binding(() => groupWrapper.isExpanded ? 1.0 : 0.0);
                                                draggingV = false;
                                            } else {
                                                groupWrapper.isExpanded = !groupWrapper.isExpanded;
                                                groupWrapper.groupExpandProgress = Qt.binding(() => groupWrapper.isExpanded ? 1.0 : 0.0);
                                                if (groupWrapper.isExpanded) {
                                                    NotificationManager.markGroupRead(groupKey);
                                                }
                                            }
                                        }

                                        onCanceled: {
                                            groupHeaderMa.preventStealing = false;
                                            if (draggingH) {
                                                groupResetAnim.from = groupWrapper.dragX;
                                                groupResetAnim.start();
                                                draggingH = false;
                                            }
                                            if (draggingV) {
                                                groupResetAnimY.from = groupWrapper.dragY;
                                                groupResetAnimY.start();
                                                groupWrapper.groupExpandProgress = Qt.binding(() => groupWrapper.isExpanded ? 1.0 : 0.0);
                                                draggingV = false;
                                            }
                                        }
                                    }

                                    RowLayout {
                                        z: 1
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: root.s(10)
                                        anchors.rightMargin: root.s(10)
                                        spacing: root.s(10)

                                        Item {
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredWidth: root.s(40)
                                            Layout.preferredHeight: root.s(40)

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: Radius.inner(root.s(10), root.s(20))
                                                color: ThemeBackend.surface2
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.margins: root.s(5)
                                                radius: Math.max(0, Radius.inner(root.s(10), root.s(20)) - root.s(5))
                                                color: "transparent"
                                                clip: true

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: groupWrapper.customType === "screenshot"
                                                    text: "󰄀"
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: root.s(22)
                                                    color: ThemeBackend.mauve
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: groupWrapper.customType === "weather"
                                                    text: "󰖕"
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: root.s(22)
                                                    color: ThemeBackend.peach
                                                }


                                                Image {
                                                    id: groupHeaderIcon
                                                    anchors.fill: parent
                                                    source: {
                                                        if (groupWrapper.customType !== "default") return "";
                                                        let ic = "";
                                                        if (typeof icon !== "undefined" && icon) {
                                                            ic = icon;
                                                        } else if (typeof appIcon !== "undefined" && appIcon) {
                                                            ic = appIcon;
                                                        } else if (groupWrapper.memberList && groupWrapper.memberList.length > 0) {
                                                            let first = groupWrapper.memberList[0];
                                                            if (first) {
                                                                ic = first.appIcon || first.icon || first.iconPath || "";
                                                            }
                                                        }
                                                        if (!ic) return "";
                                                        if (ic.startsWith("file://") || ic.startsWith("image://") || ic.startsWith("http://") || ic.startsWith("https://")) return ic;
                                                        return ic.startsWith("/") ? "file://" + ic : "image://icon/" + ic;
                                                    }
                                                    sourceSize: Qt.size(48, 48)
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: groupWrapper.customType === "default" && status === Image.Ready && source !== ""
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    anchors.horizontalCenterOffset: 1
                                                    anchors.verticalCenterOffset: -1
                                                    visible: groupWrapper.customType === "default" && !groupHeaderIcon.visible
                                                    text: "󰋽"
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: root.s(22)
                                                    color: ThemeBackend.subtext0
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: root.s(2)

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: root.s(4)

                                                Text {
                                                    text: displayName
                                                    font.family: ThemeBackend.fontFamily
                                                    font.weight: Font.Bold
                                                    font.pixelSize: root.s(13)
                                                    color: ThemeBackend.text
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: "·"
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: root.s(11)
                                                    color: ThemeBackend.subtext1
                                                    visible: opacity > 0.001
                                                    opacity: Math.max(0.0, 1.0 - groupWrapper.groupExpandProgress * 2.0)
                                                }

                                                Text {
                                                    id: headerTimeLabel
                                                    property string timeText: ""
                                                    function updateTimeText() {
                                                        let timestamp = latestTimestamp || Date.now();
                                                        let diff = Math.floor((Date.now() - timestamp) / 1000);
                                                        if (diff < 60) timeText = "now";
                                                        else if (diff < 3600) { let m = Math.floor(diff / 60); timeText = m + "m"; }
                                                        else if (diff < 86400) { let h = Math.floor(diff / 3600); timeText = h + "h"; }
                                                        else { let d = Math.floor(diff / 86400); timeText = d + "d"; }
                                                    }
                                                    Timer { interval: 10000; running: true; repeat: true; onTriggered: parent.updateTimeText() }
                                                    Component.onCompleted: updateTimeText()
                                                    text: timeText
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: root.s(11)
                                                    color: ThemeBackend.subtext1
                                                    visible: opacity > 0.001
                                                    opacity: Math.max(0.0, 1.0 - groupWrapper.groupExpandProgress * 2.0)
                                                }

                                                Item { Layout.fillWidth: true }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: {
                                                    if (latestSummary && latestBody) return latestSummary + ": " + latestBody;
                                                    if (latestBody) return latestBody;
                                                    if (latestSummary) return latestSummary;
                                                    return "";
                                                }
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: root.s(11)
                                                color: ThemeBackend.subtext0
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                                visible: opacity > 0.001 && text !== ""
                                                opacity: Math.max(0.0, 1.0 - groupWrapper.groupExpandProgress * 2.0)
                                                Layout.preferredHeight: (1.0 - groupWrapper.groupExpandProgress) * implicitHeight
                                                clip: true
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: root.s(8)

                                            Item {
                                                Layout.preferredWidth: Math.max(root.s(30), countText.implicitWidth + root.s(10))
                                                Layout.preferredHeight: root.s(30)

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: Radius.inner(root.s(8), root.s(15))
                                                    color: ThemeBackend.surface2
                                                }

                                                Text {
                                                    id: countText
                                                    anchors.centerIn: parent
                                                    text: groupWrapper.memberCount
                                                    font.family: ThemeBackend.fontFamily
                                                    font.weight: Font.Bold
                                                    font.pixelSize: root.s(12)
                                                    color: ThemeBackend.text
                                                }

                                                Rectangle {
                                                    width: root.s(8)
                                                    height: root.s(8)
                                                    radius: root.s(4)
                                                    color: ThemeBackend.red
                                                    anchors.top: parent.top
                                                    anchors.right: parent.right
                                                    anchors.topMargin: -root.s(2)
                                                    anchors.rightMargin: -root.s(2)
                                                    visible: typeof unreadCount !== "undefined" && unreadCount > 0
                                                }
                                            }

                                            FlipIcon {
                                                id: groupExpandButton
                                                Layout.preferredWidth: size
                                                Layout.preferredHeight: size
                                                size: root.s(30)
                                                cornerRadius: Radius.inner(root.s(8), root.s(15))
                                                accentColor: ThemeBackend.surface2
                                                iconColor: isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.subtext1
                                                autoToggle: false
                                                flipped: groupWrapper.groupExpandProgress > 0.5
                                                onClicked: {
                                                    groupWrapper.isExpanded = !groupWrapper.isExpanded;
                                                    groupWrapper.groupExpandProgress = Qt.binding(() => groupWrapper.isExpanded ? 1.0 : 0.0);
                                                    if (groupWrapper.isExpanded) {
                                                        NotificationManager.markGroupRead(groupKey);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item {
                                id: expandedMembersContainer
                                Layout.fillWidth: true
                                Layout.preferredHeight: membersRowLayout.implicitHeight * groupWrapper.groupExpandProgress
                                implicitHeight: membersRowLayout.implicitHeight * groupWrapper.groupExpandProgress
                                opacity: Math.max(0.0, (groupWrapper.groupExpandProgress - 0.15) / 0.85)
                                visible: groupWrapper.groupExpandProgress > 0.001
                                clip: true

                                RowLayout {
                                    id: membersRowLayout
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: root.s(8)

                                    Item {
                                        Layout.preferredWidth: root.s(14)
                                        Layout.fillHeight: true

                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: root.s(8)
                                            width: Math.max(1, root.s(2))
                                            radius: root.s(1)
                                            color: Qt.rgba(ThemeBackend.surface2.r, ThemeBackend.surface2.g, ThemeBackend.surface2.b, 0.7)
                                        }
                                    }

                                    ColumnLayout {
                                        id: membersCol
                                        Layout.fillWidth: true
                                        spacing: root.s(8)

                                        Repeater {
                                            id: memberRepeater
                                            model: groupWrapper.memberList

                                            delegate: Loader {
                                                id: memberNotifLoader
                                                Layout.fillWidth: true

                                                property var memberData: modelData
                                                property var memberUid: memberData && memberData.uid !== undefined ? memberData.uid : -1

                                                QtObject {
                                                    id: memberDelegateWrapper
                                                    property var nData: memberData
                                                    property var nUid: memberUid
                                                    property var realNotif: NotificationManager.liveNotifs && memberUid !== -1 ? NotificationManager.liveNotifs[memberUid] : null
                                                    property bool isPopupContext: false
                                                    property var actionArray: {
                                                        try {
                                                            let aj = memberData ? memberData.actionsJson : "";
                                                            return aj ? JSON.parse(aj) : [];
                                                        } catch (e) {
                                                            return [];
                                                        }
                                                    }
                                                    function removeThisNotif() {
                                                        if (memberUid !== -1) {
                                                            NotificationManager.dismissNotification(memberUid);
                                                        }
                                                    }
                                                }

                                                source: {
                                                    if (!memberData) return "";
                                                    let appn = memberData.appName || displayName || "";
                                                    let app = appn.toLowerCase().trim();
                                                    if (app === "weather") return "../../modules/notifications/types/Weather.qml";
                                                    if (app === "screenshot" || app === "screen recorder" || app === "spectacle") return "../../modules/notifications/types/Screenshot.qml";
                                                    return "../../modules/notifications/types/Default.qml";
                                                }

                                                onLoaded: {
                                                    if (item) {
                                                        item.root = root.rootContext ? root.rootContext : root;
                                                        item.delegateWrapper = memberDelegateWrapper;
                                                        item.model = memberData;
                                                        if (item.hasOwnProperty("showIcon")) item.showIcon = true;
                                                    }
                                                }

                                                Binding {
                                                    target: memberNotifLoader.item
                                                    property: "model"
                                                    value: memberData
                                                    when: memberNotifLoader.item !== null
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
