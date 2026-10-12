pragma Singleton

// Shim, not a port: upstream's Scaler.s() is the identity and the widget files call it
// as a singleton. Never import services/layout beside this; its Scaler type would shadow it.
import QtQuick
import Quickshell

Singleton {
    function s(val) {
        return val;
    }
}
