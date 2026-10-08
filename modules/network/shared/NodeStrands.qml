// The plasma strands that tie orbiting nodes to the core, shared by every network tab.
import QtQuick

Item {
    id: strands

    required property var host          // the tab's popup: s(), colours
    property var nodes: null            // the Repeater whose items are the orbit nodes
    property real coreWidth: 0
    property bool lit: false
    property color tint: strands.host ? strands.host.accent : "white"

    anchors.fill: parent
    z: 0

    Canvas {
        id: canvas
        anchors.fill: parent
        z: 0
        opacity: strands.lit ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 500
            }
        }

        Timer {
            interval: 45
            repeat: true
            running: canvas.opacity > 0.01
            onTriggered: canvas.requestPaint()
        }

        onPaint: {
            var ctx = getContext("2d");
            var S = strands.host.s;
            ctx.clearRect(0, 0, width, height);
            if (!strands.lit)
                return;

            var time = Date.now() / 1000;
            var tWave1 = time * 2.5;
            var tWave2 = time * -1.5;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";

            var startX = width / 2, startY = height / 2;
            var coreW = strands.coreWidth;

            for (var i = 0; i < (strands.nodes ? strands.nodes.count : 0); i++) {
                var item = strands.nodes.itemAt(i);
                if (!item || item.width <= 0)
                    continue;
                var targetX = item.x + item.width / 2;
                var targetY = item.y + item.height / 2;
                if (targetX < 0 || targetY < 0 || targetX > width || targetY > height)
                    continue;

                var dx = targetX - startX, dy = targetY - startY;
                var fullDist = Math.sqrt(dx * dx + dy * dy);
                if (fullDist < S(10))
                    continue;

                var alpha = Math.atan2(dy, dx);
                var cosA = Math.cos(alpha), sinA = Math.sin(alpha);
                var perpX = -sinA, perpY = cosA;
                var startOffset = coreW / 2 + S(5), endOffset = S(35);
                var drawDist = fullDist - startOffset - endOffset;
                if (drawDist <= 0)
                    continue;

                var sX = startX + cosA * startOffset;
                var sY = startY + sinA * startOffset;
                var distanceFactor = Math.max(0, 1.0 - (fullDist / 400.0));
                var wCore = S(1.0) + (distanceFactor * S(2.0));
                var wGlow = S(4.0) + (distanceFactor * S(4.0));
                var a = 0.2 + (distanceFactor * 0.7);
                var steps = 8;

                ctx.beginPath();
                ctx.moveTo(sX, sY);
                for (var j = 1; j <= steps; j++) {
                    var t = j / steps;
                    var env = Math.sin(t * Math.PI);
                    var off = Math.sin(tWave1 + t * 6) * S(6) * env + ((Math.random() - 0.5) * S(5.0) * distanceFactor);
                    ctx.lineTo(sX + cosA * drawDist * t + perpX * off, sY + sinA * drawDist * t + perpY * off);
                }
                ctx.lineWidth = wGlow;
                ctx.strokeStyle = strands.tint;
                ctx.globalAlpha = a * 0.15;
                ctx.stroke();
                ctx.lineWidth = wCore;
                ctx.strokeStyle = "#ffffff";
                ctx.globalAlpha = a;
                ctx.stroke();

                ctx.beginPath();
                ctx.moveTo(sX, sY);
                for (var k = 1; k <= steps; k++) {
                    var tk = k / steps;
                    var envK = Math.sin(tk * Math.PI);
                    var offK = Math.cos(tWave2 + tk * 8) * S(12) * envK + ((Math.random() - 0.5) * S(3.0) * distanceFactor);
                    ctx.lineTo(sX + cosA * drawDist * tk + perpX * offK, sY + sinA * drawDist * tk + perpY * offK);
                }
                ctx.lineWidth = wCore * 1.5;
                ctx.strokeStyle = strands.tint;
                ctx.globalAlpha = a * 0.3;
                ctx.stroke();
            }
            ctx.globalAlpha = 1.0;
        }
    }
}
