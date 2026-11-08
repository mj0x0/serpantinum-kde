pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "faces.js" as Faces

PlasmoidItem {
    id: root

    readonly property real defaultWidth: Kirigami.Units.gridUnit * 14
    readonly property real defaultHeight: Kirigami.Units.gridUnit * 7
    readonly property DateTime dateTime: DateTime {
        use24hFormat: Plasmoid.configuration.use24hFormat
        showSeconds: Plasmoid.configuration.showSeconds
    }

    // A new desktop applet opens at the root item's size.
    width: defaultWidth
    height: defaultHeight

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground
    toolTipMainText: dateTime.fullDate
    toolTipSubText: dateTime.timeShort

    Theme { id: theme }

    fullRepresentation: Loader {
        id: face

        Layout.minimumWidth: item?.minWidth ?? Kirigami.Units.gridUnit * 5
        Layout.minimumHeight: item?.minHeight ?? Kirigami.Units.gridUnit * 2.5
        Layout.preferredWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height * 2.6 : root.defaultWidth
        Layout.preferredHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width : root.defaultHeight

        function load() {
            setSource(Qt.resolvedUrl(Faces.file(Plasmoid.configuration.face)), {
                dateTime: root.dateTime,
                theme: theme,
                smoothHands: Plasmoid.configuration.smoothHands
            });
        }

        Component.onCompleted: load()

        Connections {
            target: Plasmoid.configuration
            function onFaceChanged() {
                face.load();
            }
            function onSmoothHandsChanged() {
                face.load();
            }
        }
    }
}
