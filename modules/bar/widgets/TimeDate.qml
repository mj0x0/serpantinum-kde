// Clock and typed-in date (bar.time.format); opens the calendar. Three faces from
// serpantinum v2: classic stacked, material diagonal, badge dot-matrix (bar.timeStyle).
import "../../../services/audio"
import "../../calendar"
import "../../../services/theme"
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: timedate
    required property var barWindow
    required property var mocha
    property bool vertical: false
    property bool placed: true
    property bool grouped: false
    property real targetX: 0
    property real targetY: 0
    property bool isHovered: clockMouse.containsMouse

    readonly property string style: barWindow.timeStyle
    readonly property bool isClassic: style !== "material" && style !== "badge"

    // Time parts straight off the clock; no regex, bar.time.format decides what exists.
    readonly property var timeParts: {
        const raw = ("" + barWindow.timeStr).trim();
        const sp = raw.indexOf(" ");
        const ampm = sp > 0 ? raw.substring(sp + 1).toUpperCase() : "";
        const parts = (sp > 0 ? raw.substring(0, sp) : raw).split(":");
        return {
            hours: parts.length > 0 ? parts[0] : "",
            minutes: parts.length > 1 ? parts[1] : "",
            seconds: parts.length > 2 ? parts[2] : "",
            ampm: ampm,
            hasMinutes: parts.length > 1,
            hasSeconds: parts.length > 2
        };
    }
    readonly property string weekdayStr: { barWindow.minuteStr; return Qt.formatDateTime(new Date(), "ddd").toUpperCase(); }
    readonly property string matrixDate: dayStr + " " + monthStr

    // Measured on the full date, so the typewriter never shifts the neighbours.
    readonly property real textColWidth: Math.max(timeMeasure.implicitWidth, dateMeasure.implicitWidth)
    readonly property real classicWidth: textColWidth + barWindow.s(28)
    readonly property real faceWidth: isClassic ? classicWidth
                                    : ((style === "material" ? matRow.implicitWidth : badgeRow.implicitWidth) + barWindow.s(20))
    readonly property real faceHeight: isClassic ? (vClock.implicitHeight + barWindow.s(20))
                                     : ((style === "material" ? matCol.implicitHeight : badgeCol.implicitHeight) + barWindow.s(20))
    readonly property real targetWidth: (placed && !vertical) ? faceWidth : 0
    readonly property real targetHeight: (placed && vertical) ? faceHeight : 0

    x: vertical ? 0 : targetX
    y: vertical ? targetY : (parent.height - barWindow.barHeight) / 2
    width: vertical ? parent.width : targetWidth
    height: vertical ? targetHeight : barWindow.barHeight
    Behavior on x { enabled: barWindow.startupCascadeFinished && !timedate.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: barWindow.startupCascadeFinished && timedate.vertical; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: !timedate.vertical; NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
    visible: placed && (vertical ? height : width) > 0

    color: grouped ? "transparent" : (isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : barWindow.pillBg)
    radius: barWindow.pillRadius
    border.width: grouped ? 0 : 1
    border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 * barWindow.pillBorderAlpha : 0.05 * barWindow.pillBorderAlpha)
    Behavior on color { ColorAnimation { duration: 250 } }
    scale: isHovered ? 1.03 : 1.0
    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

    property bool showLayout: false
    Timer { running: barWindow.isStartupReady; interval: 150; onTriggered: timedate.showLayout = true }
    opacity: showLayout ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    transform: Translate {
        y: timedate.showLayout ? 0 : barWindow.s(-30)
        Behavior on y { NumberAnimation { duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
    }

    MouseArea { id: clockMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { Sounds.playSfx("system/quick_click.wav"); CalendarState.toggle(); } }

    Text { id: timeMeasure; visible: false; text: barWindow.timeStr; font.family: Fonts.ui; font.pixelSize: barWindow.s(16); font.weight: Font.Black }
    Text { id: dateMeasure; visible: false; text: barWindow.fullDateStr; font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold }

    // Re-read once a minute via minuteStr, which is enough for the date.
    readonly property string dayStr: { barWindow.minuteStr; return Qt.formatDateTime(new Date(), "dd"); }
    readonly property string monthStr: { barWindow.minuteStr; return Qt.formatDateTime(new Date(), "MMM").toUpperCase(); }

    // v2's side clock: hour, minute, a short rule, then day and month.
    Column {
        id: vClock
        visible: timedate.vertical && timedate.isClassic
        anchors.centerIn: parent
        spacing: barWindow.s(1)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: barWindow.hourStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(14); font.weight: Font.Black
            color: mocha.blue
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: barWindow.minuteStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(14); font.weight: Font.Black
            color: mocha.sapphire
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: barWindow.s(16)
            height: barWindow.s(12)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: 2; radius: 1; color: mocha.surface2 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: timedate.dayStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(12); font.weight: Font.Bold
            color: mocha.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: timedate.monthStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(10); font.weight: Font.Bold
            color: mocha.subtext0
        }
    }

    ColumnLayout {
        visible: !timedate.vertical && timedate.isClassic
        anchors.centerIn: parent
        spacing: -2
        Text { text: barWindow.timeStr; Layout.alignment: Qt.AlignLeft; Layout.preferredWidth: timedate.textColWidth; font.family: Fonts.ui; font.pixelSize: barWindow.s(16); font.weight: Font.Black; color: mocha.blue }
        Text { text: barWindow.dateStr; Layout.alignment: Qt.AlignLeft; Layout.preferredWidth: timedate.textColWidth; font.family: Fonts.ui; font.pixelSize: barWindow.s(11); font.weight: Font.Bold; color: mocha.subtext0 }
    }

    // --- material: the minute drops below the hour, so the pair reads on a diagonal ---
    component MaterialClock : Item {
        implicitWidth: timedate.timeParts.hasSeconds ? (matHour.width + barWindow.s(4) + matStack.width)
                     : (timedate.timeParts.hasMinutes ? (matMinute.x + matMinute.width + (matAmPm.visible ? matAmPm.width + barWindow.s(2) : 0))
                                                      : (matHour.width + (matAmPm.visible ? matAmPm.width + barWindow.s(2) : 0)))
        implicitHeight: timedate.timeParts.hasSeconds ? Math.max(matHour.height, matStack.height)
                      : (timedate.timeParts.hasMinutes ? matMinute.y + matMinute.height : matHour.height)

        Text {
            id: matHour
            x: 0
            anchors.verticalCenter: timedate.timeParts.hasSeconds ? parent.verticalCenter : undefined
            text: timedate.timeParts.hours
            font.family: Fonts.ui
            font.pixelSize: barWindow.s(timedate.timeParts.hasSeconds ? 22 : 20)
            font.weight: Font.Black; font.bold: true; font.letterSpacing: -0.8
            color: mocha.mauve
        }
        Text {
            id: matMinute
            visible: !timedate.timeParts.hasSeconds && timedate.timeParts.hasMinutes
            x: matHour.width + barWindow.s(1)
            y: barWindow.s(7)
            text: timedate.timeParts.minutes
            font.family: Fonts.ui; font.pixelSize: barWindow.s(16)
            font.weight: Font.Black; font.bold: true; font.letterSpacing: -0.5
            color: mocha.text
        }
        Text {
            id: matAmPm
            visible: !timedate.timeParts.hasSeconds && timedate.timeParts.ampm !== ""
            x: timedate.timeParts.hasMinutes ? (matMinute.x + matMinute.width + barWindow.s(2)) : (matHour.width + barWindow.s(2))
            y: (timedate.timeParts.hasMinutes ? (matMinute.y + matMinute.height) : (matHour.y + matHour.height)) - height - barWindow.s(1)
            text: timedate.timeParts.ampm
            font.family: Fonts.ui; font.pixelSize: barWindow.s(9)
            font.weight: Font.Black; font.bold: true
            color: mocha.subtext0
        }
        Column {
            id: matStack
            visible: timedate.timeParts.hasSeconds
            x: matHour.width + barWindow.s(4)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Row {
                spacing: barWindow.s(2)
                Text {
                    text: timedate.timeParts.minutes
                    font.family: Fonts.ui; font.pixelSize: barWindow.s(12)
                    font.weight: Font.Black; font.bold: true; font.letterSpacing: -0.4
                    color: mocha.text
                }
                Text {
                    visible: timedate.timeParts.ampm !== ""
                    text: timedate.timeParts.ampm
                    font.family: Fonts.ui; font.pixelSize: barWindow.s(8)
                    font.weight: Font.Black; font.bold: true
                    color: mocha.subtext0
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: barWindow.s(1)
                }
            }
            Text {
                x: barWindow.s(2)
                text: timedate.timeParts.seconds
                font.family: Fonts.ui; font.pixelSize: barWindow.s(10)
                font.weight: Font.Black; font.bold: true; font.letterSpacing: -0.3
                color: mocha.teal
            }
        }
    }

    component MaterialDate : Row {
        spacing: barWindow.s(3)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: timedate.dayStr
            font.family: Fonts.ui; font.pixelSize: barWindow.s(15)
            font.weight: Font.Black; font.bold: true; font.letterSpacing: -0.5
            color: mocha.teal
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                text: timedate.weekdayStr
                font.family: Fonts.ui; font.pixelSize: barWindow.s(8)
                font.weight: Font.Black; font.bold: true; font.letterSpacing: 0.2
                color: mocha.subtext0
            }
            Text {
                text: timedate.monthStr
                font.family: Fonts.ui; font.pixelSize: barWindow.s(9)
                font.weight: Font.Black; font.bold: true; font.letterSpacing: -0.2
                color: mocha.text
            }
        }
    }

    component MatDivider : Rectangle {
        width: barWindow.s(2)
        height: barWindow.s(16)
        radius: width / 2
        color: Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.7)
    }

    Row {
        id: matRow
        visible: !timedate.vertical && timedate.style === "material"
        anchors.centerIn: parent
        spacing: barWindow.s(8)
        MaterialClock { anchors.verticalCenter: parent.verticalCenter }
        MatDivider { anchors.verticalCenter: parent.verticalCenter }
        MaterialDate { anchors.verticalCenter: parent.verticalCenter }
    }
    Column {
        id: matCol
        visible: timedate.vertical && timedate.style === "material"
        anchors.centerIn: parent
        spacing: barWindow.s(6)
        MaterialClock { anchors.horizontalCenter: parent.horizontalCenter }
        MatDivider {
            anchors.horizontalCenter: parent.horizontalCenter
            width: barWindow.s(16); height: barWindow.s(2)
        }
        MaterialDate { anchors.horizontalCenter: parent.horizontalCenter }
    }

    // --- badge: a 3x5 dot-matrix font, lit dots on a dim grid ---
    readonly property real dotSize: barWindow.s(2.2)
    readonly property real dotSpacing: barWindow.s(1.1)
    readonly property var matrixFont: ({
        "0": [1,1,1, 1,0,1, 1,0,1, 1,0,1, 1,1,1], "1": [0,1,0, 1,1,0, 0,1,0, 0,1,0, 1,1,1],
        "2": [1,1,1, 0,0,1, 1,1,1, 1,0,0, 1,1,1], "3": [1,1,1, 0,0,1, 1,1,1, 0,0,1, 1,1,1],
        "4": [1,0,1, 1,0,1, 1,1,1, 0,0,1, 0,0,1], "5": [1,1,1, 1,0,0, 1,1,1, 0,0,1, 1,1,1],
        "6": [1,1,1, 1,0,0, 1,1,1, 1,0,1, 1,1,1], "7": [1,1,1, 0,0,1, 0,0,1, 0,0,1, 0,0,1],
        "8": [1,1,1, 1,0,1, 1,1,1, 1,0,1, 1,1,1], "9": [1,1,1, 1,0,1, 1,1,1, 0,0,1, 1,1,1],
        ":": [0,0,0, 0,1,0, 0,0,0, 0,1,0, 0,0,0], ".": [0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,1,0],
        "-": [0,0,0, 0,0,0, 1,1,1, 0,0,0, 0,0,0], "/": [0,0,1, 0,0,1, 0,1,0, 1,0,0, 1,0,0],
        ",": [0,0,0, 0,0,0, 0,0,0, 0,1,0, 1,0,0], " ": [0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0],
        "A": [0,1,0, 1,0,1, 1,1,1, 1,0,1, 1,0,1], "B": [1,1,0, 1,0,1, 1,1,0, 1,0,1, 1,1,0],
        "C": [0,1,1, 1,0,0, 1,0,0, 1,0,0, 0,1,1], "D": [1,1,0, 1,0,1, 1,0,1, 1,0,1, 1,1,0],
        "E": [1,1,1, 1,0,0, 1,1,0, 1,0,0, 1,1,1], "F": [1,1,1, 1,0,0, 1,1,0, 1,0,0, 1,0,0],
        "G": [0,1,1, 1,0,0, 1,0,1, 1,0,1, 0,1,1], "H": [1,0,1, 1,0,1, 1,1,1, 1,0,1, 1,0,1],
        "I": [1,1,1, 0,1,0, 0,1,0, 0,1,0, 1,1,1], "J": [0,0,1, 0,0,1, 0,0,1, 1,0,1, 0,1,0],
        "K": [1,0,1, 1,1,0, 1,0,0, 1,1,0, 1,0,1], "L": [1,0,0, 1,0,0, 1,0,0, 1,0,0, 1,1,1],
        "M": [1,0,1, 1,1,1, 1,0,1, 1,0,1, 1,0,1], "N": [1,1,0, 1,0,1, 1,0,1, 1,0,1, 1,0,1],
        "O": [0,1,0, 1,0,1, 1,0,1, 1,0,1, 0,1,0], "P": [1,1,0, 1,0,1, 1,1,0, 1,0,0, 1,0,0],
        "Q": [0,1,0, 1,0,1, 1,0,1, 0,1,1, 0,0,1], "R": [1,1,0, 1,0,1, 1,1,0, 1,0,1, 1,0,1],
        "S": [0,1,1, 1,0,0, 0,1,0, 0,0,1, 1,1,0], "T": [1,1,1, 0,1,0, 0,1,0, 0,1,0, 0,1,0],
        "U": [1,0,1, 1,0,1, 1,0,1, 1,0,1, 0,1,0], "V": [1,0,1, 1,0,1, 1,0,1, 1,0,1, 0,1,0],
        "W": [1,0,1, 1,0,1, 1,0,1, 1,1,1, 1,0,1], "X": [1,0,1, 1,0,1, 0,1,0, 1,0,1, 1,0,1],
        "Y": [1,0,1, 1,0,1, 0,1,0, 0,1,0, 0,1,0], "Z": [1,1,1, 0,0,1, 0,1,0, 1,0,0, 1,1,1]
    })
    function glyphPattern(ch) {
        const f = timedate.matrixFont;
        return f[ch] || f[("" + ch).toUpperCase()] || f[" "];
    }

    component MatrixChar : Grid {
        property string character: " "
        property color activeColor: mocha.text
        columns: 3
        rows: 5
        spacing: timedate.dotSpacing
        Repeater {
            model: 15
            Rectangle {
                required property int index
                width: timedate.dotSize
                height: timedate.dotSize
                radius: timedate.dotSize / 2
                readonly property bool isLit: timedate.glyphPattern(parent.character)[index] === 1
                color: isLit ? parent.activeColor : Qt.rgba(parent.activeColor.r, parent.activeColor.g, parent.activeColor.b, 0.1)
            }
        }
    }

    component MatrixWord : Row {
        property string word: ""
        property bool isTime: false
        spacing: barWindow.s(2.5)
        Repeater {
            model: parent.word.length
            MatrixChar {
                required property int index
                character: parent.word.charAt(index)
                activeColor: {
                    if (parent.isTime) {
                        const colon = parent.word.indexOf(":");
                        if (character === ":") return mocha.subtext0;
                        return (colon === -1 || index < colon) ? mocha.blue : mocha.text;
                    }
                    if (character >= "0" && character <= "9") return mocha.peach;
                    if (character === "." || character === "-" || character === "/" || character === ",") return mocha.surface2;
                    return mocha.subtext0;
                }
            }
        }
    }

    component MatrixDivider : Grid {
        columns: 1
        rows: 5
        spacing: timedate.dotSpacing
        Repeater {
            model: 5
            Rectangle {
                required property int index
                width: timedate.dotSize
                height: timedate.dotSize
                radius: timedate.dotSize / 2
                color: (index === 1 || index === 3) ? Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.8)
                                                    : Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.15)
            }
        }
    }

    Row {
        id: badgeRow
        visible: !timedate.vertical && timedate.style === "badge"
        anchors.centerIn: parent
        spacing: barWindow.s(8.5)
        MatrixWord { anchors.verticalCenter: parent.verticalCenter; word: barWindow.timeStr; isTime: true }
        MatrixDivider { anchors.verticalCenter: parent.verticalCenter }
        MatrixWord { anchors.verticalCenter: parent.verticalCenter; word: timedate.matrixDate }
    }
    Column {
        id: badgeCol
        visible: timedate.vertical && timedate.style === "badge"
        anchors.centerIn: parent
        spacing: barWindow.s(4.5)
        // Vertical splits the clock on its colons so each pair stacks.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: barWindow.s(2)
            Repeater {
                model: ("" + barWindow.timeStr).trim().split(":")
                MatrixWord { required property string modelData; word: modelData; isTime: true }
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: timedate.dotSpacing
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: timedate.dotSize; height: timedate.dotSize; radius: timedate.dotSize / 2
                    color: index === 1 ? Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.8)
                                       : Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.15)
                }
            }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: barWindow.s(2)
            MatrixWord { anchors.horizontalCenter: parent.horizontalCenter; word: timedate.dayStr }
            MatrixWord { anchors.horizontalCenter: parent.horizontalCenter; word: timedate.monthStr }
        }
    }

}
