// v2's weather face.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as Plasma5Support

LockCard {
    id: box
    implicitHeight: box.lock.s(182)

    property var weather: null
    readonly property bool ready: weather !== null
    property var hourly: []
    readonly property var today: (weather && weather.forecast && weather.forecast[0]) ? weather.forecast[0] : null
    readonly property color accent: (weather && weather.current_hex && weather.current_hex.length === 7) ? weather.current_hex : lock.mauve

    function num(v) { var n = parseFloat(v); return isNaN(n) ? "--" : Math.round(n); }

    // The next four hours of the forecast, starting at the current hour.
    function updateHourly() {
        var all = [];
        if (weather && weather.forecast)
            for (var d = 0; d < weather.forecast.length; d++)
                if (weather.forecast[d].hourly) all = all.concat(weather.forecast[d].hourly);
        if (all.length === 0) { box.hourly = []; return; }
        var ch = new Date().getHours(), best = -1, minDiff = 999;
        for (var i = 0; i < all.length; i++) {
            var h = parseInt(("" + (all[i].time || "0")).split(":")[0], 10);
            var diff = h - ch;
            if (diff >= 0 && diff < minDiff) { minDiff = diff; best = i; }
        }
        if (best < 0) best = 0;
        box.hourly = all.slice(best, best + 4);
    }

    function formatHour(t) {
        var h = parseInt(("" + t).split(":")[0], 10);
        if (isNaN(h)) return "" + t;
        if (box.lock.is12Hour) return ((h % 12) === 0 ? 12 : h % 12) + (h >= 12 ? "PM" : "AM");
        return (h < 10 ? "0" + h : h) + ":00";
    }

    Plasma5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: (src, d) => {
            source.disconnectSource(src);
            var out = ("" + (d["stdout"] || "")).trim();
            if (out === "") return;
            try { box.weather = JSON.parse(out); box.updateHourly(); } catch (e) {}
        }
        function poll() {
            var cmd = "sh -c 'cat \"$HOME/.cache/quickshell/weather/weather.json\"'";
            disconnectSource(cmd);
            connectSource(cmd);
        }
        Component.onCompleted: poll()
    }
    Timer { interval: 300000; running: true; repeat: true; onTriggered: source.poll() }
    Timer { interval: 60000; running: box.ready; repeat: true; onTriggered: box.updateHourly() }

    LoaderIcon {
        anchors.centerIn: parent
        width: box.lock.s(36); height: box.lock.s(36)
        accentColor: box.lock.mauve
        running: !box.ready
        visible: !box.ready
    }

    RowLayout {
        anchors.fill: parent
        anchors.topMargin: box.lock.s(12)
        anchors.bottomMargin: box.lock.s(12)
        anchors.leftMargin: box.lock.s(14)
        anchors.rightMargin: box.lock.s(14)
        spacing: box.lock.s(10)
        visible: box.ready

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            spacing: 0

            Text {
                text: box.weather && box.weather.current_icon ? box.weather.current_icon : ""
                font.family: box.lock.iconFont
                font.pixelSize: box.lock.s(46)
                color: box.accent
                Layout.alignment: Qt.AlignTop | Qt.AlignLeft
                transform: Translate { y: -box.lock.s(4) }
            }
            Item { Layout.fillHeight: true }
            ColumnLayout {
                Layout.alignment: Qt.AlignBottom | Qt.AlignLeft
                spacing: box.lock.s(1)
                Text {
                    text: box.num(box.weather ? box.weather.current_temp : "") + "°"
                    font.family: box.lock.uiFont
                    font.pixelSize: box.lock.s(34)
                    font.weight: Font.Black
                    color: box.lock.text
                }
                Text {
                    text: "Feels like " + box.num(box.today ? box.today.feels_like : "") + "°"
                    font.family: box.lock.uiFont
                    font.pixelSize: box.lock.s(11)
                    font.weight: Font.Medium
                    color: box.lock.subtext0
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1.3
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                spacing: box.lock.s(1)
                Text {
                    Layout.fillWidth: true
                    text: box.weather && box.weather.city ? box.weather.city : (box.today ? box.today.day_full || "" : "")
                    font.family: box.lock.uiFont
                    font.pixelSize: box.lock.s(14)
                    font.weight: Font.Bold
                    color: box.lock.text
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: box.today ? (box.today.desc || "") : ""
                    font.family: box.lock.uiFont
                    font.pixelSize: box.lock.s(11)
                    font.weight: Font.Medium
                    color: box.lock.subtext0
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.alignment: Qt.AlignBottom | Qt.AlignRight
                spacing: box.lock.s(8)
                Repeater {
                    model: box.hourly
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                        spacing: box.lock.s(2)
                        Text {
                            text: box.num(modelData.temp) + "°"
                            color: box.lock.subtext0
                            font.family: box.lock.uiFont
                            font.pixelSize: box.lock.s(12)
                            font.weight: Font.Medium
                            Layout.alignment: Qt.AlignHCenter
                            transform: Translate { x: box.lock.s(2) }
                        }
                        Text {
                            text: modelData.icon || ""
                            color: (modelData.hex && modelData.hex.length === 7) ? modelData.hex : box.accent
                            font.family: box.lock.iconFont
                            font.pixelSize: box.lock.s(20)
                            Layout.alignment: Qt.AlignHCenter
                            transform: Translate { x: -box.lock.s(2) }
                        }
                        Text {
                            text: box.formatHour(modelData.time)
                            color: box.lock.subtext0
                            font.family: box.lock.uiFont
                            font.pixelSize: box.lock.s(10)
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
