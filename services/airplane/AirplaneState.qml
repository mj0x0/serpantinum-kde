pragma Singleton

// What airplane mode switched off, kept outside the notification center so it survives the panel closing.
import QtQuick

Item {
    // Set only by the airplane toggle, so radios that are merely off don't read as airplane mode.
    property bool engaged: false
    property bool remembered: false
    property bool wifiBefore: false
    property bool btBefore: false

    function remember(wifi, bt) { wifiBefore = wifi; btBefore = bt; remembered = true; engaged = true; }
    function forget() { remembered = false; engaged = false; }
}
