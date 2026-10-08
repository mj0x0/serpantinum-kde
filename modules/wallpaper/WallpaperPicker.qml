import "../../services/caching"
import "../../services/wallpaper"
import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import "picker"
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Qt.labs.folderlistmodel
import QtMultimedia
import Quickshell
import Quickshell.Io

Item {
    id: window
    width: Screen.width

    Caching { id: paths }

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    
    function s(val) { 
        return scaler.s(val); 
    }

    MatugenColors { id: _theme }

    readonly property Item view: viewLoader.item
    readonly property string pickerStyle: ShellSettings.pickerStyle
    readonly property var theme: _theme
    // Filter bar top margin + height + gap.
    readonly property real contentTop: window.s(40) + window.s(56) + window.s(18)
    // The popup host honours this; Slices keeps the registry's 650, the grid and the fan need more.
    readonly property real targetMasterHeight: window.pickerStyle === "wall" ? Math.min(Screen.height * 0.88, window.s(900))
                                             : (window.pickerStyle === "hand" && window.view && window.view.wantedHeight > 0) ? Math.min(Screen.height * 0.88, window.contentTop + window.view.wantedHeight) : 0

    property string widgetArg: ""
    property string targetWallName: ""
    property bool initialFocusSet: false
    property int visibleItemCount: -1
    property int scrollAccum: 0
    property real scrollThreshold: window.s(300)

    property string currentFilter: "All"
    readonly property bool wallhavenMode: window.currentFilter === "Wallhaven"
    readonly property bool wallhavenTyping: wallhavenLoader.item ? wallhavenLoader.item.hasFocus === true : false
    property string _lastFilter: "All"
    property var colorMap: ({})
    property var paletteMap: ({})
    property int cacheVersion: 0 
    
    
    property bool isApplying: false
    property bool isMonitorSelectorOpen: false
    property bool previewing: false
    property bool previewClosing: false
    onPreviewingChanged: {
        if (!window.previewing && previewLoader.item) window.previewClosing = true;
        if (window.previewing && window.wallhavenMode && wallhavenLoader.item) wallhavenLoader.item.requestPreview();
    }
    onPickerStyleChanged: window.previewing = false
    onWallhavenModeChanged: window.previewing = false

    // What the Preview shows: the selected local thumb, or the Wallhaven cursor tile.
    readonly property var localCandidate: {
        const v = window.view;
        if (!v || v.currentIndex < 0 || v.currentIndex >= localProxyModel.count) return null;
        const e = localProxyModel.get(v.currentIndex);
        const fn = "" + e.fileName;
        return {
            key: fn,
            url: "" + e.fileUrl,
            hiUrl: fn.startsWith("000_") ? "" : "file://" + window.srcDir + "/" + window.getCleanName(fn),
            name: window.getCleanName(fn),
            isVideo: fn.startsWith("000_"),
            videoUrl: "file://" + window.srcDir + "/" + window.getCleanName(fn),
            palette: window.paletteMap[fn] || [],
            status: ""
        };
    }
    readonly property var candidate: window.wallhavenMode ? (wallhavenLoader.item ? wallhavenLoader.item.cursor : null) : window.localCandidate

    function localOrigin() {
        return window.view && window.view.selectedRect ? window.view.selectedRect() : null;
    }
    function wallhavenOrigin() {
        const b = wallhavenLoader.item;
        const r = b && b.cursorRect ? b.cursorRect() : null;
        return r ? Qt.rect(r.x + wallhavenLoader.x, r.y + wallhavenLoader.y, r.width, r.height) : null;
    }

    // Separate flag so add-animations fire on new arrivals
    // even before the first focus snap has happened
    property bool allowAddAnimation: false
    
    Timer {
        id: applyUnlockTimer
        interval: 250
        onTriggered: window.isApplying = false
    }
    
    property bool isStartup: localFolderModel.status === FolderListModel.Loading || srcModel.status === FolderListModel.Loading
    property bool isReady: visible && localFolderModel.status === FolderListModel.Ready
    
    property bool isModelChanging: false
    
    property bool jumpToLastOnFilterChange: false

    readonly property var filterData: [
        { name: "All", hex: "", label: "All" },
        { name: "Video", hex: "", label: "Vid" },
        { name: "Red", hex: "#FF4500", label: "" },
        { name: "Orange", hex: "#FFA500", label: "" },
        { name: "Yellow", hex: "#FFD700", label: "" },
        { name: "Green", hex: "#32CD32", label: "" },
        { name: "Blue", hex: "#1E90FF", label: "" },
        { name: "Purple", hex: "#8A2BE2", label: "" },
        { name: "Pink", hex: "#FF69B4", label: "" },
        { name: "Monochrome", hex: "#A9A9A9", label: "" },
        { name: "Wallhaven", hex: "", label: "Wallhaven" } 
    ]

    ListModel { id: monitorModel }

    Process {
        id: monitorProc
        // KDE port: kscreen-doctor replaces hyprctl, reshaped to the same [{name}] array.
        command: ["sh", "-c", "kscreen-doctor -j 2>/dev/null | python3 -c \"import sys,json; d=json.load(sys.stdin); print(json.dumps([{'name': o['name']} for o in d.get('outputs',[]) if o.get('enabled', True)]))\""]
        running: false
        
        stdout: StdioCollector {
            onStreamFinished: {
                let response = this.text;
                if (!response || response.trim().length === 0)
                    return;
                try {
                    var monitors = JSON.parse(response);
                    monitorModel.clear();
                    for (var i = 0; i < monitors.length; i++)
                        monitorModel.append({ "name": monitors[i].name, "selected": true });
                } catch (e) {
                    console.warn("wallpaper picker: kscreen-doctor gave unusable output");
                }
            }
        }
    }

    function loadMonitors() {
        monitorProc.running = true;
    }

    function getMonitorOutputs() {
        if (monitorModel.count <= 1) return "all"; 
        
        let selected = [];
        for (let i = 0; i < monitorModel.count; i++) {
            if (monitorModel.get(i).selected) {
                selected.push(monitorModel.get(i).name);
            }
        }
        
        if (selected.length === 0) return "none";
        if (selected.length === monitorModel.count) return "all";
        
        return selected.join(",");
    }

    function applyWallpaper(safeFileName, isVideo) {
        if (!safeFileName || window.isApplying) return;
        
        let outputs = window.getMonitorOutputs();
        if (outputs === "none") return;
        
        window.isApplying = true;
        applyUnlockTimer.restart();
        
        window.targetWallName = safeFileName;
        let cleanName = window.getCleanName(safeFileName);
        // KDE port: set-wallpaper.py replaces swww/mpvpaper and fires the theming
        // hook itself, so matugen is not run here. Per-output is unwired.
        let reloadScript = Qt.resolvedUrl("../../helpers/wallpaper_reload.sh").toString();

        if (reloadScript.startsWith("file://")) {
            reloadScript = decodeURIComponent(reloadScript.substring(7));
        }

        const escapeBash = (str) => String(str).replace(/(["\\$`])/g, '\\$1');
        const escOutputs = escapeBash(outputs);
        
        // getLogDir() creates the dir, bare logDir does NOT, and bash SKIPS a command whose
        // redirection cannot be opened - so a missing dir silently never set the wallpaper.
        const logDir = paths.getLogDir("wallpaper_picker");
        const logFile = logDir + "/wallpaper_debug.log";
        const escLogDir = escapeBash(logDir);
        
        const originalFile = window.srcDir + "/" + cleanName;
        const thumbFile = paths.getCacheDir("wallpaper_picker") + "/thumbs/" + safeFileName;
        
        const escOriginal = escapeBash(originalFile);
        const escThumb = escapeBash(thumbFile);
        const escReload = escapeBash(reloadScript);

        let wallpaperCmd = "";
        
        WallpaperService.apply(originalFile);
        WallpaperState.hide();

        wallpaperCmd = `
            echo "" >> ${logFile}
            echo "[$(date +'%H:%M:%S.%3N')] APPLYING LOCAL ${isVideo ? "VIDEO" : "IMAGE"}: ${escOriginal} TO ${escOutputs}" >> ${logFile}
        `;

        const fullScript = `
            mkdir -p "${escLogDir}"
            cp "${isVideo ? escThumb : escOriginal}" ${paths.getCacheDir("wallpaper_picker")}/current_wallpaper.png || true
            
            
            ${wallpaperCmd}
            ( bash "${escReload}" || true ) &
        `;
        Quickshell.execDetached(["bash", "-c", fullScript]);
    }
    
    onVisibleChanged: {
        if (!visible) {
            window.initialFocusSet = false;
            window.allowAddAnimation = false;
            window.isApplying = false;
            window.isMonitorSelectorOpen = false;
            window.previewing = false;
            window.previewClosing = false;
        } else {
            window.isFilterAnimating = true;
            filterAnimationTimer.restart();

            window.applyFilters(true);
        }
    }

    property bool isLoading: localFolderModel.status === FolderListModel.Loading ||
                             srcModel.status === FolderListModel.Loading

    property bool showSpinner: !window.wallhavenMode && window.isLoading

    property string currentNotification: {
        if (window.wallhavenMode) return "";
        if (isLoading) return "Generating thumbnails...";
        if (window.visibleItemCount === 0) return "No wallpapers found";
        
        if (window.currentFilter === "All") return "";
        if (window.currentFilter === "Video") return "Videos";
        
        return window.currentFilter;
    }
    
    property bool showNotification: !window.isStartup && currentNotification !== ""

    function getCleanName(name) {
        if (!name) return "";
        let clean = String(name);
        return clean.startsWith("000_") ? clean.substring(4) : clean;
    }

    onWidgetArgChanged: {
        if (widgetArg !== "") {
            targetWallName = widgetArg;
            initialFocusSet = false;
            tryFocus();
        }
    }

    function executeFocusRestore(targetIndex, requirePositioning) {
        if (!window.view) return;
        let targetModel = window.getModelForFilter(window.currentFilter);

        if (targetIndex !== -1 && targetIndex < targetModel.count) {
            window.isModelChanging = true;

            if (requirePositioning) view.snapTo(targetIndex);
            else view.currentIndex = targetIndex;

            window.isModelChanging = false;
            window.initialFocusSet = true;

            // Allow add-animations for future incremental arrivals
            // Use a short delay so the initial snap itself isn't animated
            allowAddAnimationTimer.restart();
        }
    }

    Timer {
        id: allowAddAnimationTimer
        interval: 600
        onTriggered: window.allowAddAnimation = true
    }

    function tryFocus() {
        if (initialFocusSet) return;

        if (localProxyModel.count > 0) {
            let foundIndex = -1;
            let cleanTarget = window.getCleanName(targetWallName);

            if (cleanTarget !== "") {
                for (let i = 0; i < localProxyModel.count; i++) {
                    let fname = localProxyModel.get(i).fileName || "";
                    if (window.getCleanName(fname) === cleanTarget) {
                        foundIndex = i;
                        break;
                    }
                }
            }

            let finalIndex = foundIndex !== -1 ? foundIndex : 0;
            window.executeFocusRestore(finalIndex, true);
        }
    }
    
    function getModelForFilter(filter) {
        return localProxyModel;
    }

    function updateVisibleCount() {
        let targetModel = window.getModelForFilter(window.currentFilter);
        
        if (!targetModel || targetModel.count === 0) {
            window.visibleItemCount = 0;
            return;
        }
        let count = 0;
        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                count++;
            }
        }
        window.visibleItemCount = count;
    }

    readonly property string homeDir: "file://" + Quickshell.env("HOME")
    readonly property string thumbDir: "file://" + paths.getCacheDir("wallpaper_picker") + "/thumbs"
    // ShellSettings knob first, then the env var the original used, then the default.
    readonly property string srcDir: {
        const knob = ShellSettings.wallpaperDir
        if (knob && knob !== "") return knob
        const dir = Quickshell.env("WALLPAPER_DIR")
        return (dir && dir !== "")
        ? dir
        : Quickshell.env("HOME") + "/Pictures/Wallpapers"
    }

    readonly property real itemWidth: window.s(400)
    readonly property real itemHeight: window.s(420)
    readonly property real borderWidth: window.s(3)
    readonly property real spacing: window.s(10)
    readonly property real skewFactor: -0.35

    Timer {
        id: scrollThrottle
        interval: 150
    }

    property bool isFilterAnimating: false
    Timer {
        id: filterAnimationTimer
        interval: 800
        onTriggered: window.isFilterAnimating = false
    }

    property bool isItemAnimating: false
    Timer {
        id: itemAnimationTimer
        interval: 500
        onTriggered: window.isItemAnimating = false
    }

    function noteItemMove() {
        window.isItemAnimating = true;
        itemAnimationTimer.restart();
    }

    function wheelStep(delta) {
        if (scrollThrottle.running) return;
        window.scrollAccum += delta;
        if (Math.abs(window.scrollAccum) >= window.scrollThreshold) {
            window.stepToNextValidIndex(window.scrollAccum > 0 ? -1 : 1);
            window.scrollAccum = 0;
            scrollThrottle.start();
        }
    }

    function visibleIndexList() {
        const m = window.getModelForFilter(window.currentFilter);
        const out = [];
        if (!m) return out;
        for (let i = 0; i < m.count; i++) {
            const fname = m.get(i).fileName || "";
            if (window.checkItemMatchesFilter(fname, fname.startsWith("000_"), window.cacheVersion, window.currentFilter)) out.push(i);
        }
        return out;
    }

    function getHexBucket(hexStr) {
        if (!hexStr) return "Monochrome";
        
        hexStr = String(hexStr).trim().replace(/#/g, '');
        if (hexStr.length > 6) hexStr = hexStr.substring(0, 6);
        if (hexStr.length !== 6) return "Monochrome";

        let r = parseInt(hexStr.substring(0,2), 16) / 255;
        let g = parseInt(hexStr.substring(2,4), 16) / 255;
        let b = parseInt(hexStr.substring(4,6), 16) / 255;

        if (isNaN(r) || isNaN(g) || isNaN(b)) return "Monochrome";

        let max = Math.max(r, g, b), min = Math.min(r, g, b);
        let d = max - min;
        
        let h = 0;
        let s = max === 0 ? 0 : d / max;
        let v = max;

        if (max !== min) {
            if (max === r) {
                h = (g - b) / d + (g < b ? 6 : 0);
            } else if (max === g) {
                h = (b - r) / d + 2;
            } else {
                h = (r - g) / d + 4;
            }
            h /= 6;
        }
        h = h * 360;

        if (s < 0.05 || v < 0.08) return "Monochrome";

        if (h >= 345 || h < 15) return "Red";
        if (h >= 15 && h < 45) return "Orange";
        if (h >= 45 && h < 75) return "Yellow";
        if (h >= 75 && h < 165) return "Green";
        if (h >= 165 && h < 260) return "Blue";
        if (h >= 260 && h < 315) return "Purple";
        if (h >= 315 && h < 345) return "Pink";

        return "Monochrome";
    }

    function checkItemMatchesFilter(fileName, isVid, cv, filter) {
        if (filter === "All") return true;
        if (filter === "Video") return isVid;
        
        let hexColor = window.colorMap[String(fileName)];
        if (!hexColor) return filter === "Monochrome";
        
        return window.getHexBucket(hexColor) === filter;
    }

    FolderListModel {
        id: markerModel
        folder: "file://" + paths.getCacheDir("wallpaper_picker") + "/colors_markers"
        showDirs: false
        nameFilters: ["*_HEX_*", "*_PAL_*"]
        
        onCountChanged: window.processMarkers()
        onStatusChanged: {
            if (status === FolderListModel.Ready) window.processMarkers()
        }
    }

    FolderListModel {
        id: srcModel
        folder: "file://" + window.srcDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
    }

    function processMarkers() {
        let newMap = {};
        let newPal = {};
        for (let i = 0; i < markerModel.count; i++) {
            let markerName = markerModel.get(i, "fileName") || "";
            if (!markerName) continue;

            let palIdx = markerName.lastIndexOf("_PAL_");
            if (palIdx !== -1) {
                newPal[markerName.substring(0, palIdx)] = markerName.substring(palIdx + 5).split("-").map(h => "#" + h);
                continue;
            }
            let splitIdx = markerName.lastIndexOf("_HEX_");
            if (splitIdx !== -1) {
                let fName = markerName.substring(0, splitIdx);
                let hexCode = markerName.substring(splitIdx + 5);
                newMap[fName] = "#" + hexCode;
            }
        }
        window.colorMap = newMap;
        window.paletteMap = newPal;
        window.cacheVersion++;
        window.updateVisibleCount();
    }

    function triggerColorExtraction() {
        const extractScript = `
            COLOR_DIR="${paths.getCacheDir('wallpaper_picker')}/colors_markers"
            THUMBS="${paths.getCacheDir('wallpaper_picker')}/thumbs"
            CSV="${paths.getCacheDir('wallpaper_picker')}/colors.csv"
            
            mkdir -p "$COLOR_DIR"
            
            if [ -f "$CSV" ]; then
                while IFS=, read -r fname hexcode; do
                    cleanhex=$(echo "$hexcode" | tr -d '\r#' | cut -c 1-6)
                    if [ -n "$cleanhex" ] && [ -n "$fname" ]; then
                        touch "$COLOR_DIR/$fname""_HEX_$cleanhex" 2>/dev/null
                    fi
                done < "$CSV"
                mv "$CSV" "$CSV.bak" 2>/dev/null
            fi
            
            if command -v magick &> /dev/null; then CMD="magick"; else CMD="convert"; fi
            
            for file in "$THUMBS"/*; do
                if [ -f "$file" ]; then
                    filename=$(basename "$file")
                    found=0
                    for marker in "$COLOR_DIR/$filename"_HEX_*; do
                        if [ -e "$marker" ]; then found=1; break; fi
                    done
                    
                    if [ $found -eq 0 ]; then
                        hex=$($CMD "$file" -modulate 100,200 -resize "1x1^" -gravity center -extent 1x1 -depth 8 -format "%[hex:p{0,0}]" info:- 2>/dev/null | grep -oE '[0-9A-Fa-f]{6}' | head -n 1)
                        if [ -n "$hex" ]; then
                            touch "$COLOR_DIR/$filename""_HEX_$hex"
                        fi
                    fi

                    pal=0
                    for marker in "$COLOR_DIR/$filename"_PAL_*; do
                        if [ -e "$marker" ]; then pal=1; break; fi
                    done
                    if [ $pal -eq 0 ]; then
                        pals=$($CMD "$file" -resize 100x100 -colors 5 -depth 8 -format '%c' histogram:info:- 2>/dev/null | sort -rn | grep -oE '#[0-9A-Fa-f]{6}' | head -n 5 | tr -d '#' | paste -sd- -)
                        if [ -n "$pals" ]; then
                            touch "$COLOR_DIR/$filename""_PAL_$pals"
                        fi
                    fi
                fi
            done
        `;
        Quickshell.execDetached(["bash", "-c", extractScript]);
    }

    function stepToNextValidIndex(direction) {
        if (!window.view) return;
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (!targetModel || targetModel.count === 0) return;
        
        let start = view.currentIndex;
        let found = -1;

        if (direction === 1) {
            for (let i = start + 1; i < targetModel.count; i++) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        } else {
            for (let i = start - 1; i >= 0; i--) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        }

        if (found !== -1) {
            view.currentIndex = found;
            return;
        }

        let filterOrder = ["All", "Video", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Monochrome"];
        let currentFilterIdx = filterOrder.indexOf(window.currentFilter);

        if (currentFilterIdx === -1) {
            let current = start;
            for (let i = 0; i < targetModel.count; i++) {
                current = (current + direction + targetModel.count) % targetModel.count;
                let fname = targetModel.get(current).fileName || "";
                let isVid = fname.startsWith("000_");
                
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    view.currentIndex = current;
                    return;
                }
            }
            return;
        }

        let nextFilterIdx = currentFilterIdx + direction;

        if (nextFilterIdx >= 0 && nextFilterIdx < filterOrder.length) {
            window.jumpToLastOnFilterChange = (direction === -1);
            window.currentFilter = filterOrder[nextFilterIdx];
        }
    }

    function cycleFilter(direction) {
        let currentIdx = -1;
        for (let i = 0; i < window.filterData.length; i++) {
            if (window.filterData[i].name === window.currentFilter) {
                currentIdx = i;
                break;
            }
        }
        
        if (currentIdx !== -1) {
            let nextIdx = (currentIdx + direction + window.filterData.length) % window.filterData.length;
            window.currentFilter = window.filterData[nextIdx].name;
        }
    }

    function applyFilters(forceSnap) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        
        if (!targetModel || targetModel.count === 0) {
            window.updateVisibleCount();
            return;
        }

        let firstValidIndex = -1;
        let lastValidIndex = -1;
        let cleanTarget = window.getCleanName(window.targetWallName);
        let targetIndex = -1;

        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                if (firstValidIndex === -1) {
                    firstValidIndex = i;
                }
                lastValidIndex = i;
                
                if (cleanTarget !== "" && window.getCleanName(fname) === cleanTarget) {
                    targetIndex = i;
                }
            }
        }

        let indexToFocus = -1;

        if (targetIndex !== -1) {
             indexToFocus = targetIndex;
        } else if (window.jumpToLastOnFilterChange && lastValidIndex !== -1) {
            indexToFocus = lastValidIndex;
        } else if (firstValidIndex !== -1) {
            indexToFocus = firstValidIndex;
        }

        window.jumpToLastOnFilterChange = false;
        
        if (indexToFocus !== -1) {
            window.executeFocusRestore(indexToFocus, forceSnap === true);
        }
        
        window.updateVisibleCount();
    }

    onCurrentFilterChanged: {
        window.isFilterAnimating = true;
        filterAnimationTimer.restart();
        window.isModelChanging = true;
        let fromWallhaven = window._lastFilter === "Wallhaven";
        window._lastFilter = window.currentFilter;
        
        Qt.callLater(() => {
            if (window.wallhavenMode) {
                if (wallhavenLoader.item) wallhavenLoader.item.focusQuery();
            } else {
                if (window.view) view.forceActiveFocus();
            }

            if (!window.wallhavenMode) window.applyFilters(fromWallhaven);
            window.isModelChanging = false;
        });
    }

    Shortcut { 
        sequence: "Left"; 
        enabled: !window.isApplying && !window.wallhavenMode
        onActivated: window.stepToNextValidIndex(-1) 
    }
    Shortcut {
        sequence: "Right";
        enabled: !window.isApplying && !window.wallhavenMode
        onActivated: window.stepToNextValidIndex(1)
    }
    Shortcut {
        sequence: "Up"
        enabled: !window.isApplying && !window.wallhavenMode
        onActivated: if (window.view && window.view.stepRow) window.view.stepRow(-1)
    }
    Shortcut {
        sequence: "Down"
        enabled: !window.isApplying && !window.wallhavenMode
        onActivated: if (window.view && window.view.stepRow) window.view.stepRow(1)
    }

    Shortcut {
        sequence: "Return"
        enabled: !window.isApplying && !window.wallhavenMode
        onActivated: {
            if (!window.view) return;
            let targetModel = window.getModelForFilter(window.currentFilter);
            if (view.currentIndex >= 0 && view.currentIndex < targetModel.count) {
                let fname = targetModel.get(view.currentIndex).fileName;
                if (fname) {
                    let isVid = String(fname).startsWith("000_");
                    window.applyWallpaper(String(fname), isVid);
                }
            }
        } 
    }
    Shortcut {
        sequence: "Space"
        enabled: !window.isApplying && !window.wallhavenTyping
        onActivated: if (window.candidate) window.previewing = !window.previewing
    }
    
    // Escape: swallowed while applying, leaves the Wallhaven tab first, else the host closes us.
    function handleEscape() {
        if (window.previewing) { window.previewing = false; return true; }
        if (window.isApplying) return true;
        if (window.wallhavenMode) {
            if (wallhavenLoader.item && wallhavenLoader.item.handleEscape()) return true;
            window.currentFilter = "All";
            return true;
        }
        return false;
    }
    Shortcut { sequence: "Tab"; enabled: !window.isApplying && !window.wallhavenMode; onActivated: window.cycleFilter(1) }
    Shortcut { sequence: "Backtab"; enabled: !window.isApplying && !window.wallhavenTyping; onActivated: window.cycleFilter(-1) }

    // Shift+digit reaches us as the shifted symbol on most layouts, so both forms are bound.
    Instantiator {
        model: [["Shift+1", "!", "Red"], ["Shift+2", "@", "Orange"], ["Shift+3", "#", "Yellow"], ["Shift+4", "$", "Green"], ["Shift+5", "%", "Blue"], ["Shift+6", "^", "Purple"], ["Shift+7", "&", "Pink"], ["Shift+8", "*", "Monochrome"], ["Shift+9", "(", "Wallhaven"], ["Shift+0", ")", "All"]]
        delegate: Shortcut {
            required property var modelData
            sequences: [modelData[0], modelData[1]]
            enabled: !window.isApplying && !window.wallhavenTyping
            onActivated: window.currentFilter = modelData[2]
            // Both forms match one press, which Qt dispatches as ambiguous rather than activated.
            onActivatedAmbiguously: window.currentFilter = modelData[2]
        }
    }
    Instantiator {
        model: [["Ctrl+1", "slices"], ["Ctrl+2", "wall"], ["Ctrl+3", "hand"]]
        delegate: Shortcut {
            required property var modelData
            sequence: modelData[0]
            enabled: !window.isApplying && !window.wallhavenTyping && !window.wallhavenMode
            onActivated: ShellSettings.setValue("wallpaper.pickerStyle", modelData[1])
        }
    }

    ListModel { id: localProxyModel }
    
    readonly property var activeModel: localProxyModel

    FolderListModel {
        id: localFolderModel
        folder: window.thumbDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        // Newest first. Thumbs carry their SOURCE mtime (touch -r), so this is date added.
        // FolderListModel's Time sort is ALREADY newest-first; sortReversed flips it to oldest.
        sortField: FolderListModel.Time
        
        onCountChanged: window.syncLocalModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncLocalModel() }
    }

    // Tracks the highest index we have already synced into localProxyModel
    // so we never re-scan items we already ingested.
    property int _localSyncedCount: 0

    function syncLocalModel() {
        let folderCount = localFolderModel.count;

        // If the folder shrank (files deleted), we need a full rebuild.
        // We do it silently without animation by blocking allowAddAnimation briefly.
        if (folderCount < window._localSyncedCount) {
            let wasAllowing = window.allowAddAnimation;
            window.allowAddAnimation = false;
            window.isModelChanging = true;

            localProxyModel.clear();
            window._localSyncedCount = 0;

            window.isModelChanging = false;
            // Re-run to fill from scratch, then restore anim state
            window.syncLocalModel();
            if (wasAllowing) allowAddAnimationTimer.restart();
            return;
        }

        // Incremental append — only new items
        if (folderCount > window._localSyncedCount) {
            let batch = [];
            for (let i = window._localSyncedCount; i < folderCount; i++) {
                let fn = localFolderModel.get(i, "fileName");
                let fu = localFolderModel.get(i, "fileUrl");
                if (fn !== undefined) {
                    batch.push({ "fileName": fn, "fileUrl": String(fu) });
                }
            }

            if (batch.length > 0) {
                localProxyModel.append(batch);
            }

            window._localSyncedCount = folderCount;
        }

        window.updateVisibleCount();

        // First-time focus snap
        if (!window.initialFocusSet && localProxyModel.count > 0) {
            window.tryFocus();
        }
    }

    // One of picker/*View.qml; each exposes currentIndex, snapTo(i) and, for grids, stepRow(d).
    Loader {
        id: viewLoader
        anchors.fill: parent
        visible: !window.wallhavenMode
        opacity: window.previewing ? 0.25 : 1
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        sourceComponent: window.pickerStyle === "wall" ? wallView : window.pickerStyle === "hand" ? handView : slicesView
        onLoaded: {
            item.forceActiveFocus();
            if (window.visible && window.initialFocusSet) window.applyFilters(true);
        }
    }
    // Outlives previewing so the Preview can play its close animation; closed releases it.
    Loader {
        id: previewLoader
        anchors.fill: parent
        z: 10
        active: window.previewing || window.previewClosing
        sourceComponent: Preview {
            picker: window
            open: window.previewing
            candidateKey: window.candidate ? window.candidate.key : ""
            candidateUrl: window.candidate ? window.candidate.url : ""
            candidateHiUrl: window.candidate ? (window.candidate.hiUrl || "") : ""
            candidateName: window.candidate ? window.candidate.name : ""
            candidateIsVideo: window.candidate ? window.candidate.isVideo === true : false
            candidateVideoUrl: window.candidate ? (window.candidate.videoUrl || "") : ""
            candidatePalette: window.candidate ? (window.candidate.palette || []) : []
            candidateStatus: window.candidate ? (window.candidate.status || "") : ""
            originFn: window.wallhavenMode ? window.wallhavenOrigin : window.localOrigin
            onClosed: window.previewClosing = false
            onDismissed: window.previewing = false
        }
    }
    Component { id: slicesView; SlicesView { picker: window } }
    Component { id: wallView; WallView { picker: window } }
    Component { id: handView; HandView { picker: window } }

    // The Wallhaven tab replaces the coverflow; WallhavenService keeps its state between opens.
    Loader {
        id: wallhavenLoader
        active: window.wallhavenMode
        anchors.top: filterBarBackground.bottom
        anchors.topMargin: window.s(18)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: window.s(72)
        anchors.rightMargin: window.s(72)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: window.s(24)
        z: 5
        opacity: status !== Loader.Ready ? 0 : (window.previewing ? 0.25 : 1)
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        sourceComponent: WallhavenBrowser {
            previewOpen: window.previewing
            onPreviewRequested: open => window.previewing = open
        }
    }

    Rectangle {
        id: filterBarBackground
        anchors.top: parent.top
        
        anchors.topMargin: window.isReady ? window.s(40) : window.s(-100)
        opacity: window.isReady ? 1.0 : 0.0
        Behavior on anchors.topMargin { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        anchors.horizontalCenter: parent.horizontalCenter
        z: 20
        height: window.s(56)
        width: filterRow.width + window.s(24)
        radius: Radius.outer(window.s(14))
        
        color: Qt.rgba(_theme.mantle.r, _theme.mantle.g, _theme.mantle.b, 0.90)
        border.color: _theme.surface2
        border.width: 1

        Row {
            id: filterRow
            anchors.centerIn: parent
            spacing: window.s(12)

            Rectangle {
                id: notifDrawer
                height: window.s(44)
                property real paddingLeft: window.showSpinner ? window.s(40) : window.s(16)
                property real targetWidth: window.showNotification ? Math.min(notifTextDrawer.implicitWidth + paddingLeft + window.s(20), window.s(300)) : 0
                width: targetWidth
                visible: width > 0.1
                radius: Radius.outer(window.s(10))
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                
                color: window.showNotification ? _theme.surface2 : "transparent"
                border.color: window.showNotification ? _theme.surface1 : "transparent"
                border.width: 1

                Behavior on width { 
                    NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 } 
                }
                Behavior on color { ColorAnimation { duration: 400 } }
                Behavior on border.color { ColorAnimation { duration: 400 } }

                Item {
                    visible: window.showSpinner
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Canvas {
                        id: notifSpinner
                        width: window.s(14)
                        height: window.s(14)
                        anchors.centerIn: parent
                        property real scaleTrigger: window.s(1)
                        onScaleTriggerChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            var s = window.s;
                            ctx.reset();
                            ctx.lineWidth = s(2);
                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.3);
                            ctx.beginPath();
                            ctx.arc(s(7), s(7), s(5), 0, Math.PI * 2);
                            ctx.stroke();
                            
                            ctx.strokeStyle = Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.9);
                            ctx.beginPath();
                            ctx.arc(s(7), s(7), s(5), 0, Math.PI * 0.5);
                            ctx.stroke();
                        }
                        RotationAnimation on rotation {
                            loops: Animation.Infinite
                            from: 0; to: 360
                            duration: 800
                            running: window.showSpinner && window.showNotification
                        }
                    }
                }

                Text {
                    id: notifTextDrawer
                    anchors.left: parent.left
                    anchors.leftMargin: window.showSpinner ? window.s(40) : window.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, window.s(300) - anchors.leftMargin - window.s(16))
                    text: window.currentNotification
                    
                    color: _theme.text
                    font.family: Fonts.ui
                    font.pixelSize: window.s(14)
                    font.bold: true
                    elide: Text.ElideRight

                    opacity: window.showNotification ? 0.9 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
                    Behavior on anchors.leftMargin { 
                        NumberAnimation { duration: 600; easing.type: Easing.OutBack; easing.overshoot: 0.5 } 
                    }
                }
            }

            Rectangle {
                id: monitorDrawer
                visible: monitorModel.count > 1
                height: window.s(44)
                
                property real expandedWidth: window.s(44) + monitorListRow.width + window.s(8)
                width: visible ? (window.isMonitorSelectorOpen ? expandedWidth : window.s(44)) : 0
                
                radius: Radius.outer(window.s(10))
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                
                color: window.isMonitorSelectorOpen ? _theme.surface2 : "transparent"
                border.color: window.isMonitorSelectorOpen ? _theme.text : _theme.surface1
                border.width: window.isMonitorSelectorOpen ? window.s(2) : 1
                
                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
                Behavior on color { ColorAnimation { duration: 400 } }
                Behavior on border.color { ColorAnimation { duration: 400 } }

                MouseArea {
                    id: monitorIconMouse
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.isMonitorSelectorOpen = !window.isMonitorSelectorOpen
                }

                Canvas {
                    id: monitorIcon
                    width: window.s(18)
                    height: window.s(18)
                    anchors.centerIn: monitorIconMouse
                    property string activeColor: window.isMonitorSelectorOpen ? _theme.text : (monitorIconMouse.containsMouse ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7))
                    onActiveColorChanged: requestPaint()
                    property real scaleTrigger: window.s(1)
                    onScaleTriggerChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        var s = window.s;
                        ctx.reset();
                        ctx.lineWidth = s(2);
                        ctx.strokeStyle = activeColor;
                        ctx.lineJoin = "round";
                        ctx.lineCap = "round";
                        
                        ctx.beginPath();
                        ctx.rect(s(2), s(3), s(14), s(9));
                        ctx.stroke();
                        
                        ctx.beginPath();
                        ctx.moveTo(s(9), s(12));
                        ctx.lineTo(s(9), s(16));
                        ctx.moveTo(s(5), s(16));
                        ctx.lineTo(s(13), s(16));
                        ctx.stroke();
                    }
                }

                Row {
                    id: monitorListRow
                    anchors.left: monitorIconMouse.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: window.s(8)
                    
                    opacity: window.isMonitorSelectorOpen ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 300 } }

                    Repeater {
                        model: monitorModel
                        delegate: Item {
                            width: monitorText.contentWidth + window.s(16)
                            height: window.s(32)
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Rectangle {
                                anchors.fill: parent
                                radius: Radius.outer(window.s(6))
                                color: model.selected ? _theme.text : _theme.surface1
                                border.color: model.selected ? _theme.text : _theme.surface2
                                border.width: 1
                                
                                Behavior on color { ColorAnimation { duration: 250 } }
                                Behavior on border.color { ColorAnimation { duration: 250 } }
                                
                                Text {
                                    id: monitorText
                                    text: model.name
                                    anchors.centerIn: parent
                                    color: model.selected ? _theme.base : _theme.text
                                    font.family: Fonts.ui
                                    font.pixelSize: window.s(12)
                                    font.bold: model.selected
                                    Behavior on color { ColorAnimation { duration: 250 } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: window.isMonitorSelectorOpen && !window.isApplying
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (model.selected) {
                                        let activeCount = 0;
                                        for (let i = 0; i < monitorModel.count; i++) {
                                            if (monitorModel.get(i).selected) activeCount++;
                                        }
                                        if (activeCount > 1) {
                                            monitorModel.setProperty(index, "selected", false);
                                        }
                                    } else {
                                        monitorModel.setProperty(index, "selected", true);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: window.filterData

                delegate: Item {
                    width: !visible ? 0 : ((modelData.name === "Video" || modelData.name === "All") ? window.s(44) : (modelData.hex === "" ? filterText.contentWidth + window.s(24) : window.s(36)))
                    height: !visible ? 0 : window.s(36)
                    anchors.verticalCenter: parent.verticalCenter
                    
                    Rectangle {
                        anchors.fill: parent
                        radius: Radius.outer(window.s(10))
                        color: modelData.hex === "" 
                                ? (window.currentFilter === modelData.name ? _theme.surface2 : "transparent") 
                                : modelData.hex
                        
                        border.color: window.currentFilter === modelData.name ? _theme.text : _theme.surface1
                        border.width: window.currentFilter === modelData.name ? window.s(2) : 1
                        scale: window.currentFilter === modelData.name ? 1.15 : (filterMouse.containsMouse ? 1.08 : 1.0)
                        
                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        Text {
                            id: filterText
                            visible: modelData.hex === "" && modelData.name !== "Video" && modelData.name !== "All"
                            text: modelData.label
                            anchors.centerIn: parent
                            color: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            font.family: Fonts.ui
                            font.pixelSize: window.s(14)
                            font.bold: window.currentFilter === modelData.name
                            Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutQuart } }
                        }

                        Canvas {
                            visible: modelData.name === "Video"
                            width: window.s(14); height: window.s(16)
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: window.s(2)
                            property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                var s = window.s;
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.beginPath();
                                ctx.moveTo(0, 0);
                                ctx.lineTo(s(14), s(8));
                                ctx.lineTo(0, s(16));
                                ctx.closePath();
                                ctx.fill();
                            }
                        }

                        Canvas {
                            visible: modelData.name === "All"
                            width: window.s(14); height: window.s(14)
                            anchors.centerIn: parent
                            property string activeColor: window.currentFilter === modelData.name ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                var s = window.s;
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.fillRect(0, 0, s(6), s(6));
                                ctx.fillRect(s(8), 0, s(6), s(6));
                                ctx.fillRect(0, s(8), s(6), s(6));
                                ctx.fillRect(s(8), s(8), s(6), s(6));
                            }
                        }
                    }

                    MouseArea {
                        id: filterMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: window.currentFilter = modelData.name
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Rectangle {
                width: 1
                height: window.s(24)
                color: _theme.surface2
                anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
                model: [{ name: "slices" }, { name: "wall" }, { name: "hand" }]

                delegate: Item {
                    id: styleChip
                    readonly property bool active: window.pickerStyle === modelData.name
                    width: window.s(36)
                    height: window.s(36)
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: Radius.outer(window.s(10))
                        color: styleChip.active ? _theme.surface2 : "transparent"
                        border.color: styleChip.active ? _theme.text : _theme.surface1
                        border.width: styleChip.active ? window.s(2) : 1
                        scale: styleChip.active ? 1.15 : (styleMouse.containsMouse ? 1.08 : 1.0)

                        Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                        Behavior on border.color { ColorAnimation { duration: 300 } }

                        Canvas {
                            width: modelData.name === "hand" ? window.s(22) : modelData.name === "slices" ? window.s(20) : window.s(16); height: window.s(16)
                            anchors.centerIn: parent
                            property string activeColor: styleChip.active ? _theme.text : Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                            onActiveColorChanged: requestPaint()
                            property real scaleTrigger: window.s(1)
                            onScaleTriggerChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                var s = window.s;
                                ctx.reset();
                                ctx.fillStyle = activeColor;
                                ctx.strokeStyle = activeColor;
                                ctx.lineWidth = s(1.5);
                                ctx.lineJoin = "round";
                                if (modelData.name === "slices") {
                                    var skew = window.skewFactor * s(16);
                                    for (var i = 0; i < 3; i++) {
                                        var x = s(6.3) + i * s(5);
                                        ctx.beginPath();
                                        ctx.moveTo(x, 0);
                                        ctx.lineTo(x + s(3), 0);
                                        ctx.lineTo(x + s(3) + skew, s(16));
                                        ctx.lineTo(x + skew, s(16));
                                        ctx.closePath();
                                        ctx.fill();
                                    }
                                } else if (modelData.name === "wall") {
                                    for (var r = 0; r < 2; r++) {
                                        for (var c = 0; c < 3; c++) {
                                            ctx.beginPath();
                                            ctx.roundedRect(c * s(5.5), s(2) + r * s(6.5), s(4.5), s(5.5), s(1), s(1));
                                            ctx.fill();
                                        }
                                    }
                                } else {
                                    var cw = s(6), ch = s(11);
                                    var angles = [-15, 15, 0];
                                    var offsets = [-s(4.5), s(4.5), 0];
                                    for (var k = 0; k < 3; k++) {
                                        ctx.save();
                                        ctx.translate(s(11) + offsets[k], s(13));
                                        ctx.rotate(angles[k] * Math.PI / 180);
                                        ctx.beginPath();
                                        ctx.roundedRect(-cw / 2, -ch, cw, ch, s(1), s(1));
                                        if (k === 2) ctx.fill(); else ctx.stroke();
                                        ctx.restore();
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: styleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: ShellSettings.setValue("wallpaper.pickerStyle", modelData.name)
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Item {
                id: handMoveChip
                readonly property var moves: ["random", "cycle", "cascade", "corkscrew", "shuffle", "spiral"]
                visible: window.pickerStyle === "hand"
                width: handMoveText.contentWidth + window.s(24)
                height: window.s(36)
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: Radius.outer(window.s(10))
                    color: "transparent"
                    border.color: _theme.surface1
                    border.width: 1
                    scale: handMoveMouse.containsMouse ? 1.08 : 1.0

                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                    Text {
                        id: handMoveText
                        text: ShellSettings.handMove
                        anchors.centerIn: parent
                        color: Qt.rgba(_theme.text.r, _theme.text.g, _theme.text.b, 0.7)
                        font.family: Fonts.ui
                        font.pixelSize: window.s(14)
                    }
                }

                MouseArea {
                    id: handMoveMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const i = handMoveChip.moves.indexOf(ShellSettings.handMove);
                        ShellSettings.setValue("wallpaper.handMove", handMoveChip.moves[(i + 1) % handMoveChip.moves.length]);
                    }
                }
            }

        }
    }

    Component.onCompleted: {
        window.loadMonitors();

        if (window.view) view.forceActiveFocus();
        window.processMarkers();
        window.triggerColorExtraction();
    }
}
