// serpantinum v2's LoaderIcon: a blob that morphs between seven shapes while it spins.
import QtQuick

Item {
    id: root
    implicitWidth: 64
    implicitHeight: 64

    property color accentColor: "white"
    property bool running: true

    opacity: running ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.InOutQuad } }

    readonly property var shapeConfigs: [
        {p: 7, d: 0.08, ax: 1.0, ay: 1.0},
        {p: 9, d: 0.12, ax: 1.0, ay: 1.0},
        {p: 5, d: 0.15, ax: 1.0, ay: 1.0},
        {p: 2, d: 0.10, ax: 1.3, ay: 0.7},
        {p: 8, d: 0.18, ax: 1.0, ay: 1.0},
        {p: 4, d: 0.15, ax: 1.0, ay: 1.0},
        {p: 0, d: 0.00, ax: 1.2, ay: 0.8}
    ]
    property var shapes: []
    property int currentIndex: 0
    property int nextIndex: 1
    property real morphProgress: 0.0
    property real kickRotation: 0.0
    property real baseRotation: 0.0

    NumberAnimation on baseRotation { from: 0; to: 360; duration: 9100; loops: Animation.Infinite; running: root.running }
    Behavior on morphProgress { SpringAnimation { spring: 6.0; damping: 0.5; mass: 1.0; epsilon: 0.001 } }
    Behavior on kickRotation { SpringAnimation { spring: 6.0; damping: 0.5; mass: 1.0; epsilon: 0.001 } }

    Component.onCompleted: {
        let out = [];
        for (let s = 0; s < shapeConfigs.length; s++) {
            let c = shapeConfigs[s], pts = [];
            for (let i = 0; i < 32; i++) {
                let theta = (i / 32) * Math.PI * 2;
                let r = 1.0 + c.d * Math.cos(c.p * theta);
                pts.push({ x: r * Math.cos(theta) * c.ax, y: r * Math.sin(theta) * c.ay });
            }
            out.push(pts);
        }
        root.shapes = out;
        root.morphProgress = 1.0;
        root.kickRotation = 45.0;
    }

    Timer {
        interval: 650
        running: root.running
        repeat: true
        onTriggered: {
            root.currentIndex = root.nextIndex;
            root.nextIndex = (root.nextIndex + 1) % root.shapes.length;
            root.morphProgress = 0.0;
            root.morphProgress = 1.0;
            root.kickRotation += 45.0;
        }
    }

    Canvas {
        id: blob
        anchors.fill: parent
        rotation: root.baseRotation + root.kickRotation
        Connections { target: root; function onMorphProgressChanged() { blob.requestPaint() } }
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (root.shapes.length === 0) return;
            var a = root.shapes[root.currentIndex], b = root.shapes[root.nextIndex];
            var t = Math.max(0, Math.min(1.2, root.morphProgress));
            var cx = width / 2, cy = height / 2, rad = Math.min(width, height) * 0.38;
            ctx.beginPath();
            for (var i = 0; i <= a.length; i++) {
                var k = i % a.length;
                var x = cx + (a[k].x + (b[k].x - a[k].x) * t) * rad;
                var y = cy + (a[k].y + (b[k].y - a[k].y) * t) * rad;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.closePath();
            ctx.fillStyle = root.accentColor.toString();
            ctx.fill();
        }
    }
}
