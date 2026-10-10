// Shim, not a port: upstream Weather's member names over the rice's weather cache
// (helpers/weather.sh, kept fresh by the bar poller). Named WeatherBridge: the rice already
// has Weather types (bar widget, notification). Reads the cache only, never fetches.
pragma Singleton

import "../caching"
import "../settings"
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    Caching { id: caching }

    readonly property string unit: "" + ShellSettings.value("weather.unit", "metric")

    property var data: ({})
    property var forecast: []
    property string currentIcon: ""
    property string currentTemp: ""
    property string currentTempFormatted: "--°"
    property string currentHex: (typeof ThemeBackend !== "undefined" && ThemeBackend.yellow) ? ThemeBackend.yellow.toString() : "#f9e2af"
    property string unitSym: unit === "imperial" ? "°F" : (unit === "standard" ? "K" : "°C")
    property real latitude: 0.0
    property real longitude: 0.0

    property bool isLoading: false
    property bool isReady: false

    signal weatherUpdated()

    function refresh(showLoader) {}

    function forceFetch() {
        return root.data;
    }

    function getData() {
        return root.data;
    }

    function parseJson(rawText) {
        if (!rawText) {
            root.isLoading = false;
            return;
        }
        let txt = typeof rawText === "function" ? rawText() : rawText;
        if (typeof txt !== "string") txt = String(txt || "");
        txt = txt.trim();
        if (txt === "") {
            root.isLoading = false;
            return;
        }

        try {
            let parsed = JSON.parse(txt);
            root.data = parsed;

            if (parsed.offline === true) {
                root.currentTemp = "";
                root.currentTempFormatted = "--°";
            }

            if (parsed.current_icon !== undefined) {
                root.currentIcon = parsed.current_icon;
            }
            if (parsed.current_temp_formatted !== undefined) {
                root.currentTempFormatted = parsed.current_temp_formatted;
            } else if (parsed.current_temp !== undefined && parsed.current_temp !== null) {
                let sym = parsed.unit_sym || root.unitSym;
                root.currentTempFormatted = parsed.current_temp.toString() + sym;
            }
            if (parsed.current_temp !== undefined) {
                root.currentTemp = parsed.current_temp.toString();
            }
            if (parsed.current_hex !== undefined) {
                root.currentHex = parsed.current_hex;
            }
            if (parsed.unit_sym !== undefined) {
                root.unitSym = parsed.unit_sym;
            }
            if (parsed.latitude !== undefined) {
                root.latitude = Number(parsed.latitude);
            }
            if (parsed.longitude !== undefined) {
                root.longitude = Number(parsed.longitude);
            }
            if (parsed.forecast && Array.isArray(parsed.forecast)) {
                root.forecast = parsed.forecast;
            }

            root.isReady = true;
            root.isLoading = false;
            root.weatherUpdated();
        } catch(e) {
            root.isLoading = false;
        }
    }

    FileView {
        id: weatherWatcher
        path: caching.getCacheDir("weather") + "/weather.json"
        watchChanges: true
        onLoaded: root.parseJson(typeof weatherWatcher.text === "function" ? weatherWatcher.text() : weatherWatcher.text)
        onFileChanged: root.parseJson(typeof weatherWatcher.text === "function" ? weatherWatcher.text() : weatherWatcher.text)
    }
}
