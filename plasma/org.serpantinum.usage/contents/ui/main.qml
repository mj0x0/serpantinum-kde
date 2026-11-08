pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "faces.js" as Faces

PlasmoidItem {
    id: root

    readonly property real defaultWidth: Kirigami.Units.gridUnit * 10
    readonly property real defaultHeight: Kirigami.Units.gridUnit * 7
    readonly property SysData sysData: SysData {
        metric: Faces.id(Plasmoid.configuration.face)
        tempSensor: Plasmoid.configuration.tempSensor
    }

    // A new desktop applet opens at the root item's size.
    width: defaultWidth
    height: defaultHeight

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground | PlasmaCore.Types.ConfigurableBackground

    Theme { id: theme }

    fullRepresentation: Loader {
        id: face

        Layout.minimumWidth: item?.minWidth ?? Kirigami.Units.gridUnit * 5
        Layout.minimumHeight: item?.minHeight ?? Kirigami.Units.gridUnit * 3.5
        Layout.preferredWidth: Plasmoid.formFactor === PlasmaCore.Types.Horizontal ? height * 1.4 : root.defaultWidth
        Layout.preferredHeight: Plasmoid.formFactor === PlasmaCore.Types.Vertical ? width / 1.4 : root.defaultHeight

        function load() {
            setSource(Qt.resolvedUrl(Faces.file(Plasmoid.configuration.face)), {
                sysData: root.sysData,
                theme: theme,
                animate: Plasmoid.configuration.animate
            });
        }

        Component.onCompleted: load()

        Connections {
            target: Plasmoid.configuration
            function onFaceChanged() {
                face.load();
            }
            function onAnimateChanged() {
                face.load();
            }
            function onTempSensorChanged() {
                face.load();
            }
        }
    }
}
