// Makes Quickshell the freedesktop notification daemon: owns the bus name and feeds
// NotificationManager, which holds the history and the toast queue. The only server.

import "../../services/notifications"
import "../notifcenter"
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "." as Notifs

Scope {
    id: root

    // No toasts while the panel is open; it shows the history instead.
    Binding { target: NotificationManager; property: "panelOpen"; value: NotifCenterState.open }

    NotificationServer {
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: n => NotificationManager.receive(n)
    }

    Notifs.NotificationPopups {}
}
