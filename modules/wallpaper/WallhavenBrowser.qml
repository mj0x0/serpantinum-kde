import "../../services/layout"
import "../../services/reusables" as V2
import "../../services/settings"
import "../../services/theme"
import "../../services/wallpaper"
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

// The picker's Wallhaven tab: v2 controls over a lazy grid fed by WallhavenService.
// Arrows move the highlight, Enter downloads or applies it, Tab previews the full image.
Item {
    id: root

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    function s(v) { return scaler.s(v) }
    MatugenColors { id: theme }

    readonly property color accent: theme.mauve
    readonly property real gap: root.s(10)
    readonly property real tileRadius: Radius.inner(root.s(10), root.s(16))
    readonly property real ctlH: root.s(36)
    readonly property real ctlRadius: Radius.outer(root.s(8))
    readonly property int columns: Math.max(3, Math.min(10,
        Math.round(Number(ShellSettings.value("wallpaper.wallhaven.columns", 5)) || 5)))

    // Kept for callers; the preview sheet that used them now lives in the picker.
    property real overhang: 0
    property real underhang: 0
    property real sidehang: 0
    property real chassisRadius: Radius.chassis(root.s(24))

    readonly property bool hasFocus: queryField.hasFocus
    readonly property bool navActive: !root.hasFocus
    function dropFocus() { grid.forceActiveFocus() }
    function focusQuery() { queryField.forceInputFocus() }

    // Any, 1080p, this screen, 4K: deduplicated and ordered by height.
    readonly property var resPresets: {
        var list = [{ label: "Any", value: "" }];
        var cands = ["1920x1080", WallhavenService.screenRes, "3840x2160"];
        var uniq = [];
        for (var i = 0; i < cands.length; i++)
            if (cands[i] !== "" && uniq.indexOf(cands[i]) < 0) uniq.push(cands[i]);
        uniq.sort((a, b) => parseInt(a.split("x")[1]) - parseInt(b.split("x")[1]));
        for (var j = 0; j < uniq.length; j++)
            list.push({ label: "≥" + uniq[j].split("x")[1] + "p", value: uniq[j] });
        return list;
    }
    readonly property var resLabels: root.resPresets.map(p => p.label)
    readonly property int resIndex: Math.max(0, root.resPresets.map(p => p.value).indexOf(WallhavenService.atleast))

    readonly property var sortLabels: ["Newest", "Relevance", "Random", "Views", "Favourites", "Toplist"]
    readonly property var sortValues: ["date_added", "relevance", "random", "views", "favorites", "toplist"]
    readonly property var rangeLabels: ["Day", "3 days", "Week", "Month", "3 months", "6 months", "Year"]
    readonly property var rangeValues: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]

    function fmtSize(b) {
        if (!b) return "";
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB";
        return Math.round(b / 1024) + " KB";
    }
    function fmtCount(n) { return Number(n).toLocaleString(Qt.locale(), "f", 0) }

    readonly property string statusText: {
        var S = WallhavenService;
        if (S.notice !== "") return S.notice;
        if (S.error !== "" && S.model.count > 0)
            return S.errorMessage + (S.error === "ratelimit" && S.retryIn > 0 ? " · retrying in " + S.retryIn + " s" : "");
        if (!S.started) return "";
        var parts = [];
        if (S.total > 0) parts.push(root.fmtCount(S.total) + " wallpapers");
        if (S.lastPage > 1) parts.push("page " + S.page + " of " + root.fmtCount(S.lastPage));
        if (S.purityForced) parts.push("NSFW needs an API key in Settings → Wallpaper");
        if (S.loading && S.model.count > 0) parts.push("loading…");
        return parts.join(" · ");
    }

    readonly property string overlayGlyph: {
        var S = WallhavenService;
        if (S.model.count > 0) return "";
        if (S.error === "ratelimit") return "\u{f0150}";
        if (S.error === "offline") return "\u{f05aa}";
        if (S.error === "key") return "\u{f0341}";
        if (S.error !== "") return "\u{f05d6}";
        if (S.loading || !S.started) return "\u{f06ad}";
        return "\u{f11d1}";
    }
    readonly property string overlayText: {
        var S = WallhavenService;
        if (S.model.count > 0) return "";
        if (S.error === "ratelimit")
            return "Wallhaven asked us to slow down." + (S.retryIn > 0 ? " Retrying in " + S.retryIn + " s." : "");
        if (S.error === "offline") return "Can't reach wallhaven.cc. Check the connection.";
        if (S.error === "key") return "wallhaven rejected the API key. Fix it in Settings → Wallpaper.";
        if (S.error !== "") return S.errorMessage || "Something went wrong talking to wallhaven.";
        if (S.loading || !S.started) return "Searching wallhaven…";
        return "Nothing on wallhaven matches that.";
    }

    // Row count, not contentHeight: the latter lags the model by a layout pass.
    function maybeLoadMore() {
        var rows = Math.ceil(grid.count / Math.max(1, root.columns));
        if (rows * grid.cellHeight - grid.contentY - grid.height < grid.cellHeight * 2)
            WallhavenService.loadMore();
    }

    function pick(tile) {
        grid.currentIndex = tile.index;
        root.dropFocus();
        WallhavenService.download(tile.wid);
    }
    function previewTile(tile) {
        grid.currentIndex = tile.index;
        root.dropFocus();
        root.previewRequested(true);
        root.requestPreview();
    }

    // --- keyboard ---------------------------------------------------------------------
    // The current delegate stays instantiated, so its role-bound properties are the live row.
    readonly property Item cur: grid.currentItem
    onCurChanged: if (root.previewOpen) root.requestPreview()
    // Driven by the picker, which owns the shared preview and listens for previewRequested.
    property bool previewOpen: false
    signal previewRequested(bool open)
    readonly property string previewSource: !root.cur ? "" : (root.cur.local !== "" ? root.cur.local : root.cur.full)
    readonly property var cursor: {
        const c = root.cur;
        if (!c) return null;
        return {
            key: c.wid,
            url: (c.thumb || c.full || c.local) ? "file://" + (c.thumb || c.full || c.local) : "",
            hiUrl: c.local !== "" ? "file://" + c.local : (c.full !== "" ? "file://" + c.full : ""),
            name: c.resolution + "  ·  " + root.fmtSize(c.fileSize),
            palette: c.colors === "" ? [] : c.colors.split(","),
            status: c.pvState === "loading" ? "Loading the full image…  " + c.pvProgress + "%"
                  : (c.local !== "" ? "Saved" : (c.full !== "" ? "" : "Thumbnail")),
            isVideo: false,
            videoUrl: ""
        };
    }
    function cursorRect() {
        const it = grid.currentItem;
        if (!it) return null;
        return it.mapToItem(root, 0, 0, it.width, it.height);
    }

    function moveCursor(delta) {
        var n = grid.count;
        if (n === 0) return;
        var i = grid.currentIndex < 0 ? 0 : Math.max(0, Math.min(n - 1, grid.currentIndex + delta));
        grid.currentIndex = i;
        grid.positionViewAtIndex(i, GridView.Contain);
        if (root.previewOpen) root.requestPreview();
    }
    function requestPreview() {
        if (root.cur && root.previewSource === "") WallhavenService.preview(root.cur.wid);
    }
    function togglePreview() {
        if (root.previewOpen) { root.previewRequested(false); return; }
        if (grid.count === 0) return;
        if (grid.currentIndex < 0) grid.currentIndex = 0;
        root.previewRequested(true);
        root.requestPreview();
    }
    function activateCursor() {
        if (!root.cur) return;
        WallhavenService.download(root.cur.wid);
        root.previewRequested(false);
    }
    // Escape leaves the query field; the picker closes the preview and handles the rest.
    function handleEscape() {
        if (root.hasFocus) { root.dropFocus(); return true; }
        return false;
    }

    Shortcut { sequence: "Left";   enabled: root.navActive; onActivated: root.moveCursor(-1) }
    Shortcut { sequence: "Right";  enabled: root.navActive; onActivated: root.moveCursor(1) }
    Shortcut { sequence: "Up";     enabled: root.navActive; onActivated: root.moveCursor(-root.columns) }
    Shortcut { sequence: "Return"; enabled: root.navActive; onActivated: root.activateCursor() }
    Shortcut { sequence: "Tab";    enabled: root.navActive; onActivated: root.togglePreview() }
    // Down also leaves the query field for the grid, like a launcher.
    Shortcut {
        sequence: "Down"
        onActivated: {
            if (root.hasFocus) {
                root.dropFocus();
                if (grid.currentIndex < 0) root.moveCursor(0);
            } else {
                root.moveCursor(root.columns);
            }
        }
    }

    Component.onCompleted: if (!WallhavenService.started) WallhavenService.search()

    // A page that does not fill the view must pull the next one without a scroll.
    Connections {
        target: WallhavenService
        function onLoadingChanged() { if (!WallhavenService.loading) Qt.callLater(root.maybeLoadMore) }
    }

    component Bit : V2.ClickButton {
        property bool on: false
        implicitHeight: root.ctlH
        horizontalPadding: root.s(12)
        cornerRadius: root.ctlRadius
        textFontSize: root.s(11)
        accentColor: on ? theme.text : theme.surface0
        textColor: on ? theme.crust : theme.text
        opacity: enabled ? 1 : 0.4
    }

    component Btn : V2.ClickButton {
        implicitHeight: root.s(30)
        horizontalPadding: root.s(14)
        cornerRadius: root.ctlRadius
        textFontSize: root.s(11)
        accentColor: theme.surface1
        textColor: theme.text
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: root.s(10)
            z: 2   // the dropdown lists open over the grid below

            V2.Input {
                id: queryField
                Layout.preferredWidth: root.s(340)
                Layout.preferredHeight: root.ctlH
                placeholderText: "Search wallhaven"
                leadingIcon: "\u{f0349}"
                showClearButton: true
                baseColor: theme.surface0
                accentColor: root.accent
                textColor: theme.text
                subTextColor: theme.subtext0
                borderColor: Qt.alpha(theme.surface2, 0.6)
                cornerRadius: root.ctlRadius
                fontPixelSize: root.s(12)
                onTextEdited: t => WallhavenService.typed(t)
                onAccepted: t => { WallhavenService.query = t; WallhavenService.search() }
                onCleared: WallhavenService.typed("")
                Component.onCompleted: text = WallhavenService.query
            }

            Row {
                spacing: root.s(4)
                Repeater {
                    model: ["General", "Anime", "People"]
                    Bit {
                        required property int index
                        required property string modelData
                        buttonText: modelData
                        on: WallhavenService.categories.charAt(index) === "1"
                        onClicked: WallhavenService.toggleBit("categories", index)
                    }
                }
            }

            Row {
                spacing: root.s(4)
                Repeater {
                    model: ["SFW", "Sketchy", "NSFW"]
                    Bit {
                        required property int index
                        required property string modelData
                        buttonText: modelData
                        on: WallhavenService.purity.charAt(index) === "1"
                        enabled: index < 2 || ("" + ShellSettings.value("wallpaper.wallhaven.apiKey", "")) !== ""
                        onClicked: WallhavenService.toggleBit("purity", index)
                    }
                }
            }

            V2.Dropdown {
                id: sortDrop
                Layout.preferredWidth: root.s(150)
                Layout.preferredHeight: root.ctlH
                options: root.sortLabels
                currentIndex: Math.max(0, root.sortValues.indexOf(WallhavenService.sorting))
                accentColor: root.accent
                baseColor: theme.surface0
                hoverColor: theme.surface1
                dropdownColor: theme.surface0
                borderColor: Qt.alpha(theme.surface2, 0.6)
                textColor: theme.text
                activeTextColor: theme.crust
                cornerRadius: root.ctlRadius
                fontPixelSize: root.s(11)
                onValueChanged: (i, v) => WallhavenService.setFilter("sorting", root.sortValues[i])
            }

            V2.Dropdown {
                id: rangeDrop
                visible: WallhavenService.sorting === "toplist"
                Layout.preferredWidth: root.s(130)
                Layout.preferredHeight: root.ctlH
                options: root.rangeLabels
                currentIndex: Math.max(0, root.rangeValues.indexOf(WallhavenService.topRange))
                accentColor: root.accent
                baseColor: theme.surface0
                hoverColor: theme.surface1
                dropdownColor: theme.surface0
                borderColor: Qt.alpha(theme.surface2, 0.6)
                textColor: theme.text
                activeTextColor: theme.crust
                cornerRadius: root.ctlRadius
                fontPixelSize: root.s(11)
                onValueChanged: (i, v) => WallhavenService.setFilter("topRange", root.rangeValues[i])
            }

            V2.Switch {
                id: resSwitch
                Layout.preferredWidth: root.s(Math.max(120, 64 * root.resLabels.length))
                Layout.preferredHeight: root.ctlH
                options: root.resLabels
                currentIndex: root.resIndex
                accentColor: root.accent
                baseColor: theme.surface0
                textColor: theme.subtext0
                activeTextColor: theme.crust
                cornerRadius: root.ctlRadius
                fontPixelSize: root.s(11)
                onToggled: i => WallhavenService.setFilter("atleast", root.resPresets[i].value)
                Connections { target: root; function onResIndexChanged() { resSwitch.currentIndex = root.resIndex } }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: root.statusText !== ""
                Layout.maximumWidth: root.s(560)
                implicitWidth: statusLabel.implicitWidth + root.s(24)
                implicitHeight: root.ctlH
                radius: root.ctlRadius
                color: Qt.alpha(theme.mantle, 0.9)
                border.color: theme.surface2
                border.width: 1
                Text {
                    id: statusLabel
                    anchors.fill: parent
                    anchors.leftMargin: root.s(12)
                    anchors.rightMargin: root.s(12)
                    verticalAlignment: Text.AlignVCenter
                    text: root.statusText
                    color: theme.text
                    font.family: Fonts.ui
                    font.pixelSize: root.s(11)
                    elide: Text.ElideRight
                }
            }
            Btn {
                visible: WallhavenService.error !== "" && WallhavenService.error !== "ratelimit" && WallhavenService.model.count > 0
                buttonText: "Retry"
                onClicked: WallhavenService.retry()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            id: gridBox
            // Never taller than two rows: a wide screen with few columns would otherwise
            // grow tiles past the view and up against the bar.
            readonly property real cellH: Math.max(1, Math.min(Math.floor(width / root.columns) * 9 / 16,
                                                              Math.floor(height / 2)))
            readonly property real cellW: Math.floor(cellH * 16 / 9)

            GridView {
                id: grid
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: gridBox.cellW * root.columns
                clip: true
                model: WallhavenService.model
                cellWidth: gridBox.cellW
                cellHeight: gridBox.cellH
                cacheBuffer: cellHeight * 2
                currentIndex: -1
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 4000
                maximumFlickVelocity: 4000
                onContentYChanged: root.maybeLoadMore()
                onHeightChanged: root.maybeLoadMore()
                onCountChanged: Qt.callLater(root.maybeLoadMore)
                delegate: Tile {}
            }

            Column {
                anchors.centerIn: parent
                spacing: root.s(12)
                visible: root.overlayText !== ""
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.overlayGlyph
                    font.family: Fonts.icons
                    font.pixelSize: root.s(40)
                    color: theme.overlay1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.s(520)
                    text: root.overlayText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: Fonts.ui
                    font.pixelSize: root.s(14)
                    color: theme.subtext0
                }
                Btn {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: WallhavenService.error !== "" && WallhavenService.error !== "ratelimit"
                    buttonText: "Retry"
                    onClicked: WallhavenService.retry()
                }
            }
        }
    }

    component Tile : Item {
        id: tile
        required property int index
        required property string wid
        required property string thumb
        required property string resolution
        required property int fileSize
        required property string colors
        required property string local
        required property string full
        required property string dlState
        required property int dlProgress
        required property string dlMessage
        required property string pvState
        required property int pvProgress
        width: grid.cellWidth
        height: grid.cellHeight

        readonly property bool current: GridView.isCurrentItem
        readonly property bool saved: tile.dlState === "saved" || tile.dlState === "applied" || tile.local !== ""
        readonly property bool busy: tile.dlState === "downloading"
        readonly property bool failed: tile.dlState === "error"
        readonly property string badgeGlyph: busy ? "\u{f0b8f}" : (failed ? "\u{f05d6}" : "\u{f012c}")
        readonly property string badgeText: busy ? tile.dlProgress + "%"
                                          : (failed ? "Failed" : (tile.dlState === "applied" ? "Applied" : "Saved"))

        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: root.gap / 2
            radius: root.tileRadius
            color: theme.surface0
            scale: ma.pressed ? 0.97 : ((ma.containsMouse || tile.current) ? 1.02 : 1.0)
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }

            Rectangle {
                id: mask
                anchors.fill: parent
                radius: card.radius
                visible: false
                layer.enabled: true
            }

            Item {
                id: art
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Image {
                    id: img
                    anchors.fill: parent
                    source: tile.thumb !== "" ? "file://" + tile.thumb : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 250 } }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.s(30)
                    color: Qt.alpha(theme.base, 0.82)
                    opacity: (ma.containsMouse || tile.current) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.s(10)
                        anchors.rightMargin: root.s(10)
                        spacing: root.s(8)
                        Text {
                            text: tile.resolution
                            color: theme.text
                            font.family: Fonts.ui
                            font.pixelSize: root.s(11)
                            font.weight: Font.Medium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.fmtSize(tile.fileSize)
                            color: theme.subtext0
                            font.family: Fonts.ui
                            font.pixelSize: root.s(11)
                            elide: Text.ElideRight
                        }
                        Row {
                            spacing: root.s(4)
                            Repeater {
                                model: tile.colors === "" ? [] : tile.colors.split(",")
                                Rectangle {
                                    required property var modelData
                                    width: root.s(8)
                                    height: width
                                    radius: width / 2
                                    color: modelData
                                    border.width: 1
                                    border.color: Qt.alpha(theme.text, 0.25)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    height: root.s(4)
                    width: parent.width * tile.dlProgress / 100
                    color: theme.text
                    visible: tile.busy
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }

            MultiEffect {
                anchors.fill: parent
                source: art
                maskEnabled: true
                maskSource: mask
            }

            Text {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: img.status === Image.Error ? "\u{f02ee}" : "\u{f02f5}"
                font.family: Fonts.icons
                font.pixelSize: root.s(28)
                color: theme.overlay0
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: root.s(8)
                visible: tile.saved || tile.busy || tile.failed
                height: root.s(24)
                width: badgeRow.implicitWidth + root.s(16)
                radius: Radius.inner(root.s(6), root.s(12))
                color: Qt.alpha(theme.base, 0.85)
                Row {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: root.s(5)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.badgeGlyph
                        font.family: Fonts.icons
                        font.pixelSize: root.s(13)
                        color: tile.failed ? theme.red : theme.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.badgeText
                        font.family: Fonts.ui
                        font.pixelSize: root.s(11)
                        font.weight: Font.Medium
                        color: theme.text
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: "transparent"
                border.width: root.s(2)
                border.color: theme.text
                opacity: (ma.containsMouse || tile.current) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                // Real mouse motion moves the highlight, so Tab previews what is under the pointer.
                onPositionChanged: if (!root.previewOpen) grid.currentIndex = tile.index
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) root.pick(tile);
                    else root.previewTile(tile);
                }
            }

            V2.IconButton {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: root.s(8)
                size: root.s(28)
                cornerRadius: Radius.inner(root.s(6), root.s(12))
                buttonIcon: "\u{f06d0}"
                iconFontSize: root.s(15)
                centerInk: true
                accentColor: Qt.alpha(theme.base, 0.85)
                textColor: theme.text
                opacity: (ma.containsMouse || tile.current) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                onClicked: root.previewTile(tile)
            }
        }
    }
}
