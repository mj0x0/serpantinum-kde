// Settings in serpantinum v2's guide look (guide/GuidePopup.qml): a centred card, the
// sidebar with a gliding highlight, one page per tab or subtab, and a search over every row.

import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: window
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width; currentHeight: Screen.height }
    MatugenColors { id: _theme }

    function s(v) { return scaler.s(v) }

    readonly property color base:     _theme.base
    readonly property color mantle:   _theme.mantle
    readonly property color crust:    _theme.crust
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color accent:   _theme.mauve

    // Accent roles offered as pickable tints.
    readonly property color mauve:    _theme.mauve
    readonly property color sapphire: _theme.sapphire
    readonly property color green:    _theme.green
    readonly property color yellow:   _theme.yellow
    readonly property color peach:    _theme.peach
    readonly property color pink:     _theme.pink
    readonly property color red:      _theme.red

    readonly property string fontFamily: Fonts.ui
    readonly property string glyphFamily: "Iosevka Nerd Font"

    // Nerd Font MDI glyphs keep a one-cell advance but ink past it, so centring the
    // advance box lands them right of centre. boundingRect IS the advance box (always
    // centred, i.e. no nudge at all) — the ink is tightBoundingRect.
    FontMetrics { id: glyphMetrics; font.family: window.glyphFamily; font.pixelSize: window.s(16) }
    function glyphNudge(g, px) {
        if (!g) return 0;
        var br = glyphMetrics.tightBoundingRect(g);
        var dx = glyphMetrics.advanceWidth(g) / 2 - (br.x + br.width / 2);
        return Math.round(dx * (px === undefined ? 1 : px / window.s(16)));
    }

    // Set by SettingsWindow when the card sits flush on a screen edge: that side goes square.
    property string attachEdge: ""
    property real cardRadius: Radius.eased(s(18))
    readonly property bool flush: attachEdge !== ""
    readonly property real radiusTL: (attachEdge === "top"    || attachEdge === "left")  ? 0 : cardRadius
    readonly property real radiusTR: (attachEdge === "top"    || attachEdge === "right") ? 0 : cardRadius
    readonly property real radiusBL: (attachEdge === "bottom" || attachEdge === "left")  ? 0 : cardRadius
    readonly property real radiusBR: (attachEdge === "bottom" || attachEdge === "right") ? 0 : cardRadius

    property int currentTab: 0
    property int currentSubTab: 0
    property int expandedTab: -1

    readonly property var tabsModel: [
        { key: "general",       name: "General",           icon: "\u{f0493}", file: "pages/GeneralPage.qml" },
        { key: "appearance",    name: "Appearance",        icon: "\u{f0765}", file: "pages/AppearancePage.qml" },
        { key: "bar",           name: "Bar",               icon: "\u{f0309}", separatorBefore: true,
          subtabs: [
            { key: "bar_general", name: "General", icon: "\u{f035c}", file: "pages/BarPage.qml" },
            { key: "bar_modules", name: "Modules", icon: "\u{f12a8}", file: "pages/BarModulesPage.qml" },
            { key: "tray",        name: "Tray",    icon: "\u{f0f1d}", file: "pages/TrayPage.qml" }
          ] },
        { key: "notifications", name: "Notifications",     icon: "\u{f009a}", file: "pages/NotificationsPage.qml" },
        { key: "launcher",      name: "Launcher",          icon: "\u{f0349}", file: "pages/LauncherPage.qml" },
        { key: "dock",          name: "Dock",              icon: "\u{f10a9}", file: "pages/DockPage.qml" },
        { key: "osd",           name: "On-Screen Display", icon: "\u{f057e}", file: "pages/OsdPage.qml" },
        { key: "wallpaper",     name: "Wallpaper",         icon: "\u{f05e2}", file: "pages/WallpaperPage.qml" },
        { key: "capture",       name: "Capture",           icon: "\u{f0100}",
          subtabs: [
            { key: "screenshot", name: "Screenshot",       icon: "\u{f0e51}", file: "pages/CapturePage.qml" },
            { key: "ocr",        name: "Text recognition", icon: "\u{f113d}", file: "pages/OcrPage.qml" },
            { key: "recording",  name: "Recording",        icon: "\u{f0567}", file: "pages/RecordingPage.qml" }
          ] },
        { key: "music",         name: "Music",             icon: "\u{f075a}", separatorBefore: true, file: "pages/MusicPage.qml" },
        { key: "calendar",      name: "Calendar",          icon: "\u{f00ed}", file: "pages/CalendarPage.qml" },
        { key: "weather",       name: "Weather",           icon: "\u{f0590}", file: "pages/WeatherPage.qml" },
        { key: "network",       name: "Network",           icon: "\u{f0317}", file: "pages/NetworkPage.qml" },
        { key: "system",        name: "System",            icon: "\u{f0ad1}", separatorBefore: true, file: "pages/SystemPage.qml" }
    ]

    readonly property var currentTabModel: tabsModel[currentTab] || null
    readonly property bool hasSubTabs: !!(currentTabModel && currentTabModel.subtabs && currentTabModel.subtabs.length > 0)

    // --- search ---------------------------------------------------------------
    property bool searchActive: false
    property string searchQuery: ""
    property int searchSelectedIndex: -1
    property string highlightedSettingId: ""
    property int highlightToken: 0
    property var pendingHighlightItem: null

    property var searchIndexMap: ({})
    property var searchIndex: []

    function searchHaystack(item) {
        if (item.hay === undefined) {
            item.hay = [
                item.title, item.desc,
                resolveTabTitle(item.tab), resolveSubtabTitle(item.tab, item.subtab),
                item.tab, item.subtab, item.keywords
            ].join("\n").toLowerCase();
        }
        return item.hay;
    }

    function resolveTabTitle(tabKey) {
        if (!tabKey) return "";
        let cleanKey = String(tabKey).trim().toLowerCase();
        for (let i = 0; i < tabsModel.length; i++) {
            let t = tabsModel[i];
            if (t.key.toLowerCase() === cleanKey || t.name.toLowerCase() === cleanKey) return t.name;
        }
        return String(tabKey).trim();
    }

    function resolveSubtabTitle(tabKey, subtabKey) {
        if (!subtabKey) return "";
        let cleanSub = String(subtabKey).trim().toLowerCase();
        let cleanTab = String(tabKey || "").trim().toLowerCase();
        for (let i = 0; i < tabsModel.length; i++) {
            let t = tabsModel[i];
            if (cleanTab === "" || t.key.toLowerCase() === cleanTab || t.name.toLowerCase() === cleanTab) {
                if (t.subtabs) {
                    let st = t.subtabs.find(x => x.key.toLowerCase() === cleanSub || x.name.toLowerCase() === cleanSub);
                    if (st) return st.name;
                }
            }
        }
        return String(subtabKey).trim();
    }

    // A tab by key or name, a subtab by key, name or index under it, or a bare subtab name.
    function resolveIndices(tabKey, subKey) {
        if (!tabKey) return { tabIndex: -1, subIndex: -1 };
        let lower = String(tabKey).toLowerCase();
        for (let i = 0; i < tabsModel.length; i++) {
            let t = tabsModel[i];
            if (t.key.toLowerCase() === lower || t.name.toLowerCase() === lower) {
                let sIdx = -1;
                if (subKey !== undefined && subKey !== null && subKey !== "") {
                    let sLower = String(subKey).toLowerCase();
                    let sNum = parseInt(subKey);
                    if (!isNaN(sNum) && t.subtabs && sNum >= 0 && sNum < t.subtabs.length) {
                        sIdx = sNum;
                    } else if (t.subtabs) {
                        sIdx = t.subtabs.findIndex(st => st.key.toLowerCase() === sLower || st.name.toLowerCase() === sLower);
                    }
                }
                return { tabIndex: i, subIndex: sIdx };
            }
            if (t.subtabs) {
                let sIdx = t.subtabs.findIndex(st => st.key.toLowerCase() === lower || st.name.toLowerCase() === lower);
                if (sIdx !== -1) return { tabIndex: i, subIndex: sIdx };
            }
        }
        return { tabIndex: -1, subIndex: -1 };
    }

    function resolveTargetLocation(target) {
        let tabIdx = -1;
        let subIdx = -1;
        if (!target) return { tabIndex: tabIdx, subIndex: subIdx };
        try {
            let p = target.parent;
            while (p) {
                if (subIdx === -1 && p.subTabIndex !== undefined && p.subTabIndex !== null && p.subTabIndex >= 0) {
                    subIdx = p.subTabIndex;
                }
                if (tabIdx === -1 && p.tabIndex !== undefined && p.tabIndex !== null && p.tabIndex >= 0) {
                    tabIdx = p.tabIndex;
                }
                p = p.parent;
            }
        } catch(e) {
            return { tabIndex: -1, subIndex: -1 };
        }
        if (tabIdx >= tabsModel.length) tabIdx = -1;
        return { tabIndex: tabIdx, subIndex: subIdx };
    }

    function normalizeSearchEntry(entry) {
        if (!entry) return null;
        let id = String(entry.id || entry.title || "").trim();
        if (!id) return null;
        let norm = s => String(s || "").trim().toLowerCase();
        let cleanTab = norm(entry.tab);
        let cleanSubtab = norm(entry.subtab);

        let indices = resolveIndices(entry.tab, entry.subtab);
        if (indices.tabIndex >= 0) {
            let tModel = tabsModel[indices.tabIndex];
            cleanTab = norm(tModel.key);
            if (indices.subIndex >= 0 && tModel.subtabs && indices.subIndex < tModel.subtabs.length) {
                cleanSubtab = norm(tModel.subtabs[indices.subIndex].key);
            }
        }

        return {
            key: cleanTab + "|" + cleanSubtab + "|" + id.toLowerCase(),
            id: id,
            title: String(entry.title || "").trim(),
            desc: String(entry.desc || "").trim(),
            tab: cleanTab,
            subtab: cleanSubtab,
            icon: String(entry.icon || "\u{f0493}").trim(),
            keywords: entry.keywords || "",
            target: entry.target || null
        };
    }

    function registerSearchItem(entry) {
        let item = normalizeSearchEntry(entry);
        if (!item) return;
        searchIndexMap[item.key] = item;
        searchRebuildTimer.restart();
    }

    function unregisterSearchItem(key) {
        if (!key) return;
        if (searchIndexMap[key]) {
            delete searchIndexMap[key];
            searchRebuildTimer.restart();
        }
    }

    function rebuildSearchIndex() {
        let list = [];
        for (let k in searchIndexMap) {
            list.push(searchIndexMap[k]);
        }
        searchIndex = list;
    }

    readonly property var filteredSearchResults: {
        let q = searchQuery.trim().toLowerCase();
        if (q === "") return [];
        let hits = [];
        for (let i = 0; i < searchIndex.length; i++) {
            let item = searchIndex[i];
            if (searchHaystack(item).indexOf(q) === -1) continue;
            let title = String(item.title).toLowerCase();
            let at = title.indexOf(q);
            hits.push({ item: item, rank: title === q ? 0 : (at === 0 ? 1 : (at > 0 ? 2 : 3)) });
        }
        if (hits.length > 60) {
            hits.sort((a, b) => a.rank - b.rank);
            hits = hits.slice(0, 60);
        }
        return hits.map(h => h.item);
    }

    readonly property var groupedSearchResults: {
        let results = filteredSearchResults;
        if (results.length === 0) return [];

        let tabGroupsMap = {};

        for (let i = 0; i < results.length; i++) {
            let item = results[i];
            let indices = resolveIndices(item.tab, item.subtab);
            let tIdx = indices.tabIndex !== -1 ? indices.tabIndex : 9999;
            let sIdx = indices.subIndex;

            if (!tabGroupsMap[tIdx]) {
                let isKnown = tIdx >= 0 && tIdx < tabsModel.length;
                let tModel = isKnown ? tabsModel[tIdx] : null;
                tabGroupsMap[tIdx] = {
                    tabKey: isKnown ? tModel.key : item.tab,
                    tabIndex: tIdx,
                    title: isKnown ? tModel.name : "General",
                    icon: isKnown ? tModel.icon : "\u{f0493}",
                    directItems: [],
                    subgroupsMap: {}
                };
            }

            let tg = tabGroupsMap[tIdx];
            let isKnown = tIdx >= 0 && tIdx < tabsModel.length;
            let tModel = isKnown ? tabsModel[tIdx] : null;

            if (sIdx >= 0 && isKnown && tModel.subtabs && sIdx < tModel.subtabs.length) {
                let stModel = tModel.subtabs[sIdx];
                if (!tg.subgroupsMap[sIdx]) {
                    tg.subgroupsMap[sIdx] = {
                        subKey: stModel.key,
                        subIndex: sIdx,
                        title: stModel.name,
                        icon: stModel.icon,
                        items: []
                    };
                }
                tg.subgroupsMap[sIdx].items.push(item);
            } else {
                tg.directItems.push(item);
            }
        }

        let sortedGroups = Object.values(tabGroupsMap).map(tg => {
            let subList = Object.values(tg.subgroupsMap);
            subList.sort((a, b) => a.subIndex - b.subIndex);
            return {
                tabKey: tg.tabKey,
                tabIndex: tg.tabIndex,
                title: tg.title,
                icon: tg.icon,
                directItems: tg.directItems,
                subgroups: subList
            };
        });

        sortedGroups.sort((a, b) => a.tabIndex - b.tabIndex);
        return sortedGroups;
    }

    readonly property var flatSearchResults: {
        let groups = groupedSearchResults;
        if (!groups || groups.length === 0) return [];
        let list = [];
        for (let i = 0; i < groups.length; i++) {
            let tg = groups[i];
            for (let d = 0; d < tg.directItems.length; d++) {
                list.push(tg.directItems[d]);
            }
            for (let s = 0; s < tg.subgroups.length; s++) {
                let sg = tg.subgroups[s];
                for (let k = 0; k < sg.items.length; k++) {
                    list.push(sg.items[k]);
                }
            }
        }
        return list;
    }

    function navigateSearch(dir) {
        let count = flatSearchResults.length;
        if (count === 0) return;
        searchSelectedIndex = Math.max(0, Math.min(count - 1, searchSelectedIndex + dir));
    }

    function activateSelectedSearch() {
        let count = flatSearchResults.length;
        if (count === 0) return;
        let item = (searchSelectedIndex >= 0 && searchSelectedIndex < count)
            ? flatSearchResults[searchSelectedIndex]
            : flatSearchResults[0];
        if (item) {
            selectSearchResult(item);
        }
    }

    function ensureSearchItemVisible(itemObj) {
        if (!itemObj || !contentArea.searchResults) return;
        try {
            let mapped = itemObj.mapToItem(contentArea.searchResults.column, 0, 0);
            let itemY = mapped.y;
            let itemH = itemObj.height;
            let viewTop = contentArea.searchResults.contentY;
            let viewHeight = contentArea.searchResults.height;
            let viewBottom = viewTop + viewHeight;

            if (itemY < viewTop) {
                contentArea.searchResults.contentY = Math.max(0, itemY - window.s(8));
            } else if (itemY + itemH > viewBottom) {
                let maxScroll = Math.max(0, contentArea.searchResults.contentHeight - viewHeight);
                contentArea.searchResults.contentY = Math.min(maxScroll, itemY + itemH - viewHeight + window.s(8));
            }
        } catch(e) {}
    }

    function ensureTabVisible(idx) {
        if (!sidebar.tabsView || idx < 0 || !sidebar.tabsItems || idx >= sidebar.tabsItems.count) return;
        let item = sidebar.tabsItems.itemAt(idx);
        if (!item) return;
        let view = sidebar.tabsView;
        if (item.y < view.contentY) {
            view.contentY = Math.max(0, item.y - s(8));
        } else if (item.y + item.height > view.contentY + view.height) {
            view.contentY = Math.min(Math.max(0, view.contentHeight - view.height), item.y + item.height - view.height + s(8));
        }
    }

    function triggerHighlight(settingId) {
        highlightedSettingId = settingId;
        highlightToken++;
    }

    function openSearch() {
        searchRebuildTimer.stop();
        rebuildSearchIndex();
        searchClearTimer.stop();
        searchActive = true;
        searchSelectedIndex = 0;
        searchFocusTimer.restart();
    }

    function closeSearch() {
        if (!searchActive) return;
        searchActive = false;
        searchSelectedIndex = -1;
        window.forceActiveFocus();
        searchClearTimer.restart();
    }

    function selectSearchResult(item) {
        if (!item) return;

        let loc = resolveTargetLocation(item.target);
        if (loc.tabIndex >= 0) {
            gotoTab(String(loc.tabIndex), loc.subIndex >= 0 ? String(loc.subIndex) : "");
        } else {
            gotoTab(item.tab, item.subtab);
        }

        pendingHighlightItem = item;
        highlightTimer.restart();
        closeSearch();
    }

    function runPendingHighlight() {
        let item = pendingHighlightItem;
        pendingHighlightItem = null;
        if (!item) return;

        let handled = false;
        if (item.target) {
            try {
                if (typeof item.target.triggerHighlightAnimation === "function") {
                    item.target.triggerHighlightAnimation();
                    handled = true;
                }
            } catch(e) {
                handled = false;
            }
        }
        if (!handled) {
            triggerHighlight(item.id);
        }
    }

    // --- navigation -----------------------------------------------------------
    function gotoTab(tabName, subTabName) {
        if (tabName === undefined || tabName === null || tabName === "") return;
        tabName = String(tabName);
        if (!subTabName && tabName.indexOf(":") !== -1) {
            let parts = tabName.split(":");
            tabName = parts[0];
            subTabName = parts[1];
        }
        let r = resolveIndices(tabName, subTabName);
        let num = parseInt(tabName);
        if (r.tabIndex < 0 && !isNaN(num) && num >= 0 && num < tabsModel.length) {
            let t = tabsModel[num];
            let sNum = parseInt(subTabName);
            r = { tabIndex: num, subIndex: (!isNaN(sNum) && t.subtabs && sNum >= 0 && sNum < t.subtabs.length) ? sNum : 0 };
        }
        if (r.tabIndex < 0) return;
        currentTab = r.tabIndex;
        let t = tabsModel[r.tabIndex];
        expandedTab = (t.subtabs && t.subtabs.length > 0) ? r.tabIndex : -1;
        currentSubTab = Math.max(0, r.subIndex);
    }

    function nextTab() {
        let parentTab = tabsModel[currentTab];
        if (parentTab && parentTab.subtabs && parentTab.subtabs.length > 0 && expandedTab === currentTab) {
            if (currentSubTab < parentTab.subtabs.length - 1) {
                currentSubTab++;
                return;
            }
        }
        currentTab = (currentTab + 1) % tabsModel.length;
        let nextParent = tabsModel[currentTab];
        if (nextParent && nextParent.subtabs && nextParent.subtabs.length > 0) {
            expandedTab = currentTab;
            currentSubTab = 0;
        } else {
            expandedTab = -1;
            currentSubTab = 0;
        }
    }

    function prevTab() {
        let parentTab = tabsModel[currentTab];
        if (parentTab && parentTab.subtabs && parentTab.subtabs.length > 0 && expandedTab === currentTab) {
            if (currentSubTab > 0) {
                currentSubTab--;
                return;
            }
        }
        currentTab = (currentTab - 1 + tabsModel.length) % tabsModel.length;
        let prevParent = tabsModel[currentTab];
        if (prevParent && prevParent.subtabs && prevParent.subtabs.length > 0) {
            expandedTab = currentTab;
            currentSubTab = prevParent.subtabs.length - 1;
        } else {
            expandedTab = -1;
            currentSubTab = 0;
        }
    }

    function focusInContent() {
        let f = window.Window.window ? window.Window.window.activeFocusItem : null;
        return !!f && f !== window;
    }

    function moveFocus(forward) {
        let next = window.Window.window.activeFocusItem.nextItemInFocusChain(forward);
        if (next && next !== window) next.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
    }

    function scrollIntoView(item) {
        if (!item) return;
        let p = item.parent;
        while (p) {
            if (p.contentY !== undefined && p.contentItem !== undefined && p.contentHeight !== undefined) {
                let y = item.mapToItem(p.contentItem, 0, 0).y;
                let margin = s(24);
                if (y < p.contentY + margin) {
                    p.contentY = Math.max(0, y - margin);
                } else if (y + item.height > p.contentY + p.height - margin) {
                    p.contentY = Math.min(Math.max(0, p.contentHeight - p.height), y + item.height - p.height + margin);
                }
                return;
            }
            p = p.parent;
        }
    }

    function activeFlickable() {
        let queue = [contentArea];
        while (queue.length > 0) {
            let it = queue.shift();
            if (it.visible === false) continue;
            if (it !== contentArea && it.contentY !== undefined && it.contentHeight !== undefined && it.contentItem !== undefined) return it;
            for (let i = 0; i < it.children.length; i++) queue.push(it.children[i]);
        }
        return null;
    }

    function scrollPage(kind) {
        let f = activeFlickable();
        if (!f) return;
        let maxY = Math.max(0, f.contentHeight - f.height);
        let y = f.contentY;
        if (kind === "down") y += f.height * 0.9;
        else if (kind === "up") y -= f.height * 0.9;
        else if (kind === "home") y = 0;
        else if (kind === "end") y = maxY;
        f.contentY = Math.max(0, Math.min(maxY, y));
    }

    // The host owns Escape and asks us first; true means it was ours.
    function handleEscape() {
        if (searchActive) {
            if (searchQuery !== "") {
                searchQuery = "";
                if (contentArea.searchInput) contentArea.searchInput.text = "";
            } else {
                closeSearch();
            }
            return true;
        }
        if (focusInContent()) {
            window.forceActiveFocus();
            return true;
        }
        return false;
    }

    Timer {
        id: searchFocusTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (contentArea.searchInput) {
                contentArea.searchInput.forceInputFocus();
            }
        }
    }

    Timer {
        id: highlightTimer
        interval: 160
        repeat: false
        onTriggered: window.runPendingHighlight()
    }

    Timer {
        id: searchClearTimer
        interval: 900
        repeat: false
        onTriggered: {
            window.searchQuery = "";
            if (contentArea.searchInput) contentArea.searchInput.text = "";
        }
    }

    Timer {
        id: searchRebuildTimer
        interval: 30
        repeat: false
        onTriggered: window.rebuildSearchIndex()
    }

    Shortcut {
        sequences: [StandardKey.Find, "Ctrl+K"]
        onActivated: window.openSearch()
    }

    Shortcut {
        sequences: ["Ctrl+PgDown", "Ctrl+Tab"]
        onActivated: window.nextTab()
    }

    Shortcut {
        sequences: ["Ctrl+PgUp", "Ctrl+Shift+Tab"]
        onActivated: window.prevTab()
    }

    Shortcut {
        sequences: [StandardKey.Close, "Ctrl+Q"]
        onActivated: SettingsState.hide()
    }

    Connections {
        target: window.Window.window
        function onActiveFocusItemChanged() {
            let f = window.Window.window.activeFocusItem;
            if (f && f !== window) window.scrollIntoView(f);
        }
    }

    Keys.onPressed: (event) => {
        let plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
        if (event.key === Qt.Key_Escape) {
            if (!window.handleEscape()) SettingsState.hide();
            event.accepted = true;
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            let dir = event.key === Qt.Key_Down ? 1 : -1;
            if (window.searchActive) window.navigateSearch(dir);
            else if (window.focusInContent()) window.moveFocus(dir > 0);
            else if (dir > 0) window.nextTab();
            else window.prevTab();
            event.accepted = true;
        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && plain) {
            let dir = event.key === Qt.Key_Right ? 1 : -1;
            if (!window.searchActive && !window.focusInContent()) { if (dir > 0) window.nextTab(); else window.prevTab(); }
            event.accepted = !window.searchActive;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && window.searchActive) {
            window.activateSelectedSearch();
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            let forward = event.key === Qt.Key_Tab;
            if (window.searchActive) window.navigateSearch(forward ? 1 : -1);
            else if (forward) window.nextTab();
            else window.prevTab();
            event.accepted = true;
        } else if (!window.searchActive && !window.focusInContent()) {
            if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Space) window.scrollPage("down");
            else if (event.key === Qt.Key_PageUp) window.scrollPage("up");
            else if (event.key === Qt.Key_Home) window.scrollPage("home");
            else if (event.key === Qt.Key_End) window.scrollPage("end");
            else if (event.key === Qt.Key_Slash || (plain && event.text.length === 1 && event.text >= " " && event.text !== " ")) {
                window.openSearch();
                if (event.key !== Qt.Key_Slash && contentArea.searchInput) {
                    contentArea.searchInput.text = event.text;
                    window.searchQuery = event.text;
                }
            } else return;
            event.accepted = true;
        }
    }

    onCurrentTabChanged: ensureTabVisible(currentTab)

    // Deep link: SettingsState.section names a tab or subtab, matched case-insensitively.
    Component.onCompleted: { gotoTab(SettingsState.section); intro.start(); }
    Connections {
        target: SettingsState
        function onSectionChanged() { window.gotoTab(SettingsState.section) }
    }

    // v2's guide intro: the card settles, the sidebar slides in, tabs stagger, content rises.
    property real introBase: 0
    property real introSidebar: 0
    property real introTabs: 0
    property real introContent: 0

    function getTabProgress(idx) {
        if (introTabs >= 1) return 1;
        if (introTabs <= 0) return 0;
        var p = Math.min(1, Math.max(0, (introTabs - idx * 0.04) / 0.42));
        if (p <= 0) return 0;
        if (p >= 1) return 1;
        var c1 = 0.85, c3 = c1 + 1;
        return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2);
    }
    function getTabOpacity(idx) {
        if (introTabs >= 1) return 1;
        if (introTabs <= 0) return 0;
        return Math.min(1, Math.max(0, (introTabs - idx * 0.04) / 0.28));
    }

    ParallelAnimation {
        id: intro
        NumberAnimation { target: window; property: "introBase"; from: 0; to: 1; duration: 650; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 60 }
            NumberAnimation { target: window; property: "introSidebar"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTabs"; from: 0; to: 1; duration: 550 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: window; property: "introContent"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
        }
    }

    Item {
        anchors.fill: parent
        opacity: window.introBase
        scale: window.flush ? 1 : 0.95 + 0.05 * window.introBase

        Rectangle {
            anchors.fill: parent
            color: window.base
            radius: window.cardRadius
            topLeftRadius: window.radiusTL
            topRightRadius: window.radiusTR
            bottomLeftRadius: window.radiusBL
            bottomRightRadius: window.radiusBR
            border.color: window.surface0
            border.width: window.flush ? 0 : 1

            SettingsSidebar {
                id: sidebar
                popup: window
            }

            SettingsContent {
                id: contentArea
                popup: window
                x: sidebar.width
                width: Math.max(0, parent.width - sidebar.width)
                height: parent.height
            }
        }
    }
}
