// Notification store, serpantinum v2's NotificationManager on our daemon: history,
// grouped history and the toast queue. The NotificationServer itself lives in
// modules/notifications/Notifications.qml and calls receive(); nothing else owns the bus.
pragma Singleton

import "../dnd"
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    // uid -> live Notification. Mutated in place, never reassigned: consumers hold the object.
    property var liveNotifs: ({})
    property int counter: 0
    // Bound by the daemon Scope from NotifCenterState: no toasts while the panel is open.
    property bool panelOpen: false
    property int unreadCount: 0
    property bool _batch: false
    property var _resolveCache: ({})

    ListModel { id: historyModel }
    ListModel { id: popupsModel }
    ListModel { id: groupedModel }

    property alias history: historyModel
    property alias popups: popupsModel
    property alias groupedHistory: groupedModel

    signal popupAdded(int uid, var notif)

    readonly property var aliasTable: ({
        "telegram": "org.telegram.desktop",
        "discord": "discord",
        "slack": "slack",
        "spotify": "spotify"
    })

    onPanelOpenChanged: {
        if (panelOpen) { popupsModel.clear(); _resolveCache = ({}); }
    }

    // --- app resolution ------------------------------------------------------
    function resolveApp(n) {
        if (!n) return { groupKey: "system", displayName: "System", icon: "" };
        let rawAppName = n.appName || "";
        let appName = rawAppName.toLowerCase().trim()
            .replace(/\s*(canary|beta|nightly|-git|git|dev|development)\s*$/g, "");
        let desktopEntry = ("" + (n.desktopEntry || "")).trim().replace(/\.desktop$/, "");
        let key = desktopEntry + "|" + appName;
        if (_resolveCache[key] !== undefined) return _resolveCache[key];

        let entry = null;
        if (desktopEntry) entry = DesktopEntries.byId(desktopEntry);
        if (!entry && appName) {
            let alias = aliasTable[appName];
            entry = alias ? DesktopEntries.byId(alias) : DesktopEntries.heuristicLookup(rawAppName);
        }
        let resolved = {
            groupKey: entry ? entry.id : (appName || "system"),
            displayName: entry ? entry.name : (rawAppName || "System"),
            icon: n.appIcon || (entry ? entry.icon : "")
        };
        _resolveCache[key] = resolved;
        return resolved;
    }

    function urgencyOf(n) {
        if (n.urgency === NotificationUrgency.Critical) return 2;
        if (n.urgency === NotificationUrgency.Low) return 0;
        return 1;
    }

    // --- intake ---------------------------------------------------------------
    function receive(n) {
        n.tracked = true;

        let extractedActions = [];
        if (n.actions) {
            for (let i = 0; i < n.actions.length; i++) {
                extractedActions.push({
                    "id":   n.actions[i].identifier || "",
                    "text": n.actions[i].text || "Action"
                });
            }
        }

        root.counter++;
        let uid = root.counter;
        root.liveNotifs[uid] = n;
        n.closed.connect(function () { root._onClosed(uid); });

        let urgency = urgencyOf(n);
        let resolved = resolveApp(n);
        // Critical notifications never fold into a group.
        let groupKey = urgency === 2 ? resolved.groupKey + "_crit_" + uid : resolved.groupKey;
        let now = Date.now();
        let imageVal = (n.image ? "" + n.image : "") || (n.appIcon ? "" + n.appIcon : "");

        let notifData = {
            "appName":     n.appName !== "" ? n.appName : "System",
            "displayName": resolved.displayName,
            "groupKey":    groupKey,
            "summary":     n.summary !== "" ? n.summary : "No Title",
            "body":        n.body || "",
            "iconPath":    n.appIcon || "",
            "icon":        resolved.icon || n.appIcon || "",
            "image":       imageVal,
            "imagePath":   imageVal,
            "actionsJson": JSON.stringify(extractedActions),
            "hasActions":  extractedActions.length > 0,
            "uid":         uid,
            "notif":       n,
            "time":        now,
            "timestamp":   now,
            "urgency":     urgency,
            "read":        false
        };
        historyModel.insert(0, notifData);

        // Replayed after a reload: history only, no toast.
        if (n.lastGeneration || root.panelOpen) return;
        // DND keeps recording; only critical still pops.
        if (DndState.enabled && urgency !== 2) return;

        popupsModel.insert(0, notifData);
        root.popupAdded(uid, n);
    }

    // The app closed it, or we dismissed it: the object dies after this, so the
    // history entry goes with it (as KDE does).
    function _onClosed(uid) {
        delete root.liveNotifs[uid];
        if (root._batch) return;
        removePopup(uid);
        _removeFromHistory(uid);
    }

    function _removeFromHistory(uid) {
        for (let i = 0; i < historyModel.count; i++) {
            if (historyModel.get(i).uid === uid) { historyModel.remove(i, 1); return true; }
        }
        return false;
    }

    // --- toasts ---------------------------------------------------------------
    // Toast only: the live object stays, so a history card's actions keep working.
    function removePopup(uid) {
        for (let i = popupsModel.count - 1; i >= 0; i--) {
            if (popupsModel.get(i).uid === uid) { popupsModel.remove(i, 1); return; }
        }
    }

    // --- read state -------------------------------------------------------------
    function markAsRead(uid) {
        for (let i = 0; i < historyModel.count; i++) {
            let d = historyModel.get(i);
            if (d.uid === uid) {
                if (!d.read) { historyModel.setProperty(i, "read", true); rebuildGroups(); }
                return;
            }
        }
    }

    function markGroupRead(groupKey) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let d = historyModel.get(i);
            if (d.groupKey === groupKey && !d.read) { historyModel.setProperty(i, "read", true); changed = true; }
        }
        if (changed) rebuildGroups();
    }

    function markAllRead() {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            if (!historyModel.get(i).read) { historyModel.setProperty(i, "read", true); changed = true; }
        }
        if (changed) rebuildGroups();
    }

    // --- dismissal ----------------------------------------------------------------
    function dismissNotification(uid) {
        let n = root.liveNotifs[uid];
        if (n) { n.dismiss(); return; }   // closed -> _onClosed does the rest
        removePopup(uid);
        _removeFromHistory(uid);
    }

    function dismissGroup(groupKey) {
        root._batch = true;
        for (let i = historyModel.count - 1; i >= 0; i--) {
            let d = historyModel.get(i);
            if (d.groupKey !== groupKey) continue;
            let uid = d.uid;
            let n = root.liveNotifs[uid];
            delete root.liveNotifs[uid];
            if (n) n.dismiss();
            removePopup(uid);
            historyModel.remove(i, 1);
        }
        root._batch = false;
        rebuildGroups();
    }

    // dismiss() rather than drop: dropping refs while tracked stays true leaks the objects.
    // ONE bulk remove, so a view runs a single staggered remove transition.
    function clearAll() {
        root._batch = true;
        for (let key in root.liveNotifs) {
            let n = root.liveNotifs[key];
            delete root.liveNotifs[key];
            if (n) n.dismiss();
        }
        if (historyModel.count > 0) historyModel.remove(0, historyModel.count);
        popupsModel.clear();
        groupedModel.clear();
        root._batch = false;
        root.unreadCount = 0;
    }

    // --- grouping -------------------------------------------------------------------
    Connections {
        target: historyModel
        function onCountChanged() { if (!root._batch) root.rebuildGroups(); }
    }

    function rebuildGroups() {
        let groups = {};
        let order = [];
        let unread = 0;

        for (let i = 0; i < historyModel.count; i++) {
            let d = historyModel.get(i);
            let g = groups[d.groupKey];
            if (!g) {
                g = groups[d.groupKey] = {
                    groupKey: d.groupKey, displayName: d.displayName, icon: d.icon,
                    members: [], unreadCount: 0,
                    latestSummary: d.summary, latestBody: d.body, latestTimestamp: d.timestamp
                };
                order.push(d.groupKey);
            }
            if (d.timestamp >= g.latestTimestamp) {
                g.latestTimestamp = d.timestamp; g.latestSummary = d.summary; g.latestBody = d.body;
            }
            // No `notif` here: a QObject does not survive JSON.stringify; cards use liveNotifs.
            g.members.push({
                "appName": d.appName, "displayName": d.displayName, "summary": d.summary, "body": d.body,
                "iconPath": d.iconPath, "icon": d.icon, "image": d.image, "imagePath": d.imagePath,
                "actionsJson": d.actionsJson, "hasActions": d.hasActions, "uid": d.uid,
                "timestamp": d.timestamp, "urgency": d.urgency, "read": d.read
            });
            if (!d.read) { g.unreadCount++; unread++; }
        }
        root.unreadCount = unread;

        for (let i = groupedModel.count - 1; i >= 0; i--) {
            if (!groups[groupedModel.get(i).groupKey]) groupedModel.remove(i, 1);
        }

        for (let i = 0; i < order.length; i++) {
            let g = groups[order[i]];
            let entry = {
                "groupKey": g.groupKey, "displayName": g.displayName, "icon": g.icon,
                "count": g.members.length, "unreadCount": g.unreadCount,
                "latestSummary": g.latestSummary, "latestBody": g.latestBody,
                "latestTimestamp": g.latestTimestamp, "itemsJson": JSON.stringify(g.members)
            };
            let existing = -1;
            for (let j = 0; j < groupedModel.count; j++) {
                if (groupedModel.get(j).groupKey === g.groupKey) { existing = j; break; }
            }
            if (existing === -1) { groupedModel.insert(i, entry); continue; }
            if (existing !== i && i < groupedModel.count) groupedModel.move(existing, i, 1);
            let item = groupedModel.get(i);
            for (let k in entry) if (item[k] !== entry[k]) groupedModel.setProperty(i, k, entry[k]);
        }
    }

    // --- lock screen ------------------------------------------------------------------
    // Read over IPC by the greeter, which is a separate process and cannot see the model.
    readonly property int recentCount: 6

    function recentJson() {
        var out = [];
        for (var i = 0; i < historyModel.count && out.length < root.recentCount; i++) {
            var e = historyModel.get(i);
            out.push({
                "app":     e.appName || "",
                "summary": e.summary || "",
                "body":    e.body || "",
                "icon":    e.iconPath || "",
                "time":    e.time || 0
            });
        }
        return JSON.stringify(out);
    }
}
