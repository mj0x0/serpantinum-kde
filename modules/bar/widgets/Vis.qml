// 16 cava bars from the shared Cava singleton; a consumer only while placed, and cava
// itself only runs while something plays. serpantinum v2's VisWidget.
import "../../../services/cava"
import QtQuick

Rectangle {
    id: vis
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0
    readonly property int barCount: 16

    property bool subscribed: false
    readonly property bool wantSubscribe: placed && showLayout
    onWantSubscribeChanged: updateSubscription()
    function updateSubscription() {
        if (wantSubscribe && !subscribed) { subscribed = true; Cava.registerConsumer(); }
        else if (!wantSubscribe && subscribed) { subscribed = false; Cava.unregisterConsumer(); }
    }
    Component.onCompleted: updateSubscription()
    Component.onDestruction: if (subscribed) { subscribed = false; Cava.unregisterConsumer(); }

    readonly property var levels: {
        var src = Cava.barLevels, out = [];
        if (!src || src.length === 0) { for (var i = 0; i < barCount; i++) out.push(0.0); return out; }
        for (var j = 0; j < barCount; j++) {
            var norm = barCount > 1 ? (j / (barCount - 1)) : 0;
            var srcIdx = Math.min(src.length - 1, Math.floor(Math.pow(norm, 1.4) * (src.length - 1)));
            var val = src[srcIdx] || 0.0;
            out.push(val < 0.04 ? 0.0 : Math.pow((val - 0.04) / 0.96, 1.25));
        }
        return out;
    }

    readonly property real targetWidth: (placed && !vertical) ? hRow.implicitWidth + barWindow.s(24) : 0
    readonly property real targetHeight: (placed && vertical) ? vCol.implicitHeight + barWindow.s(20) : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !vis.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && vis.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    visible: placed && (vertical ? height : width) > 0
    clip: true

    color: grouped ? "transparent" : barWindow.pillBg
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05 * barWindow.pillBorderAlpha)

    property bool showLayout: false
    Timer { running: barWindow.isStartupReady; interval: 100; onTriggered: vis.showLayout = true }
    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

    Row {
        id: hRow
        visible: !vis.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(4)
        Repeater {
            model: vis.barCount
            delegate: Rectangle {
                required property int index
                property real level: index < vis.levels.length ? vis.levels[index] : 0.0
                width: barWindow.s(5)
                height: Math.max(barWindow.s(4), level * vis.height * 0.65)
                radius: width / 2
                color: mocha.mauve
                opacity: 0.45 + level * 0.55
                anchors.verticalCenter: parent.verticalCenter
                Behavior on height { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                Behavior on opacity { NumberAnimation { duration: 55 } }
            }
        }
    }

    Column {
        id: vCol
        visible: vis.vertical
        anchors.centerIn: parent
        spacing: barWindow.s(3)
        Repeater {
            model: vis.barCount
            delegate: Rectangle {
                required property int index
                property real level: index < vis.levels.length ? vis.levels[index] : 0.0
                height: barWindow.s(3)
                width: Math.max(barWindow.s(4), level * vis.width * 0.65)
                radius: height / 2
                color: mocha.mauve
                opacity: 0.45 + level * 0.55
                anchors.horizontalCenter: parent.horizontalCenter
                Behavior on width { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                Behavior on opacity { NumberAnimation { duration: 55 } }
            }
        }
    }
}
