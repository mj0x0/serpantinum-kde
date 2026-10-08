// A Material Symbols Rounded glyph: use the icon NAME as text, e.g. "search".
// Font: ttf-material-symbols-variable.

import "../../services/theme"
import QtQuick

Text {
    property real iconSize: 24
    font.family: "Material Symbols Rounded"
    font.pixelSize: iconSize
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    renderType: Text.NativeRendering
    color: Colors.md3.on_surface
}
