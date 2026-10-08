// The shell's Calendar popup grid, shrunk into a wing card. Data is KDE's headless
// calendar with its holiday (and astronomy) plugins; nothing is drawn by Plasma.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.workspace.calendar as PlasmaCalendar

LockCard {
    id: box

    readonly property date today: box.lock.today
    property date selected: box.lock.today
    property var events: []
    property real contentOpacity: 1.0
    readonly property bool onCurrentMonth: cal.year === today.getFullYear() && cal.month === today.getMonth() + 1
    readonly property bool selectedInGrid: cal.year === selected.getFullYear() && cal.month === selected.getMonth() + 1

    readonly property int hour: box.lock.now.getHours()
    readonly property color timeAccent: hour >= 5 && hour < 12 ? box.lock.yellow
                                       : hour < 17 ? box.lock.teal
                                       : hour < 21 ? box.lock.pink : box.lock.mauve
    readonly property color textAccent: Qt.tint(timeAccent, Qt.alpha(box.lock.text, 0.35))
    readonly property var weekDayNames: {
        var base = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], out = [];
        for (var i = 0; i < 7; i++) out.push(base[(box.lock.weekStart + i) % 7]);
        return out;
    }

    PlasmaCalendar.EventPluginsManager {
        id: plugins
        // Only assigning the list loads plugins; populateEnabledPluginsList just records ids.
        enabledPlugins: box.lock.astro ? ["holidaysevents", "astronomicalevents"] : ["holidaysevents"]
    }

    PlasmaCalendar.Calendar {
        id: cal
        days: 7
        weeks: 6
        firstDayOfWeek: box.lock.weekStart === 0 ? 7 : box.lock.weekStart
        today: box.today
        Component.onCompleted: daysModel.setPluginsManager(plugins)
        onDisplayedDateChanged: monthFade.restart()
    }

    Connections { target: plugins; function onDataReady() { refresh.restart() } }
    Timer { id: refresh; interval: 60; onTriggered: box.refreshEvents() }
    onSelectedChanged: refresh.restart()
    onTodayChanged: box.selected = box.today

    function refreshEvents() {
        var list = cal.daysModel.eventsForDate(box.selected), out = [];
        for (var i = 0; i < list.length; i++) out.push(list[i].title);
        box.events = out;
    }

    SequentialAnimation {
        id: monthFade
        NumberAnimation { target: box; property: "contentOpacity"; to: 0.0; duration: 120; easing.type: Easing.InSine }
        NumberAnimation { target: box; property: "contentOpacity"; to: 1.0; duration: 260; easing.type: Easing.OutQuart }
    }

    component NavButton : Rectangle {
        property string glyph: ""
        property int glyphSize: box.lock.s(13)
        signal clicked()
        Layout.preferredWidth: box.lock.s(24)
        Layout.preferredHeight: box.lock.s(24)
        radius: box.lock.s(12)
        color: navMa.containsMouse ? box.lock.surface1 : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
        Text { anchors.centerIn: parent; text: parent.glyph; font.family: box.lock.iconFont; font.pixelSize: parent.glyphSize; color: box.lock.text }
        MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: box.lock.s(12)
        spacing: box.lock.s(8)

        RowLayout {
            Layout.fillWidth: true
            spacing: box.lock.s(2)
            NavButton {
                glyph: "󰃭"
                opacity: box.onCurrentMonth ? 0.0 : 1.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                onClicked: cal.resetToToday()
            }
            NavButton { glyph: ""; onClicked: cal.previousMonth() }
            Text {
                Layout.fillWidth: true
                text: (cal.monthName + " " + cal.year).toUpperCase()
                font.family: box.lock.uiFont
                font.weight: Font.Black
                font.pixelSize: box.lock.s(12)
                fontSizeMode: Text.Fit
                minimumPixelSize: 8
                color: box.lock.text
                horizontalAlignment: Text.AlignHCenter
                opacity: box.contentOpacity
            }
            NavButton { glyph: ""; onClicked: cal.nextMonth() }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: box.lock.s(4)
            Repeater {
                model: box.weekDayNames
                Text {
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    font.family: box.lock.uiFont
                    font.weight: Font.Black
                    font.pixelSize: box.lock.s(10)
                    color: box.lock.overlay0
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            opacity: box.contentOpacity

            // One highlight shaped like a cell; it slides between days of the shown month.
            Rectangle {
                id: daySelection
                property Item cell: null
                function track() {
                    var found = null;
                    if (box.selectedInGrid)
                        for (var i = 0; i < dayRepeater.count; i++) {
                            var it = dayRepeater.itemAt(i);
                            if (it && it.isSelected) { found = it; break; }
                        }
                    cell = found;
                }
                // Deferred: the cells' isSelected bindings settle after these signals, and the cells arrive after load.
                Connections { target: box; function onSelectedChanged() { Qt.callLater(daySelection.track) } }
                Connections { target: cal; function onDisplayedDateChanged() { Qt.callLater(daySelection.track) } }
                Connections { target: dayRepeater; function onItemAdded() { Qt.callLater(daySelection.track) } }
                Component.onCompleted: Qt.callLater(track)
                visible: cell !== null
                width: cell ? cell.width : 0
                height: cell ? cell.height : 0
                x: cell ? cell.x : 0
                y: cell ? cell.y : 0
                radius: box.lock.r(8)
                color: box.textAccent
                property bool slide: false
                onCellChanged: { if (!cell) slide = false; else if (!slide) settle.restart(); }
                Timer { id: settle; interval: 300; onTriggered: daySelection.slide = true }
                Behavior on x { enabled: daySelection.slide; NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
                Behavior on y { enabled: daySelection.slide; NumberAnimation { duration: 350; easing.type: Easing.OutBack } }
            }

            GridLayout {
                anchors.fill: parent
                columns: 7
                rowSpacing: box.lock.s(4)
                columnSpacing: box.lock.s(4)

                Repeater {
                    id: dayRepeater
                    model: cal.daysModel
                    Rectangle {
                        id: dayCell
                        required property var model
                        required property int index
                        readonly property bool inMonth: model.isCurrent === true
                        readonly property bool isToday: model.yearNumber === box.today.getFullYear()
                                                        && model.monthNumber === box.today.getMonth() + 1
                                                        && model.dayNumber === box.today.getDate()
                        readonly property bool isSelected: inMonth && model.yearNumber === box.selected.getFullYear()
                                                           && model.monthNumber === box.selected.getMonth() + 1
                                                           && model.dayNumber === box.selected.getDate()
                        readonly property bool hasEvents: model.containsEventItems === true

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: box.lock.r(8)
                        color: !isSelected && dayMa.containsMouse ? Qt.alpha(box.lock.surface2, 0.4) : "transparent"
                        border.width: !isSelected && dayMa.containsMouse ? 1 : 0
                        border.color: box.lock.overlay0
                        scale: dayMa.containsMouse ? 1.2 : 1.0
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                        Text {
                            anchors.centerIn: parent
                            text: dayCell.model.dayNumber
                            font.family: box.lock.uiFont
                            font.weight: (dayCell.isSelected || dayCell.isToday) ? Font.Black : Font.Bold
                            font.pixelSize: box.lock.s(11)
                            color: dayCell.isSelected ? box.lock.base
                                 : (dayCell.isToday ? box.textAccent : (dayCell.inMonth ? box.lock.text : box.lock.overlay0))
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Rectangle {
                            visible: dayCell.inMonth && dayCell.hasEvents
                            width: box.lock.s(3); height: box.lock.s(3); radius: box.lock.s(1.5)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: box.lock.s(2)
                            color: dayCell.isSelected ? box.lock.base : box.textAccent
                            opacity: 0.9
                        }
                        MouseArea {
                            id: dayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: dayCell.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (dayCell.inMonth)
                                box.selected = new Date(dayCell.model.yearNumber, dayCell.model.monthNumber - 1, dayCell.model.dayNumber, 12)
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: box.lock.s(14)
            spacing: box.lock.s(6)
            opacity: box.events.length > 0 ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            Rectangle { width: box.lock.s(6); height: box.lock.s(6); radius: box.lock.s(3); color: box.textAccent }
            Text {
                Layout.fillWidth: true
                text: box.events.join("  ·  ")
                font.family: box.lock.uiFont
                font.pixelSize: box.lock.s(10)
                color: box.lock.text
                elide: Text.ElideRight
            }
        }
    }
}
