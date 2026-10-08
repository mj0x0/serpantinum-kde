// Where the dock sits, for everyone who is not the dock (the twin of BarState).
// Fed by Bindings from the dock window in shell.qml.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property string position: "bottom"
    property bool active: false
    property var screen: null
    // Span along the edge in global screen coordinates: island plus both fillets.
    // The window keeps it while auto-hidden, since the reveal strip lives there.
    property real start: 0
    property real length: 0
    property real thickness: 0
}
