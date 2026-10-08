// Concave fillet that lets the fill bar style hug the screen edge. Ported from
// serpantinum v2 bar/TopBar.qml (leftOuterCorner / rightOuterCorner canvases),
// generalised: the wedge hugs one vertex of the square, so all four bar edges
// use the same paint path.
import QtQuick

Canvas {
    id: root
    required property var barWindow
    required property var mocha
    property string vertexX: "left"   // left | right
    property string vertexY: "top"    // top | bottom

    width: barWindow.s(14)
    height: barWindow.s(14)

    readonly property color fillColor: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, barWindow.barOpacity)
    onFillColorChanged: requestPaint()
    onVertexXChanged: requestPaint()
    onVertexYChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = fillColor;
        var vx = vertexX === "left" ? 0 : width;
        var ox = vertexX === "left" ? width : 0;
        var vy = vertexY === "top" ? 0 : height;
        var oy = vertexY === "top" ? height : 0;
        ctx.beginPath();
        ctx.moveTo(vx, vy);
        ctx.lineTo(ox, vy);
        ctx.arcTo(vx, vy, vx, oy, width);
        ctx.lineTo(vx, oy);
        ctx.closePath();
        ctx.fill();
    }
}
