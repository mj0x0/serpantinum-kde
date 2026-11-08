import QtQuick
import org.kde.plasma.clock

// The strings upstream's DateTime singleton handed the faces, fed by Plasma's clock.
QtObject {
    id: root

    property int use24hFormat: 1
    property bool showSeconds: false

    readonly property Clock clock: Clock {
        trackSeconds: root.showSeconds
    }
    readonly property date now: clock.dateTime

    readonly property bool is12Hour: use24hFormat === 0
        || (use24hFormat === 1 && /ap/i.test(Qt.locale().timeFormat(Locale.ShortFormat)))
    readonly property string amPmSuffix: is12Hour ? " AP" : ""
    readonly property string timeShortFormat: (is12Hour ? "hh" : "HH") + ":mm" + amPmSuffix
    readonly property string timeFormat: (is12Hour ? "hh" : "HH") + ":mm" + (showSeconds ? ":ss" : "") + amPmSuffix

    readonly property string hour: {
        let h = now.getHours();
        if (is12Hour)
            h = h % 12 || 12;
        return String(h).padStart(2, "0");
    }
    readonly property string minute: Qt.locale().toString(now, "mm")
    readonly property string second: Qt.locale().toString(now, "ss")
    readonly property string amPm: is12Hour ? Qt.locale().toString(now, "AP") : ""
    readonly property string time: Qt.locale().toString(now, timeFormat)
    readonly property string timeShort: Qt.locale().toString(now, timeShortFormat)
    readonly property string dateBadge: Qt.locale().toString(now, "d MMM").toUpperCase()
    readonly property string fullDate: Qt.locale().toString(now, "dddd, MMMM d")
}
