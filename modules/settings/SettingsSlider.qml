import "../../services/reusables" as V2
import QtQuick

Item {
    id: sl
    required property var host
    property real from: 0
    property real to: 1
    property real step: 0.05
    property real value: 0
    signal committed(real v)
    implicitWidth: sl.host.s(180)
    implicitHeight: sl.host.s(18)

    // The handle shows what was dropped until settings.json catches up, or it snaps back.
    property real pending: NaN
    readonly property real shown: isNaN(sl.pending) ? sl.value : sl.pending
    onValueChanged: sl.pending = NaN      // the file has caught up (or someone else wrote it)
    function snap(v) { return Math.round((sl.from + Math.round((v - sl.from) / sl.step) * sl.step) * 1000) / 1000; }
    function push(v) {
        var x = sl.snap(v);
        if (x === sl.shown) return;
        sl.pending = x;
        sl.committed(x);
    }

    V2.Draggable {
        id: drag
        anchors.fill: parent
        from: sl.from
        to: sl.to
        stepSize: sl.step
        value: sl.shown
        showValueBubble: true
        valueFormatter: v => sl.step >= 1 ? Math.round(v).toString() : Number(v).toFixed(2)
        backgroundColor: sl.host.surface0
        accentColor: sl.host.accent
        handleColor: sl.host.text
        handleBorderColor: sl.host.mantle
        onMoved: v => sl.push(v)
        onDragFinished: sl.push(drag.dragPreview)
    }
}
