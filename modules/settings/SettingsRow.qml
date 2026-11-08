import "../../services/layout"
import "../../services/reusables" as V2
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row
    required property var host
    property string label
    property string desc
    property string glyph: ""
    default property alias content: holder.data

    // Search: a labelled row registers with the host under tab|subtab|id, and flashes
    // when picked from the results. Upstream's reusables/guide/SettingsRow.qml.
    property string settingId: ""
    property string searchKeywords: ""
    property bool searchable: true
    readonly property string effectiveSettingId: settingId !== "" ? settingId : label.toLowerCase().replace(/[^a-z0-9_]/g, "_")
    property string registeredSearchKey: ""
    property real highlightFlash: 0.0
    property int handledHighlightToken: -1

    Layout.fillWidth: true
    implicitHeight: inner.implicitHeight + row.host.s(24)
    radius: Radius.outer(row.host.s(8))
    readonly property color baseColor: Qt.alpha(row.host.surface0, 0.4)
    color: row.highlightFlash > 0.001
        ? Qt.tint(baseColor, Qt.rgba(row.host.accent.r, row.host.accent.g, row.host.accent.b, row.highlightFlash * 0.12))
        : baseColor
    Behavior on color { ColorAnimation { duration: 150 } }

    function tabLocation() {
        let tabIdx = -1;
        let subIdx = -1;
        let p = row.parent;
        while (p) {
            if (subIdx === -1 && p.subTabIndex !== undefined && p.subTabIndex !== null && p.subTabIndex >= 0) subIdx = p.subTabIndex;
            if (tabIdx === -1 && p.tabIndex !== undefined && p.tabIndex !== null && p.tabIndex >= 0) tabIdx = p.tabIndex;
            p = p.parent;
        }
        return { tabIndex: tabIdx, subIndex: subIdx };
    }

    function resolveTabInfo() {
        let tab = "";
        let subtab = "";
        let loc = tabLocation();
        let r = row.host;
        if (r && r.tabsModel && loc.tabIndex >= 0 && loc.tabIndex < r.tabsModel.length) {
            let tModel = r.tabsModel[loc.tabIndex];
            tab = tModel.key || "";
            if (tModel.subtabs && loc.subIndex >= 0 && loc.subIndex < tModel.subtabs.length) {
                subtab = tModel.subtabs[loc.subIndex].key || "";
            }
        }
        return { tab: tab, subtab: subtab };
    }

    function isOwnTabLive() {
        let r = row.host;
        if (!r || r.visible !== true) return false;
        let loc = tabLocation();
        if (loc.tabIndex < 0) return false;
        if (loc.tabIndex !== r.currentTab) return false;
        if (loc.subIndex >= 0 && loc.subIndex !== r.currentSubTab) return false;
        return true;
    }

    // A row on a page that is not showing is indexed regardless; on the live page only
    // while it is visible, so a row hidden by its own condition does not come up.
    function isIndexable() {
        if (!row.searchable || row.label === "") return false;
        if (!row.isOwnTabLive()) return true;
        return row.visible;
    }

    function registerWithSearch() {
        let r = row.host;
        if (!r || typeof r.registerSearchItem !== "function") return;
        if (!row.isIndexable()) {
            unregisterFromSearch();
            return;
        }

        let info = resolveTabInfo();
        let searchKey = info.tab + "|" + info.subtab + "|" + row.effectiveSettingId;

        if (row.registeredSearchKey !== "" && row.registeredSearchKey !== searchKey) {
            r.unregisterSearchItem(row.registeredSearchKey);
        }
        row.registeredSearchKey = searchKey;

        r.registerSearchItem({
            key: searchKey,
            id: row.effectiveSettingId,
            title: row.label,
            desc: row.desc,
            tab: info.tab,
            subtab: info.subtab,
            icon: row.glyph,
            keywords: row.searchKeywords,
            target: row
        });
    }

    function unregisterFromSearch() {
        let r = row.host;
        if (!r || typeof r.unregisterSearchItem !== "function") return;
        if (row.registeredSearchKey !== "") {
            r.unregisterSearchItem(row.registeredSearchKey);
            row.registeredSearchKey = "";
        }
    }

    function ensureVisibleInFlickable() {
        let p = row.parent;
        let flick = null;
        while (p) {
            if (p.contentY !== undefined && p.contentHeight !== undefined) {
                flick = p;
                break;
            }
            p = p.parent;
        }
        if (flick) {
            let targetPos = row.mapToItem(flick.contentItem, 0, 0);
            if (targetPos) {
                let viewTop = flick.contentY;
                let viewBottom = flick.contentY + flick.height;
                if (targetPos.y < viewTop || targetPos.y + row.height > viewBottom) {
                    flick.contentY = Math.max(0, Math.min(targetPos.y - flick.height / 2 + row.height / 2, flick.contentHeight - flick.height));
                }
            }
        }
    }

    function triggerHighlightAnimation() {
        highlightAnimation.restart();
        row.ensureVisibleInFlickable();
        ensureVisibleTimer.restart();
    }

    function checkHighlight() {
        let r = row.host;
        if (!r || r.highlightToken === undefined) return;
        if (r.highlightToken === row.handledHighlightToken) return;
        if (r.highlightedSettingId && (r.highlightedSettingId === row.effectiveSettingId || r.highlightedSettingId === row.settingId)) {
            row.handledHighlightToken = r.highlightToken;
            r.highlightedSettingId = "";
            highlightDelayTimer.restart();
        }
    }

    Connections {
        target: row.host
        ignoreUnknownSignals: true
        function onHighlightTokenChanged() {
            row.checkHighlight();
        }
    }

    onVisibleChanged: {
        searchRegTimer.restart();
        if (visible) {
            row.checkHighlight();
        }
    }

    Timer {
        id: ensureVisibleTimer
        interval: 320
        repeat: false
        onTriggered: row.ensureVisibleInFlickable()
    }

    Timer {
        id: highlightDelayTimer
        interval: 80
        repeat: false
        onTriggered: row.triggerHighlightAnimation()
    }

    Timer {
        id: searchRegTimer
        interval: 10
        repeat: false
        onTriggered: row.registerWithSearch()
    }

    SequentialAnimation {
        id: highlightAnimation
        PropertyAction { target: row; property: "highlightFlash"; value: 0.0 }
        NumberAnimation { target: row; property: "highlightFlash"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 1500 }
        NumberAnimation { target: row; property: "highlightFlash"; from: 1.0; to: 0.0; duration: 900; easing.type: Easing.InOutSine }
    }

    Component.onCompleted: {
        searchRegTimer.restart();
        checkHighlight();
    }
    Component.onDestruction: unregisterFromSearch()

    onLabelChanged: searchRegTimer.restart()
    onDescChanged: searchRegTimer.restart()
    onGlyphChanged: searchRegTimer.restart()
    onSearchableChanged: searchRegTimer.restart()
    onSettingIdChanged: searchRegTimer.restart()

    RowLayout {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: row.host.s(14)
        anchors.rightMargin: row.host.s(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.host.s(12)

        V2.IconButton {
            visible: row.glyph !== ""
            enabled: false
            size: row.host.s(32)
            Layout.preferredWidth: row.host.s(32)
            Layout.preferredHeight: row.host.s(32)
            Layout.alignment: Qt.AlignVCenter
            cornerRadius: Radius.outer(row.host.s(8))
            buttonIcon: row.glyph
            centerInk: true
            iconFontSize: row.host.s(16)
            accentColor: row.host.surface0
            textColor: row.host.text
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: row.host.s(2)
            Text {
                Layout.fillWidth: true
                text: row.label
                font.family: row.host.fontFamily
                font.pixelSize: row.host.s(13)
                color: row.host.text
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: row.desc
                visible: row.desc !== ""
                font.family: row.host.fontFamily
                font.pixelSize: row.host.s(11)
                color: row.host.subtext0
                wrapMode: Text.Wrap
            }
        }
        Item {
            id: holder
            Layout.preferredWidth: childrenRect.width
            Layout.preferredHeight: childrenRect.height
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        }
    }
}
