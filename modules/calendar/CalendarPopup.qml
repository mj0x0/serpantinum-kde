import "../../services/audio"
import "../../services/layout"
import "../../services/settings"
import "../../services/theme"
import "../../services/reusables"
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import QtCore
import Quickshell
import Quickshell.Io
import QtQuick.Window

// KDE port of serpantinum's calendar/weather control-center; hosted by Calendar.qml.
Item {
    id: window

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        // Pass both width and height so the internal popup scale perfectly synchronizes
        // with the master window's WindowRegistry.js calculations
        currentWidth: Screen.width
        currentHeight: Screen.height
    }
    
    // Expose reactive scale factor for all bindings
    readonly property real sf: scaler.baseScale

    // Keep helper function for backwards compatibility in pure JS blocks
    function s(val) { 
        return Math.round(val * window.sf); 
    }

    // --- Master window scaling --- the host binds width/height to these and centres it.
    readonly property real targetMasterHeight: window.scheduleModuleExists ? Math.round(750 * window.sf) : Math.round(510 * window.sf)
    readonly property real targetMasterWidth: Math.round(1450 * window.sf)

    // --- KEYBOARD SHORTCUTS (Escape is handled by Main.qml now) ---
    Shortcut { 
        sequence: "Left"
        onActivated: {
            if (calHover.hovered) {
                window.setMonthOffset(window.targetMonthOffset - 1);
            } else {
                window.setWeatherView(window.targetWeatherView - 1);
            }
        }
    }

    Shortcut { 
        sequence: "Right"
        onActivated: {
            if (calHover.hovered) {
                window.setMonthOffset(window.targetMonthOffset + 1);
            } else {
                window.setWeatherView(window.targetWeatherView + 1);
            }
        }
    }

    // --- COLORS (Dynamic Matugen Palette) ---
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext1: _theme.subtext1
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay2: _theme.overlay2
    readonly property color overlay1: _theme.overlay1
    readonly property color overlay0: _theme.overlay0
    readonly property color surface2: _theme.surface2
    readonly property color surface1: _theme.surface1
    readonly property color surface0: _theme.surface0
    
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color teal: _theme.teal
    readonly property color green: _theme.green
    readonly property color red: _theme.red
    readonly property color secondary: _theme.secondary

    // KDE port: weather.sh lives in the project helpers dir. The schedule + diary
    // scripts don't exist here, so schedulePathChecker leaves the module dormant.
    readonly property string scriptsDir: ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers"

    // --- Week start --- defaults to the system locale, overridable in settings.json:
    // { calendar: { weekStart: locale | sunday | monday | 0-6 } }
    readonly property int weekStartDay: {
        var v = ShellSettings.value("calendar.weekStart", "locale");
        if (typeof v === "number") return ((v % 7) + 7) % 7;
        var t = ("" + v).toLowerCase();
        if (t === "sunday") return 0;
        if (t === "monday") return 1;
        return Qt.locale().firstDayOfWeek;
    }

    readonly property var weekDayNames: {
        var base = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], out = [];
        for (var i = 0; i < 7; i++) out.push(base[(window.weekStartDay + i) % 7]);
        return out;
    }

    readonly property color timeColor: {
        let h = window.currentTime.getHours();
        if (h >= 5 && h < 12) return window.peach;      // Morning
        if (h >= 12 && h < 17) return window.sapphire;  // Afternoon
        if (h >= 17 && h < 21) return window.mauve;     // Evening
        return window.blue;                             // Night
    }

    readonly property color timeAccent: {
        let h = window.currentTime.getHours();
        if (h >= 5 && h < 12) return window.yellow;     // Morning Accent
        if (h >= 12 && h < 17) return window.teal;      // Afternoon Accent
        if (h >= 17 && h < 21) return window.pink;      // Evening Accent
        return window.mauve;                            // Night Accent
    }

    readonly property color textAccent: Qt.tint(window.timeAccent, Qt.alpha(window.text, 0.35))

    // --- STARTUP ANIMATION STATES ---
    property bool startupComplete: false
    property real introMain: 0
    property real introAmbient: 0
    property real introClock: 0
    property real introCalendar: 0
    property real introWeather: 0
    property real introSchedule: 0

    SequentialAnimation {
        running: true
        
        // 50ms buffer to allow the window manager to map the surface before animating
        PauseAnimation { duration: 20 }

        ParallelAnimation {
            // Base window fades and scales slightly
            NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }

            // Ambient background glows and big parallax icon fade in
            SequentialAnimation {
                PauseAnimation { duration: 150 }
                NumberAnimation { target: window; property: "introAmbient"; from: 0; to: 1.0; duration: 1000; easing.type: Easing.OutSine }
            }

            // Central clock and 3D orbital pop from the center
            SequentialAnimation {
                PauseAnimation { duration: 250 }
                NumberAnimation { target: window; property: "introClock"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
            }

            // Left wing (Calendar) slides in from the left
            SequentialAnimation {
                PauseAnimation { duration: 350 }
                NumberAnimation { target: window; property: "introCalendar"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuint }
            }

            // Right wing (Weather) slides in from the right
            SequentialAnimation {
                PauseAnimation { duration: 400 }
                NumberAnimation { target: window; property: "introWeather"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuint }
            }

            // Bottom section (Schedule) flows up smoothly
            SequentialAnimation {
                PauseAnimation { duration: 500 }
                NumberAnimation { target: window; property: "introSchedule"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutExpo }
            }
        }
        ScriptAction { script: window.startupComplete = true }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: window; property: "introMain"; to: 0; duration: 400; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introAmbient"; to: 0; duration: 250; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introClock"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introCalendar"; to: 0; duration: 350; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introWeather"; to: 0; duration: 350; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introSchedule"; to: 0; duration: 200; easing.type: Easing.InQuart }
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }

    // --- STATE & TIME (WITH SECOND PULSE) ---
    property var currentTime: new Date()
    property real currentEpoch: currentTime.getTime() / 1000
    
    property real secondPulse: 1.0
    NumberAnimation on secondPulse { 
        id: pulseReset 
        to: 1.0; duration: 600; easing.type: Easing.OutQuint; running: false 
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            window.currentTime = new Date();
            window.secondPulse = 1.06; // Gentle pulse
            pulseReset.start();        
            
            if (window.currentTime.getHours() === 0 && window.currentTime.getMinutes() === 0 && window.currentTime.getSeconds() === 0) {
                updateCalendarGrid();
            }
        }
    }

    // --- WEATHER DATA & ELEGANT TRANSITIONS (3D ORBIT SPIN) ---
    property var weatherData: null
    property int weatherView: 0
    property color activeWeatherHex: {
        if (!window.weatherData) return window.mauve;
        if (window.weatherView === 0 && window.weatherData.current_hex) return window.weatherData.current_hex;
        if (window.weatherData.forecast && window.weatherData.forecast[window.weatherView]) return window.weatherData.forecast[window.weatherView].hex;
        return window.mauve;
    }

    // Transition Properties
    property int targetWeatherView: 0
    property real weatherContentOpacity: 1.0
    property real weatherContentOffset: 0.0
    property int weatherAnimDirection: 1
    
    // New 3D Spin Properties
    property real transitionSpin: 0.0
    property real transitionScale: 1.0

    // --- TEMPERATURE LOGIC ---
    property real targetTemp: {
        if (!window.weatherData) return 0;
        if (window.targetWeatherView === 0 && window.weatherData.current_temp !== undefined) {
            return Number(window.weatherData.current_temp);
        }
        if (window.weatherData.forecast && window.weatherData.forecast[window.targetWeatherView]) {
            return Number(window.weatherData.forecast[window.targetWeatherView].max);
        }
        return 0;
    }
    
    property real displayedTemp: targetTemp

    Behavior on displayedTemp {
        NumberAnimation {
            id: tempAnim
            duration: 800
            easing.type: Easing.OutQuart
        }
    }

    property bool isTempAnimating: tempAnim.running
    property color tempGlowColor: {
        // Resting temperature uses the md3 Secondary colour; the red/blue only
        // flash transiently while the number counts up/down between views.
        if (!isTempAnimating || !window.startupComplete) return window.secondary;

        // If the target is higher than the currently ticking number, we are counting up
        if (window.targetTemp > window.displayedTemp) return window.red;

        // If the target is lower than the currently ticking number, we are counting down
        if (window.targetTemp < window.displayedTemp) return window.blue;

        return window.secondary;
    }

    SequentialAnimation {
        id: weatherTransitionAnim
        ParallelAnimation {
            NumberAnimation { target: window; property: "weatherContentOpacity"; to: 0.0; duration: 250; easing.type: Easing.InSine }
            NumberAnimation { target: window; property: "weatherContentOffset"; to: Math.round(-40 * window.sf) * weatherAnimDirection; duration: 250; easing.type: Easing.InSine }
            
            // Spin the 3D orbit out and scale it down for depth
            NumberAnimation { target: window; property: "transitionSpin"; to: 180 * weatherAnimDirection; duration: 300; easing.type: Easing.InBack }
            NumberAnimation { target: window; property: "transitionScale"; to: 0.8; duration: 300; easing.type: Easing.InCubic }
        }
        ScriptAction { 
            script: { 
                window.weatherView = window.targetWeatherView; 
                window.weatherContentOffset = Math.round(40 * window.sf) * weatherAnimDirection; // Move to opposite side while hidden
                
                // Reset the spin to the opposite side so it continues spinning into place seamlessly
                window.transitionSpin = -180 * weatherAnimDirection;
            } 
        }
        ParallelAnimation {
            NumberAnimation { target: window; property: "weatherContentOpacity"; to: 1.0; duration: 450; easing.type: Easing.OutQuart }
            NumberAnimation { target: window; property: "weatherContentOffset"; to: 0.0; duration: 450; easing.type: Easing.OutQuart }
            
            // Snap the 3D orbit back to 0 degrees and restore full scale
            NumberAnimation { target: window; property: "transitionSpin"; to: 0.0; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            NumberAnimation { target: window; property: "transitionScale"; to: 1.0; duration: 500; easing.type: Easing.OutBack }
        }
    }

    function setWeatherView(idx) {
        if (idx < 0 || idx > 4 || !window.weatherData) return;
        if (idx === window.targetWeatherView) return; // Ignore if we are already heading there

        // If an animation is already running, gracefully interrupt it and apply the logical switch
        // before starting the new animation so the data doesn't get desynced.
        if (weatherTransitionAnim.running) {
            weatherTransitionAnim.stop();
            window.weatherView = window.targetWeatherView;
        }

        window.weatherAnimDirection = idx > window.weatherView ? 1 : -1;
        window.targetWeatherView = idx;
        weatherTransitionAnim.start();

        // Keep the calendar on the month of the day the weather shows.
        let now = window.currentTime;
        let sel = window.selectedDate;
        window.setMonthOffset((sel.getFullYear() - now.getFullYear()) * 12 + sel.getMonth() - now.getMonth());
    }

    // The day the weather panel shows: forecast[i] is today + i days.
    readonly property date selectedDate: {
        let d = new Date(window.currentTime.getTime());
        d.setHours(12, 0, 0, 0);
        d.setDate(d.getDate() + window.targetWeatherView);
        return d;
    }

    // A clicked forecast day switches the weather, as the arrow keys do; other days only have tooltips.
    function selectDay(dayOfMonth) {
        let today = new Date(window.currentTime.getTime());
        today.setHours(12, 0, 0, 0);
        let offset = Math.round((new Date(window.gridYear, window.gridMonth, dayOfMonth, 12) - today) / 86400000);
        if (offset >= 0 && offset <= 4) window.setWeatherView(offset);
    }

    property int activeHourIndex: {
        if (window.weatherView !== 0 || !window.weatherData || !window.weatherData.forecast || !window.weatherData.forecast[0] || !window.weatherData.forecast[0].hourly) return -1;
        
        let ch = window.currentTime.getHours();
        let hrArr = window.weatherData.forecast[0].hourly.slice(0, 8);
        let bestIdx = -1;
        let minDiff = 999;
        
        for (let i = 0; i < hrArr.length; i++) {
            let timeStr = hrArr[i].time || "00:00";
            let h = parseInt(timeStr.split(":")[0]);
            let diff = Math.abs(h - ch);
            if (diff < minDiff) {
                minDiff = diff;
                bestIdx = i;
            }
        }
        return bestIdx !== -1 ? bestIdx : 0;
    }

    Process {
        id: weatherPoller
        command: ["bash", window.scriptsDir + "/weather.sh", "--json"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try { window.weatherData = JSON.parse(txt); } catch(e) {}
                }
            }
        }
    }

    Timer {
        interval: 150000 
        running: true; repeat: true
        onTriggered: weatherPoller.running = true
    }

    // --- SCHEDULE DATA & CONDITIONAL RENDERING ---
    property bool scheduleModuleExists: false
    property var scheduleData: { "header": "Loading Schedule...", "link": "", "lessons": [] }

    // Dynamic offset based on whether the schedule module exists
    property real centerOffset: window.scheduleModuleExists ? Math.round(-100 * window.sf) : 0
    Behavior on centerOffset { NumberAnimation { duration: 600; easing.type: Easing.OutQuart } }

    // Check if the schedule manager script actually exists before doing anything
    Process {
        id: schedulePathChecker
        command: ["bash", "-c", "[ -f '" + window.scriptsDir + "/schedule/schedule_manager.sh' ] && echo 1 || echo 0"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim() === "1") {
                    window.scheduleModuleExists = true;
                    schedulePoller.running = true; // Safe to start polling
                } else {
                    window.scheduleModuleExists = false;
                    // Shrinking is now automatically handled by the onTargetMasterHeightChanged watcher
                }
            }
        }
    }

    Process {
        id: schedulePoller
        command: ["bash", window.scriptsDir + "/schedule/schedule_manager.sh"]
        running: false // Handled by schedulePathChecker
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try { window.scheduleData = JSON.parse(txt); } catch(e) { console.warn("calendar: unreadable schedule data"); }
                }
            }
        }
    }

    Timer {
        interval: 600000 
        // Only run the timer if the module actually exists
        running: window.scheduleModuleExists; repeat: true
        onTriggered: schedulePoller.running = true
    }

    // --- Holidays and astro events --- KHolidays data is COMPILED INTO the library and
    // the QML module cannot query it, so helpers/kholidays/khdump links it and dumps JSON.
    readonly property string khdumpPath: window.scriptsDir + "/kholidays/khdump"
    // Region drives which holidays appear. Persisted so the pick survives a reload.
    property string holidayRegion: "il_en-us"
    readonly property string regionFile: Quickshell.env("HOME") + "/.config/quickshell/calendar-region"
    property var regionList: []          // [{code, name}] — all 170 KHolidays regions
    property string regionFilter: ""     // search text in the picker

    // Case-insensitive match on name or code; empty query returns everything.
    readonly property var regionListFiltered: {
        var q = window.regionFilter.toLowerCase().trim();
        if (q === "")
            return window.regionList;
        var out = [];
        for (var i = 0; i < window.regionList.length; i++) {
            var r = window.regionList[i];
            if (r.name.toLowerCase().indexOf(q) !== -1 || r.code.toLowerCase().indexOf(q) !== -1)
                out.push(r);
        }
        return out;
    }

    Process {
        id: regionLoader
        running: true
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || echo ''", "_", window.regionFile]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = (this.text || "").trim();
                if (v !== "")
                    window.holidayRegion = v;
                // Region may have changed → refresh both views.
                window.updateCalendarGrid();
            }
        }
    }

    Process {
        id: regionListFetcher
        stdout: StdioCollector {
            onStreamFinished: {
                try { window.regionList = JSON.parse((this.text || "").trim() || "[]"); }
                catch (e) { window.regionList = []; }
            }
        }
    }

    function loadRegionList() {
        if (window.regionList.length > 0)
            return;                       // 170 entries never change at runtime
        regionListFetcher.command = ["sh", "-c",
            "[ -x \"$1\" ] && \"$1\" --regions || echo '[]'", "_", window.khdumpPath];
        regionListFetcher.running = false;
        regionListFetcher.running = true;
    }

    function setRegion(code) {
        window.holidayRegion = code;
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "_", window.regionFile, code]);
        window.updateCalendarGrid();      // refetch this month
    }
    property var holidaysByDay: ({})   // day-of-month (int) -> [names]
    property var holidayList: []       // [{date, day, name, categories}] for the shown month
    property bool eventsOpen: false
    property bool khdumpAvailable: true   // assume yes until the probe says otherwise
    // One-shot probe: separates no events this month from helper not built.
    Process {
        id: khdumpProbe
        running: true
        command: ["sh", "-c", "[ -x \"$1\" ] && echo yes || echo no", "_", window.khdumpPath]
        stdout: StdioCollector {
            onStreamFinished: {
                window.khdumpAvailable = ((this.text || "").trim() === "yes");
            }
        }
    }

    Process {
        id: holidayFetcher
        stdout: StdioCollector {
            onStreamFinished: {
                var byDay = ({});
                var list = [];
                try {
                    var arr = JSON.parse((this.text || "").trim() || "[]");
                    for (var i = 0; i < arr.length; i++) {
                        var parts = ("" + arr[i].date).split("-");
                        var d = parseInt(parts[2], 10);
                        if (!byDay[d]) byDay[d] = [];
                        byDay[d].push(arr[i].name);
                        list.push({
                            date: arr[i].date,
                            day: d,
                            name: arr[i].name,
                            categories: (arr[i].categories || []).join(",")
                        });
                    }
                } catch (e) { /* leave empty — calendar still works */ }
                window.holidaysByDay = byDay;
                window.holidayList = list;
            }
        }
    }

    // Fetch the displayed month. Called whenever the grid is rebuilt.
    function fetchHolidays(year, month0) {
        var ym = year + "-" + (month0 + 1 < 10 ? "0" : "") + (month0 + 1);
        var astro = ShellSettings.value("calendar.astro", false) === true;
        holidayFetcher.command = ["sh", "-c",
            "[ -x \"$1\" ] && \"$1\" --month \"$2\" \"$3\" $4 || echo '[]'",
            "_", window.khdumpPath, window.holidayRegion, ym,
            astro ? "--moon" : "--no-astro"];
        holidayFetcher.running = false;
        holidayFetcher.running = true;
    }

    property int monthOffset: 0
    property int targetMonthOffset: 0
    property string targetMonthName: ""
    property int gridYear: 0
    property int gridMonth: 0
    property int gridFirstDay: 0   // grid index of the month's 1st
    readonly property bool selectedInGrid: gridYear === selectedDate.getFullYear() && gridMonth === selectedDate.getMonth()
    ListModel { id: calendarModel }

    property real calendarContentOpacity: 1.0
    property real calendarContentOffset: 0.0
    property int calendarAnimDirection: 1

    SequentialAnimation {
        id: calendarTransitionAnim
        ParallelAnimation {
            NumberAnimation { target: window; property: "calendarContentOpacity"; to: 0.0; duration: 200; easing.type: Easing.InSine }
            NumberAnimation { target: window; property: "calendarContentOffset"; to: Math.round(-20 * window.sf) * calendarAnimDirection; duration: 200; easing.type: Easing.InSine }
        }
        ScriptAction {
            script: {
                window.monthOffset = window.targetMonthOffset;
                window.calendarContentOffset = Math.round(20 * window.sf) * calendarAnimDirection;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: window; property: "calendarContentOpacity"; to: 1.0; duration: 350; easing.type: Easing.OutQuart }
            NumberAnimation { target: window; property: "calendarContentOffset"; to: 0.0; duration: 350; easing.type: Easing.OutQuart }
        }
    }

    function setMonthOffset(newOffset) {
        if (newOffset === window.targetMonthOffset) return;

        if (calendarTransitionAnim.running) {
            calendarTransitionAnim.stop();
            window.monthOffset = window.targetMonthOffset;
        }

        window.calendarAnimDirection = newOffset > window.targetMonthOffset ? 1 : -1;
        window.targetMonthOffset = newOffset;
        calendarTransitionAnim.start();
    }

    function updateCalendarGrid() {
        let d = new Date(window.currentTime.getTime());
        d.setDate(1); 
        d.setMonth(d.getMonth() + window.monthOffset);

        let targetMonth = d.getMonth();
        let targetYear = d.getFullYear();
        window.gridYear = targetYear;
        window.gridMonth = targetMonth;
        
        let actualToday = new Date();
        let isRealCurrentMonth = (actualToday.getMonth() === targetMonth && actualToday.getFullYear() === targetYear);
        let todayDate = actualToday.getDate();

        window.targetMonthName = Qt.formatDateTime(d, "MMMM yyyy");

        // Offset from the configured first day of the week, not hardcoded Monday.
        let firstDay = (new Date(targetYear, targetMonth, 1).getDay()
                        - window.weekStartDay + 7) % 7;
        window.gridFirstDay = firstDay;

        let daysInMonth = new Date(targetYear, targetMonth + 1, 0).getDate();
        let daysInPrevMonth = new Date(targetYear, targetMonth, 0).getDate();

        calendarModel.clear();

        for (let i = firstDay - 1; i >= 0; i--) {
            calendarModel.append({ dayNum: (daysInPrevMonth - i).toString(), isCurrentMonth: false, isToday: false });
        }
        for (let i = 1; i <= daysInMonth; i++) {
            calendarModel.append({ dayNum: i.toString(), isCurrentMonth: true, isToday: (isRealCurrentMonth && i === todayDate) });
        }
        let remaining = 42 - calendarModel.count;
        for (let i = 1; i <= remaining; i++) {
            calendarModel.append({ dayNum: i.toString(), isCurrentMonth: false, isToday: false });
        }

        window.fetchHolidays(targetYear, targetMonth);
    }

    onMonthOffsetChanged: updateCalendarGrid()

    Component.onCompleted: {
        updateCalendarGrid();
    }

    // --- UI LAYOUT ---
    Item {
        anchors.fill: parent
        scale: 0.95 + (0.05 * introMain)
        opacity: introMain

        // MultiEffect mask, not clip: true - a square clip let the blobs bleed into the
        // corner triangles. The mask needs layer.enabled to survive scaling.
        Rectangle {
            id: cardMask
            anchors.fill: parent
            radius: Radius.outer(Math.round(20 * window.sf))
            color: "white"
            visible: false
            layer.enabled: true
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Radius.outer(Math.round(20 * window.sf))
            color: window.base
            border.color: window.surface0
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
            }

            // --- AMBIENT WIDGET COLOR BLOBS (Spread Out) ---
            Rectangle {
                width: parent.width * 0.5; height: width; radius: width / 2
                x: (parent.width * 0.75 - width / 2) + Math.cos(window.globalOrbitAngle * 1.5) * Math.round(350 * window.sf)
                y: (parent.height * 0.3 - height / 2) + Math.sin(window.globalOrbitAngle * 1.5) * Math.round(200 * window.sf)
                opacity: 0.025 * window.introAmbient
                color: window.activeWeatherHex
                Behavior on color { ColorAnimation { duration: 1000 } }
            }

            Rectangle {
                width: parent.width * 0.6; height: width; radius: width / 2
                x: (parent.width * 0.25 - width / 2) + Math.sin(window.globalOrbitAngle * 1.2) * Math.round(-300 * window.sf)
                y: (parent.height * 0.7 - height / 2) + Math.cos(window.globalOrbitAngle * 1.2) * Math.round(-250 * window.sf)
                opacity: 0.02 * window.introAmbient
                color: window.timeColor
                Behavior on color { ColorAnimation { duration: 1000 } }
            }

            Rectangle {
                width: parent.width * 0.45; height: width; radius: width / 2
                x: (parent.width * 0.5 - width / 2) + Math.cos(window.globalOrbitAngle * -1.8) * Math.round(400 * window.sf)
                y: (parent.height * 0.5 - height / 2) + Math.sin(window.globalOrbitAngle * -1.8) * Math.round(-350 * window.sf)
                opacity: 0.015 * window.introAmbient
                color: window.timeAccent
                Behavior on color { ColorAnimation { duration: 1000 } }
            }

            // Big Parallax Weather Icon (Tied to Weather Transition)
            Text {
                id: bgWeatherIcon
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.centerOffset
                text: {
                    if (!window.weatherData) return "";
                    if (window.weatherView === 0 && window.weatherData.current_icon) return window.weatherData.current_icon;
                    if (window.weatherData.forecast && window.weatherData.forecast[window.weatherView]) return window.weatherData.forecast[window.weatherView].icon;
                    return "";
                }
                font.family: "Iosevka Nerd Font"
                font.pixelSize: Math.round(800 * window.sf)
                color: window.activeWeatherHex  // Dynamic color based on weather condition
                opacity: (0.03 + (0.01 * Math.sin(window.globalOrbitAngle * 4))) * window.introAmbient * window.weatherContentOpacity
                z: 0
                Behavior on color { ColorAnimation { duration: 1500 } }
                
                property real drift: 0
                SequentialAnimation on drift {
                    loops: Animation.Infinite
                    NumberAnimation { to: Math.round(-20 * window.sf); duration: 6000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 6000; easing.type: Easing.InOutSine }
                }
                
                transform: [
                    Translate { y: bgWeatherIcon.drift },
                    Translate { x: window.weatherContentOffset * 2 } // Exaggerated shift for background depth
                ]
            }

            // --- CENTRAL HERO: THE BREATHING TIME HUB & 3D HOURLY ORBIT ---
            Item {
                id: centralHub
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.centerOffset
                width: Math.round(1 * window.sf); height: Math.round(1 * window.sf) 
                z: 5

                opacity: introClock
                scale: 0.85 + (0.15 * introClock)

                property real levitation: 0
                SequentialAnimation on levitation {
                    loops: Animation.Infinite
                    NumberAnimation { to: Math.round(-15 * window.sf); duration: 4000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0; duration: 4000; easing.type: Easing.InOutSine }
                }

                property real orbitBreath: 1.0
                SequentialAnimation on orbitBreath {
                    loops: Animation.Infinite
                    running: true
                    NumberAnimation { to: 1.035; duration: 3500; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 3500; easing.type: Easing.InOutSine }
                }

                // 3D Perspective Wobble (Pitch, Yaw, Roll)
                property real pitchBreath: 0
                SequentialAnimation on pitchBreath {
                    loops: Animation.Infinite; running: true
                    NumberAnimation { to: 3.5; duration: 4200; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -3.5; duration: 4200; easing.type: Easing.InOutSine }
                }

                property real yawBreath: 0
                SequentialAnimation on yawBreath {
                    loops: Animation.Infinite; running: true
                    NumberAnimation { to: 2.5; duration: 5100; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -2.5; duration: 5100; easing.type: Easing.InOutSine }
                }

                property real rollBreath: 0
                SequentialAnimation on rollBreath {
                    loops: Animation.Infinite; running: true
                    NumberAnimation { to: 1.5; duration: 5800; easing.type: Easing.InOutSine }
                    NumberAnimation { to: -1.5; duration: 5800; easing.type: Easing.InOutSine }
                }
                
                transform: [
                    Translate { y: Math.round(25 * window.sf) * (1.0 - introClock) },
                    Translate { y: centralHub.levitation },
                    Rotation { axis { x: 1; y: 0; z: 0 } angle: centralHub.pitchBreath },
                    Rotation { axis { x: 0; y: 1; z: 0 } angle: centralHub.yawBreath },
                    Rotation { axis { x: 0; y: 0; z: 1 } angle: centralHub.rollBreath }
                ]

                // OPTIMIZATION: Moved scale property out of the onPaint function to prevent redrawing every frame.
                // It now draws once, and scales using the GPU.
                Canvas {
                    id: orbitCanvas
                    z: -10
                    x: Math.round(-400 * window.sf)   // Widened to prevent clipping when scaled
                    y: Math.round(-200 * window.sf)   // Heightened to prevent clipping when scaled
                    width: Math.round(800 * window.sf)
                    height: Math.round(400 * window.sf)
                    opacity: 0.25

                    scale: centralHub.orbitBreath

                    onWidthChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.beginPath();
                        var currentRx = Math.round(320 * window.sf);
                        var currentRy = Math.round(140 * window.sf);
                        for (var i = 0; i <= Math.PI * 2; i += 0.05) {
                            var xx = width/2 + Math.cos(i) * currentRx;
                            var yy = height/2 + Math.sin(i) * currentRy;
                            if (i === 0) ctx.moveTo(xx, yy); else ctx.lineTo(xx, yy);
                        }
                        ctx.strokeStyle = window.textAccent;
                        ctx.lineWidth = Math.max(1, Math.round(1.5 * window.sf));
                        ctx.setLineDash([Math.round(4 * window.sf), Math.round(10 * window.sf)]);
                        ctx.stroke();
                    }
                    Behavior on opacity { NumberAnimation { duration: 1500 } }
                }

                // Core Clock
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    z: 0 
                    scale: 0.95 + (0.05 * window.secondPulse) 
                    
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Math.round(2 * window.sf)
                        Text {
                            text: Qt.formatTime(window.currentTime, "HH:mm")
                            font.family: Fonts.ui
                            font.weight: Font.Black
                            font.pixelSize: Math.round(84 * window.sf)
                            color: window.text
                            style: Text.Outline; styleColor: Qt.alpha(window.crust, 0.4)
                        }
                        Text {
                            text: Qt.formatTime(window.currentTime, ":ss")
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: Math.round(32 * window.sf)
                            color: window.textAccent
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: Math.round(15 * window.sf)
                            opacity: window.secondPulse > 1.02 ? 1.0 : 0.6 
                            style: Text.Outline; styleColor: Qt.alpha(window.crust, 0.4)
                            Behavior on color { ColorAnimation { duration: 1000 } }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(window.currentTime, "dddd, MMMM dd")
                        font.family: Fonts.ui
                        font.weight: Font.Bold
                        font.pixelSize: Math.round(16 * window.sf)
                        color: window.subtext0
                        opacity: 0.9
                    }
                }

                // TRUE 3D ORBITAL HOURLY FORECAST (Tied to Spin Transition)
                Item {
                    anchors.fill: parent
                    opacity: window.weatherContentOpacity
                    
                    // Added Scale property to give a z-depth shrink effect when spinning
                    scale: window.transitionScale 
                    transform: Translate { x: window.weatherContentOffset * 1.5 }

                    Repeater {
                        id: hourRepeater
                        model: window.weatherData && window.weatherData.forecast[window.weatherView] && window.weatherData.forecast[window.weatherView].hourly ? window.weatherData.forecast[window.weatherView].hourly.slice(0, 8) : []
                        
                        delegate: Item {
                            property int mCount: hourRepeater.count
                            property bool isToday: window.weatherView === 0
                            property bool isHighlighted: isToday && index === window.activeHourIndex
                            
                            property real rx: Math.round(320 * window.sf) * centralHub.orbitBreath
                            property real ry: Math.round(140 * window.sf) * centralHub.orbitBreath
                            
                            property int relIdx: isToday ? (index - window.activeHourIndex) : index
                            
                            property real targetAngleDeg: isToday ? (65 + (relIdx * 30)) : (index * (360 / Math.max(1, mCount)))
                            
                            property real orbitOffset: isToday ? 0 : (window.globalOrbitAngle * (180 / Math.PI) * -1.5)
                            property real osc: isToday ? (Math.sin(window.globalOrbitAngle * 10 + index) * 5) : 0 
                            
                            // Integrated window.transitionSpin directly into the final angle calculation
                            property real rad: (targetAngleDeg + orbitOffset + osc + window.transitionSpin) * (Math.PI / 180)

                            x: Math.cos(rad) * rx - width/2
                            y: Math.sin(rad) * ry - height/2
                            z: Math.sin(rad) * Math.round(100 * window.sf) 
                            
                            scale: isHighlighted ? 1.4 : (isToday ? (0.95 + 0.20 * Math.sin(rad)) : (0.90 + 0.25 * Math.sin(rad)))
                            opacity: isHighlighted ? 1.0 : (isToday ? (0.7 + 0.3 * ((Math.sin(rad) + 1) / 2)) : (0.65 + 0.35 * ((Math.sin(rad) + 1) / 2)))

                            width: Math.round(56 * window.sf); height: Math.round(95 * window.sf)
                            
                            Rectangle {
                                anchors.fill: parent
                                radius: Radius.scaled(Math.round(28 * window.sf), 1.75, Math.round(26 * window.sf))
                                color: isHighlighted ? window.textAccent : (hrMa.containsMouse ? window.surface2 : window.surface0)
                                border.color: isHighlighted ? "transparent" : (hrMa.containsMouse ? window.textAccent : window.surface1)
                                border.width: 1
                                
                                Behavior on color { ColorAnimation { duration: 200 } }
                                
                                ColumnLayout {
                                    anchors.centerIn: parent 
                                    spacing: Math.round(4 * window.sf)
                                    
                                    Text { 
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.time
                                        font.family: Fonts.ui; font.weight: Font.Bold; font.pixelSize: Math.round(12 * window.sf)
                                        color: isHighlighted ? window.base : (hrMa.containsMouse ? window.text : window.overlay1)
                                    }
                                    
                                    Text { 
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.icon || (window.weatherData && window.weatherData.forecast[window.weatherView] ? window.weatherData.forecast[window.weatherView].icon : "")
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(18 * window.sf)
                                        color: isHighlighted ? window.base : (modelData.hex || window.text)  // Dynamic color per hourly condition
                                        
                                        transform: Translate { y: hrMa.containsMouse ? Math.round(-3 * window.sf) : 0 }
                                        Behavior on transform { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                    }
                                    
                                    Text { 
                                        Layout.alignment: Qt.AlignHCenter; text: modelData.temp + "°"
                                        font.family: Fonts.ui; font.weight: Font.Black; font.pixelSize: Math.round(14 * window.sf)
                                        color: isHighlighted ? window.base : window.text 
                                    }
                                }
                            }
                            MouseArea { id: hrMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }
            }

            // --- LEFT WING: FLOATING GLASS CALENDAR ---
            Rectangle {
                id: calendarRect
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Math.round(40 * window.sf)
                width: Math.round(320 * window.sf)
                height: Math.round(420 * window.sf)
                color: Qt.alpha(window.surface0, 0.2) 
                radius: Radius.outer(Math.round(14 * window.sf))
                border.color: Qt.alpha(window.surface1, 0.4)
                border.width: 1
                z: 10 

                opacity: introCalendar
                transform: Translate { x: Math.round(-40 * window.sf) * (1.0 - introCalendar) }

                HoverHandler { id: calHover }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Math.round(25 * window.sf)
                    spacing: Math.round(15 * window.sf)

                    RowLayout {
                        Layout.fillWidth: true
                        
                        // "Return to Today" Home Button
                        Rectangle {
                            Layout.preferredWidth: Math.round(32 * window.sf); Layout.preferredHeight: Math.round(32 * window.sf); radius: Math.round(16 * window.sf)
                            color: homeMa.containsMouse ? window.surface1 : "transparent"
                            opacity: window.targetMonthOffset !== 0 ? 1.0 : 0.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Text { anchors.centerIn: parent; text: "󰃭"; font.family: "Iosevka Nerd Font"; color: window.text; font.pixelSize: Math.round(16 * window.sf) }
                            MouseArea { 
                                id: homeMa; anchors.fill: parent; hoverEnabled: window.targetMonthOffset !== 0; 
                                onClicked: if (window.targetMonthOffset !== 0) { Sounds.playSfx("system/quick_click.wav"); window.setMonthOffset(0); } 
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: Math.round(32 * window.sf); Layout.preferredHeight: Math.round(32 * window.sf); radius: Math.round(16 * window.sf)
                            color: prevMa.containsMouse ? window.surface1 : "transparent"
                            Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; color: window.text; font.pixelSize: Math.round(16 * window.sf) }
                            MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: { Sounds.playSfx("system/quick_click.wav"); window.setMonthOffset(window.targetMonthOffset - 1); } }
                        }
                        
                        Text {
                            Layout.fillWidth: true
                            text: window.targetMonthName.toUpperCase()
                            font.family: Fonts.ui
                            font.weight: Font.Black
                            font.pixelSize: Math.round(16 * window.sf)
                            fontSizeMode: Text.Fit
                            minimumPixelSize: Math.round(8 * window.sf)
                            color: window.text
                            horizontalAlignment: Text.AlignHCenter
                            
                            opacity: window.calendarContentOpacity
                            transform: Translate { x: window.calendarContentOffset }
                        }

                        Rectangle {
                            Layout.preferredWidth: Math.round(32 * window.sf); Layout.preferredHeight: Math.round(32 * window.sf); radius: Math.round(16 * window.sf)
                            color: nextMa.containsMouse ? window.surface1 : "transparent"
                            Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; color: window.text; font.pixelSize: Math.round(16 * window.sf) }
                            MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: { Sounds.playSfx("system/quick_click.wav"); window.setMonthOffset(window.targetMonthOffset + 1); } }
                        }

                        Rectangle {
                            Layout.preferredWidth: Math.round(32 * window.sf); Layout.preferredHeight: Math.round(32 * window.sf); radius: Math.round(16 * window.sf)
                            color: diaryMa.containsMouse ? window.surface1 : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: Math.round(32 * window.sf)
                                color: window.eventsOpen ? window.textAccent
                                     : (diaryMa.containsMouse ? window.mauve : window.text)
                                // Rotates into an x while the events panel is open.
                                rotation: window.eventsOpen ? 45 : 0
                                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            MouseArea { 
                                id: diaryMa; anchors.fill: parent; hoverEnabled: true; 
                                // Toggles the month's holiday / astro-event list.
                                onClicked: {
                                    Sounds.playSfx("system/quick_click.wav");
                                    window.eventsOpen = !window.eventsOpen;
                                    if (window.eventsOpen) {
                                        window.loadRegionList();
                                        regionSearch.text = "";
                                        regionSearch.forceActiveFocus();
                                    }
                                }
                            }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Repeater {
                            model: window.weekDayNames
                            Text {
                                Layout.fillWidth: true
                                text: modelData
                                font.family: Fonts.ui
                                font.weight: Font.Black
                                font.pixelSize: Math.round(14 * window.sf)
                                color: window.overlay0
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // The grid, with the shown day's shape beneath it in the same coordinate space.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        opacity: window.calendarContentOpacity
                        transform: Translate { x: window.calendarContentOffset }

                        // One highlight for the shown day, shaped like a day cell (follows ui.radius); it slides between days.
                        Rectangle {
                            id: daySelection
                            readonly property Item cell: (window.selectedInGrid && dayRepeater.count === 42)
                                ? dayRepeater.itemAt(window.gridFirstDay + window.selectedDate.getDate() - 1) : null
                            visible: cell !== null
                            width: cell ? cell.width : 0
                            height: cell ? cell.height : 0
                            x: cell ? cell.x : 0
                            y: cell ? cell.y : 0
                            scale: cell ? cell.scale : 1
                            radius: Radius.outer(Math.round(10 * window.sf))
                            color: window.textAccent

                            // Jump on first layout or after a month change; slide only between shown days.
                            property bool slide: false
                            onCellChanged: { if (!cell) slide = false; else if (!slide) settle.restart(); }
                            Component.onCompleted: settle.restart()
                            Timer { id: settle; interval: 300; onTriggered: daySelection.slide = true }
                            Behavior on x { enabled: daySelection.slide; NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                            Behavior on y { enabled: daySelection.slide; NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                        }

                    GridLayout {
                        anchors.fill: parent
                        columns: 7
                        rowSpacing: Math.round(6 * window.sf)
                        columnSpacing: Math.round(6 * window.sf)

                        Repeater {
                            id: dayRepeater
                            model: calendarModel
                            Rectangle {
                                id: dayCell
                                readonly property bool isSelected: isCurrentMonth && window.selectedInGrid
                                                                   && parseInt(dayNum, 10) === window.selectedDate.getDate()
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                
                                color: !dayCell.isSelected && dayMa.containsMouse ? Qt.alpha(window.surface2, 0.4) : "transparent"
                                radius: Radius.outer(Math.round(10 * window.sf))
                                scale: dayMa.containsMouse ? 1.2 : 1.0
                                border.color: !dayCell.isSelected && dayMa.containsMouse ? window.overlay0 : "transparent"
                                border.width: !dayCell.isSelected && dayMa.containsMouse ? 1 : 0

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                Text {
                                    anchors.centerIn: parent
                                    text: dayNum
                                    font.family: Fonts.ui
                                    font.weight: (dayCell.isSelected || isToday) ? Font.Black : Font.Bold
                                    font.pixelSize: Math.round(14 * window.sf)
                                    color: dayCell.isSelected ? window.base : (isToday ? window.textAccent : (isCurrentMonth ? window.text : window.surface0))
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                // Event marker: a dot under days with a holiday /
                                // astronomical event in the shown month.
                                Rectangle {
                                    visible: isCurrentMonth && window.holidaysByDay[parseInt(dayNum, 10)] !== undefined
                                    width: Math.round(4 * window.sf); height: width; radius: width / 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Math.round(3 * window.sf)
                                    color: dayCell.isSelected ? window.base : window.textAccent
                                    opacity: 0.9
                                }

                                MouseArea {
                                    id: dayMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: isCurrentMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: if (isCurrentMonth) { Sounds.playSfx("system/quick_click.wav"); window.selectDay(parseInt(dayNum, 10)); }
                                }

                                // High z and no clipping ancestors, so it floats over neighbouring cells.
                                Rectangle {
                                    id: dayTip
                                    z: 999
                                    readonly property var names: window.holidaysByDay[parseInt(dayNum, 10)]
                                    visible: opacity > 0.01
                                    opacity: (isCurrentMonth && dayMa.containsMouse && dayTip.names !== undefined) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    width: tipText.implicitWidth + Math.round(16 * window.sf)
                                    height: tipText.implicitHeight + Math.round(10 * window.sf)
                                    radius: Radius.outer(Math.round(8 * window.sf))
                                    color: window.base
                                    border.color: Qt.alpha(window.textAccent, 0.5)
                                    border.width: 1

                                    // Sit above the cell, and stay inside the card.
                                    x: Math.max(-parent.x + Math.round(4 * window.sf),
                                         Math.min((parent.width - width) / 2,
                                                  calendarRect.width - parent.x - width - Math.round(20 * window.sf)))
                                    y: -height - Math.round(4 * window.sf)

                                    Text {
                                        id: tipText
                                        anchors.centerIn: parent
                                        text: dayTip.names !== undefined ? dayTip.names.join("\n") : ""
                                        font.family: Fonts.ui
                                        font.pixelSize: Math.round(10 * window.sf)
                                        color: window.text
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }
                        }
                    }
                    }

                }

                // --- Region picker --- written to ~/.config/quickshell/calendar-region.
                Rectangle {
                    id: regionPanel
                    anchors.fill: parent
                    radius: parent.radius
                    color: window.base
                    border.color: Qt.alpha(window.surface1, 0.5)
                    border.width: 1
                    clip: true

                    visible: opacity > 0.01
                    opacity: window.eventsOpen ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Math.round(16 * window.sf)
                        spacing: Math.round(8 * window.sf)

                        // Header: title + its own close button, so the picker can be
                        // dismissed without Esc taking the whole popup down with it.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Math.round(8 * window.sf)

                            Text {
                                Layout.fillWidth: true
                                text: "HOLIDAY REGION"
                                font.family: Fonts.ui
                                font.weight: Font.Black
                                font.pixelSize: Math.round(12 * window.sf)
                                color: window.textAccent
                            }

                            Rectangle {
                                Layout.preferredWidth: Math.round(22 * window.sf)
                                Layout.preferredHeight: Math.round(22 * window.sf)
                                radius: Radius.outer(Math.round(7 * window.sf))
                                color: closeMa.containsMouse ? Qt.alpha(window.surface2, 0.6) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{f0156}"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: Math.round(13 * window.sf)
                                    color: closeMa.containsMouse ? window.text : window.overlay0
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }
                                MouseArea {
                                    id: closeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { Sounds.playSfx("system/quick_click.wav"); window.eventsOpen = false; }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: window.holidayRegion
                            font.family: Fonts.ui
                            font.pixelSize: Math.round(9 * window.sf)
                            color: window.overlay0
                            elide: Text.ElideRight
                        }

                        // Search — 170 regions is far too many to scroll through.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.round(26 * window.sf)
                            radius: Radius.outer(Math.round(8 * window.sf))
                            color: Qt.alpha(window.surface0, 0.6)
                            border.width: 1
                            border.color: regionSearch.activeFocus ? Qt.alpha(window.textAccent, 0.6)
                                                                   : Qt.alpha(window.surface1, 0.6)
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Math.round(8 * window.sf)
                                anchors.rightMargin: Math.round(8 * window.sf)
                                spacing: Math.round(6 * window.sf)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u{f0349}"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: Math.round(11 * window.sf)
                                    color: window.overlay0
                                }

                                TextField {
                                    id: regionSearch
                                    width: parent.width - Math.round(24 * window.sf)
                                    anchors.verticalCenter: parent.verticalCenter
                                    background: Item {}
                                    padding: 0
                                    color: window.text
                                    font.family: Fonts.ui
                                    font.pixelSize: Math.round(10 * window.sf)
                                    placeholderText: "Search regions"
                                    placeholderTextColor: window.overlay0
                                    onTextChanged: window.regionFilter = text
                                    // Esc closes just the picker, not the whole popup.
                                    Keys.onEscapePressed: (event) => {
                                        window.eventsOpen = false;
                                        event.accepted = true;
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Qt.alpha(window.surface1, 0.6)
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Math.round(1 * window.sf)
                            model: window.regionListFiltered
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: regRow
                                width: ListView.view.width
                                height: Math.round(24 * window.sf)
                                radius: Radius.outer(Math.round(6 * window.sf))
                                readonly property bool isCurrent: modelData.code === window.holidayRegion
                                color: regRow.isCurrent ? Qt.alpha(window.textAccent, 0.18)
                                                        : (regMa.containsMouse ? Qt.alpha(window.surface2, 0.5) : "transparent")
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Math.round(8 * window.sf)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Math.round(16 * window.sf)
                                    text: modelData.name
                                    font.family: Fonts.ui
                                    font.weight: regRow.isCurrent ? Font.Bold : Font.Normal
                                    font.pixelSize: Math.round(10 * window.sf)
                                    color: regRow.isCurrent ? window.textAccent : window.text
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: regMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Sounds.playSfx("system/quick_click.wav");
                                        window.setRegion(modelData.code);
                                        window.eventsOpen = false;
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: window.regionListFiltered.length === 0
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            text: !window.khdumpAvailable ? "Helper not built.\nRun helpers/kholidays/build.sh"
                                  : (window.regionList.length === 0 ? "Loading regions..."
                                                                    : "No region matches \"" + window.regionFilter + "\"")
                            font.family: Fonts.ui
                            font.pixelSize: Math.round(10 * window.sf)
                            color: window.overlay0
                        }
                    }
                }

            }

            // --- RIGHT WING: ORGANIC FLOATING WEATHER STATS ---
            Item {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Math.round(40 * window.sf)
                width: Math.round(320 * window.sf)
                height: Math.round(420 * window.sf)
                z: 10 

                opacity: introWeather
                transform: Translate { x: Math.round(40 * window.sf) * (1.0 - introWeather) }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Math.round(20 * window.sf)

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        spacing: Math.round(20 * window.sf)
                        
                        MouseArea { 
                            id: wPrevMa; Layout.preferredWidth: Math.round(30 * window.sf); Layout.preferredHeight: Math.round(30 * window.sf); hoverEnabled: true
                            onClicked: { Sounds.playSfx("system/quick_click.wav"); window.setWeatherView(window.targetWeatherView - 1); } 
                            
                            property real pulseOffset: 0
                            SequentialAnimation on pulseOffset {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { to: Math.round(-3 * window.sf); duration: 1000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0; duration: 1000; easing.type: Easing.InOutSine }
                            }
                            
                            Text { 
                                anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(18 * window.sf)
                                color: parent.containsMouse ? window.textAccent : window.overlay1
                                transform: Translate { x: wPrevMa.containsMouse ? Math.round(-5 * window.sf) : wPrevMa.pulseOffset }
                                Behavior on transform { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            }
                        }
                        
                        Text {
                            Layout.fillWidth: true 
                            horizontalAlignment: Text.AlignHCenter 
                            text: window.weatherData && window.weatherData.forecast[window.weatherView] ? window.weatherData.forecast[window.weatherView].day_full.toUpperCase() : "LOADING..."
                            font.family: Fonts.ui
                            font.weight: Font.Black
                            font.pixelSize: Math.round(16 * window.sf)
                            fontSizeMode: Text.Fit
                            minimumPixelSize: Math.round(8 * window.sf)
                            color: window.text
                        }
                        
                        MouseArea { 
                            id: wNextMa; Layout.preferredWidth: Math.round(30 * window.sf); Layout.preferredHeight: Math.round(30 * window.sf); hoverEnabled: true
                            onClicked: { Sounds.playSfx("system/quick_click.wav"); window.setWeatherView(window.targetWeatherView + 1); }
                            
                            property real pulseOffset: 0
                            SequentialAnimation on pulseOffset {
                                loops: Animation.Infinite; running: true
                                NumberAnimation { to: Math.round(3 * window.sf); duration: 1000; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0; duration: 1000; easing.type: Easing.InOutSine }
                            }
                            
                            Text { 
                                anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(18 * window.sf)
                                color: parent.containsMouse ? window.textAccent : window.overlay1
                                transform: Translate { x: wNextMa.containsMouse ? Math.round(5 * window.sf) : wNextMa.pulseOffset }
                                Behavior on transform { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight 
                        spacing: Math.round(-5 * window.sf)
                        
                        // BIG TEMPERATURE TEXT - Anchored so it doesn't slide with the wrapper
                        Text {
                            Layout.alignment: Qt.AlignRight 
                            text: Math.round(window.displayedTemp) + "°"
                            font.family: Fonts.ui
                            font.weight: Font.Black
                            font.pixelSize: Math.round(84 * window.sf)
                            color: window.tempGlowColor
                            style: Text.Outline; 
                            styleColor: window.isTempAnimating ? Qt.alpha(window.tempGlowColor, 0.5) : Qt.alpha(window.crust, 0.4)
                            
                            Behavior on color { ColorAnimation { duration: 300 } }
                            Behavior on styleColor { ColorAnimation { duration: 300 } }
                        }
                        
                        Text {
                            Layout.alignment: Qt.AlignRight
                            Layout.maximumWidth: Math.round(320 * window.sf)
                            horizontalAlignment: Text.AlignRight
                            text: window.weatherData && window.weatherData.forecast[window.weatherView] ? window.weatherData.forecast[window.weatherView].desc : ""
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: Math.round(16 * window.sf)
                            wrapMode: Text.WordWrap
                            color: window.textAccent
                            Behavior on color { ColorAnimation { duration: 1000 } }
                            
                            opacity: window.weatherContentOpacity
                            transform: Translate { x: window.weatherContentOffset }
                        }

                        // Holidays and events on the shown day.
                        Text {
                            readonly property var names: window.selectedInGrid ? window.holidaysByDay[window.selectedDate.getDate()] : undefined
                            visible: names !== undefined
                            Layout.alignment: Qt.AlignRight
                            Layout.maximumWidth: Math.round(320 * window.sf)
                            Layout.topMargin: Math.round(10 * window.sf)
                            horizontalAlignment: Text.AlignRight
                            text: visible ? names.join("\n") : ""
                            font.family: Fonts.ui
                            font.pixelSize: Math.round(12 * window.sf)
                            wrapMode: Text.WordWrap
                            color: window.text

                            opacity: window.weatherContentOpacity * 0.85
                            transform: Translate { x: window.weatherContentOffset }
                        }
                    }

                    Item { Layout.fillHeight: true } 

                    // v2's weather stats: a 2x2 grid of chips, icon + value over a small label.
                    GridLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                        columns: 2
                        rowSpacing: window.s(8)
                        columnSpacing: window.s(8)

                        Repeater {
                            model: 4

                            ClickButton {
                                required property int index
                                Layout.preferredWidth: window.s(118)
                                Layout.preferredHeight: window.s(42)
                                cornerRadius: Radius.outer(window.s(9))
                                horizontalPadding: window.s(8)

                                readonly property var forecast: window.weatherData && window.weatherData.forecast[window.targetWeatherView]
                                                                ? window.weatherData.forecast[window.targetWeatherView] : null
                                readonly property bool imperial: ShellSettings.value("weather.unit", "metric") === "imperial"

                                buttonIcon: index === 0 ? "\u{f059d}" : index === 1 ? "\u{f058e}" : index === 2 ? "\u{f0597}" : "\u{f050f}"
                                buttonText: forecast ? (
                                    index === 0 ? forecast.wind + (imperial ? "mph" : "m/s") :
                                    index === 1 ? forecast.humidity + "%" :
                                    index === 2 ? forecast.pop + "%" :
                                    forecast.feels_like + "°"
                                ) : ""
                                subText: index === 0 ? "Wind" : index === 1 ? "Humid" : index === 2 ? "Rain" : "Feels"

                                iconFontSize: window.s(14)
                                textFontSize: window.s(11.5)
                                accentColor: window.surface0
                                // Accent icon, readable value, dim label; hover lights the whole chip.
                                iconColor: window.textAccent
                                textColor: isHoveredOrHighlighted ? window.textAccent : window.text
                                subTextColor: isHoveredOrHighlighted ? window.textAccent : window.overlay0
                            }
                        }
                    }
                }
            }

            // --- BOTTOM SECTION: FRAMELESS FLUID DATA STREAM (SCHEDULE) ---
            Item {
                id: bottomSection
                
                // CONDITIONAL RENDERING BINDING
                visible: window.scheduleModuleExists
                
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.round(240 * window.sf)
                z: 20 

                opacity: introSchedule
                transform: Translate { y: Math.round(50 * window.sf) * (1.0 - introSchedule) }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.alpha(window.crust, 0.6) }
                    }
                }

                Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Qt.alpha(window.surface1, 0.5) }

                // OPTIMIZATION: Separated the massive continuous Canvas path-drawing loop into three pre-rendered hardware-accelerated static layers.
                Item {
                    anchors.fill: parent
                    z: -1
                    opacity: 0.15
                    clip: true

                    // Wave 1 - Mauve
                    Canvas {
                        id: wave1
                        property real wLen: Math.round(100 * window.sf) * 2 * Math.PI
                        width: parent.width + wLen
                        height: parent.height
                        
                        NumberAnimation on x { from: 0; to: -wave1.wLen; duration: 4000; loops: Animation.Infinite; running: window.scheduleModuleExists }
                        
                        onWidthChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var cy = height / 2;
                            ctx.beginPath();
                            ctx.moveTo(0, cy);
                            for(var i = 0; i <= width + Math.round(20 * window.sf); i += Math.round(10 * window.sf)) {
                                ctx.lineTo(i, cy + Math.sin(i/Math.round(100 * window.sf)) * Math.round(30 * window.sf));
                            }
                            ctx.strokeStyle = window.mauve;
                            ctx.lineWidth = Math.round(2 * window.sf);
                            ctx.stroke();
                        }
                    }

                    // Wave 2 - Sapphire
                    Canvas {
                        id: wave2
                        property real wLen: Math.round(120 * window.sf) * 2 * Math.PI
                        width: parent.width + wLen
                        height: parent.height
                        
                        NumberAnimation on x { from: -wave2.wLen; to: 0; duration: 5500; loops: Animation.Infinite; running: window.scheduleModuleExists }
                        
                        onWidthChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var cy = height / 2;
                            ctx.beginPath();
                            ctx.moveTo(0, cy);
                            for(var i = 0; i <= width + Math.round(20 * window.sf); i += Math.round(10 * window.sf)) {
                                ctx.lineTo(i, cy + Math.sin(i/Math.round(120 * window.sf)) * Math.round(40 * window.sf));
                            }
                            ctx.strokeStyle = window.sapphire;
                            ctx.lineWidth = Math.round(2 * window.sf);
                            ctx.stroke();
                        }
                    }

                    // Wave 3 - Peach
                    Canvas {
                        id: wave3
                        property real wLen: Math.round(80 * window.sf) * 2 * Math.PI
                        width: parent.width + wLen
                        height: parent.height
                        
                        NumberAnimation on x { from: 0; to: -wave3.wLen; duration: 7000; loops: Animation.Infinite; running: window.scheduleModuleExists }
                        
                        onWidthChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var cy = height / 2;
                            ctx.beginPath();
                            ctx.moveTo(0, cy);
                            for(var i = 0; i <= width + Math.round(20 * window.sf); i += Math.round(10 * window.sf)) {
                                ctx.lineTo(i, cy + Math.sin(i/Math.round(80 * window.sf)) * Math.round(20 * window.sf));
                            }
                            ctx.strokeStyle = window.peach;
                            ctx.lineWidth = Math.round(2 * window.sf);
                            ctx.stroke();
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Math.round(25 * window.sf)
                    spacing: Math.round(15 * window.sf)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Math.round(15 * window.sf)
                        
                        Rectangle {
                            Layout.preferredWidth: Math.round(40 * window.sf); Layout.preferredHeight: Math.round(40 * window.sf); radius: Math.round(20 * window.sf); color: window.surface0
                            Text { anchors.centerIn: parent; text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(18 * window.sf); color: window.textAccent }
                        }
                        
                        Text { 
                            Layout.fillWidth: true // FIX: Ensures text shrinks/elides instead of expanding layout infinitely
                            text: window.scheduleData ? window.scheduleData.header : "Loading Schedule..."
                            font.family: Fonts.ui
                            font.weight: Font.Bold
                            font.pixelSize: Math.round(16 * window.sf)
                            color: window.overlay0
                            elide: Text.ElideRight
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Rectangle {
                            Layout.preferredWidth: Math.round(120 * window.sf); Layout.preferredHeight: Math.round(36 * window.sf); radius: Radius.outer(Math.round(10 * window.sf))
                            color: schLinkMa.containsMouse ? window.mauve : Qt.alpha(window.surface1, 0.5)
                            border.color: window.mauve; border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Math.round(6 * window.sf)
                                Text { text: "Open Web"; font.family: Fonts.ui; font.weight: Font.Bold; font.pixelSize: Math.round(14 * window.sf); color: schLinkMa.containsMouse ? window.base : window.text }
                                Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(14 * window.sf); color: schLinkMa.containsMouse ? window.base : window.text }
                            }
                            
                            MouseArea {
                                id: schLinkMa; anchors.fill: parent; hoverEnabled: true
                                onClicked: if(window.scheduleData && window.scheduleData.link) Quickshell.execDetached(["xdg-open", window.scheduleData.link])
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            text: "Data stream offline. No scheduled events."
                            font.family: Fonts.ui
                            font.italic: true
                            font.pixelSize: Math.round(14 * window.sf)
                            color: window.overlay0
                            visible: window.scheduleData && window.scheduleData.lessons.length === 0
                            anchors.centerIn: parent
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.round(2 * window.sf)
                            color: Qt.alpha(window.surface1, 0.4)
                            visible: window.scheduleData && window.scheduleData.lessons.length > 0
                        }

                        ScrollView {
                            id: schedScroll
                            anchors.fill: parent
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AlwaysOff
                            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                            visible: window.scheduleData && window.scheduleData.lessons.length > 0
                            contentWidth: scheduleRow.width
                            contentHeight: parent.height

                            Row {
                                id: scheduleRow
                                height: parent.height
                                spacing: 0
                                
                                // Divide the actual rendered width of the scroll area by the 430 minutes in a standard school day 
                                // to get the dynamic Pixels Per Minute ratio that stretches perfectly across the entire space.
                                property real ppm: schedScroll.width / 430.0

                                Repeater {
                                    model: window.scheduleData ? window.scheduleData.lessons : []

                                    delegate: Item {
                                        property bool isClass: modelData.type === "class"
                                        
                                        // Calculate the exact duration in minutes directly from the start and end epochs 
                                        property real durationMinutes: ((modelData.end || 0) - (modelData.start || 0)) / 60.0
                                        
                                        // Multiply duration by PPM and round to the nearest whole pixel to avoid sub-pixel gaps entirely
                                        width: Math.max(1, Math.round(durationMinutes * scheduleRow.ppm))
                                        height: parent.height
                                        
                                        Item {
                                            id: classNode
                                            anchors.fill: parent
                                            anchors.topMargin: Math.round(10 * window.sf)
                                            anchors.bottomMargin: Math.round(10 * window.sf)
                                            visible: parent.isClass
                                            
                                            property bool isActive: parent.isClass && window.currentEpoch >= (modelData.start || 0) && window.currentEpoch <= (modelData.end || 0)
                                            property bool isPast: parent.isClass && window.currentEpoch > (modelData.end || 0)
                                            
                                            Canvas {
                                                anchors.fill: parent
                                                visible: classMa.containsMouse || classNode.isActive
                                                opacity: classMa.containsMouse ? 0.2 : 0.08
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                                
                                                property real wavePhase: 0
                                                NumberAnimation on wavePhase {
                                                    from: 0; to: Math.PI * 2; duration: 2000; loops: Animation.Infinite; running: parent.visible
                                                }
                                                onWavePhaseChanged: requestPaint()
                                                onPaint: {
                                                    var ctx = getContext("2d");
                                                    ctx.clearRect(0, 0, width, height);
                                                    ctx.beginPath();
                                                    ctx.moveTo(0, height);
                                                    for(var x = 0; x <= width; x += Math.round(10 * window.sf)) {
                                                        ctx.lineTo(x, height/2 + Math.sin(x/Math.round(25 * window.sf) + wavePhase) * Math.round(20 * window.sf));
                                                    }
                                                    ctx.lineTo(width, height);
                                                    ctx.lineTo(0, height);
                                                    var grad = ctx.createLinearGradient(0, 0, width, 0);
                                                    grad.addColorStop(0, window.mauve);
                                                    grad.addColorStop(1, "transparent");
                                                    ctx.fillStyle = grad;
                                                    ctx.fill();
                                                }
                                            }

                                            Rectangle {
                                                id: accentLine
                                                width: classNode.isActive || classMa.containsMouse ? Math.round(4 * window.sf) : Math.round(2 * window.sf)
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                radius: Math.round(2 * window.sf)
                                                color: classNode.isActive ? window.mauve : (classNode.isPast ? window.surface1 : window.surface2)
                                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }

                                            ColumnLayout {
                                                anchors.left: accentLine.right
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: classMa.containsMouse ? Math.round(25 * window.sf) : Math.round(15 * window.sf)
                                                Behavior on anchors.leftMargin { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                                spacing: Math.round(6 * window.sf)

                                                Text {
                                                    text: modelData.subject || ""
                                                    font.family: Fonts.ui
                                                    font.weight: Font.Black
                                                    font.pixelSize: Math.round(16 * window.sf)
                                                    color: classNode.isActive ? window.mauve : (classNode.isPast ? window.overlay0 : window.text)
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }

                                                RowLayout {
                                                    visible: !modelData.is_compact
                                                    spacing: Math.round(8 * window.sf)
                                                    Text { text: "󰅐"; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(14 * window.sf); color: classNode.isActive ? window.mauve : window.overlay1 }
                                                    Text { text: modelData.time || ""; font.family: Fonts.ui; font.weight: Font.Bold; font.pixelSize: Math.round(14 * window.sf); color: classNode.isActive ? window.text : window.overlay1 }
                                                }

                                                RowLayout {
                                                    visible: !modelData.is_compact && (modelData.room || "") !== ""
                                                    spacing: Math.round(8 * window.sf)
                                                    Text { text: ""; font.family: "Iosevka Nerd Font"; font.pixelSize: Math.round(14 * window.sf); color: classNode.isPast ? window.surface2 : window.peach }
                                                    Text { text: modelData.room || ""; font.family: Fonts.ui; font.weight: Font.Bold; font.pixelSize: Math.round(14 * window.sf); color: window.subtext1; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                            }

                                            MouseArea { id: classMa; anchors.fill: parent; hoverEnabled: parent.visible }
                                        }

                                        Item {
                                            anchors.fill: parent
                                            visible: !parent.isClass
                                            
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                height: gapMa.containsMouse ? Math.round(4 * window.sf) : Math.round(2 * window.sf)
                                                color: gapMa.containsMouse ? window.mauve : "transparent"
                                                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: breakText.width + Math.round(16 * window.sf)
                                                height: Math.round(24 * window.sf)
                                                radius: Radius.outer(Math.round(6 * window.sf))
                                                color: window.mantle
                                                border.color: window.surface2
                                                border.width: 1
                                                opacity: gapMa.containsMouse ? 1.0 : 0.0
                                                scale: gapMa.containsMouse ? 1.0 : 0.8
                                                Behavior on opacity { NumberAnimation { duration: 150 } }
                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                                                Text {
                                                    id: breakText
                                                    anchors.centerIn: parent
                                                    text: modelData.desc || ""
                                                    font.family: Fonts.ui
                                                    font.weight: Font.Bold
                                                    font.pixelSize: Math.round(14 * window.sf)
                                                    color: window.mauve
                                                }
                                            }

                                            MouseArea { id: gapMa; anchors.fill: parent; hoverEnabled: parent.visible }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
