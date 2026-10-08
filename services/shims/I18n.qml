// Shim, not a port: provides the three keys the polkit files ask for and falls back
// to the key itself, so those files stay byte-identical to upstream.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property var strings: ({
        "polkit.default_message":      "Authentication required",
        "polkit.default_description":  "An application is attempting to perform an action that requires privileges.",
        "polkit.password_placeholder": "Password",
        "polkit.error_failed":         "Authentication failed. Please try again."
    })

    function t(key) {
        var v = strings[key];
        return v !== undefined ? v : key;
    }
}
