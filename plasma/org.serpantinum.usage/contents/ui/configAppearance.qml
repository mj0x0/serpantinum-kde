import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "faces.js" as Faces

KCM.SimpleKCM {
    id: page

    property string cfg_face
    property alias cfg_animate: animate.checked
    property alias cfg_tempSensor: tempSensor.text

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: faceBox
            Kirigami.FormData.label: i18n("Face:")
            model: Faces.faces
            textRole: "name"
            valueRole: "id"
            onActivated: page.cfg_face = currentValue
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(page.cfg_face))
        }

        QQC2.Label {
            readonly property string note: Faces.faces[faceBox.currentIndex]?.note ?? ""
            visible: note !== ""
            text: note
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        QQC2.CheckBox {
            id: animate
            Kirigami.FormData.label: i18n("Animation:")
            text: i18n("Animate the wave and value changes")
        }

        QQC2.Label {
            visible: animate.checked
            text: i18n("Renders continuously; on NVIDIA that leaks memory unless explicit sync is disabled.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        QQC2.TextField {
            id: tempSensor
            Kirigami.FormData.label: i18n("Temperature sensor:")
            visible: faceBox.currentValue === "temp"
        }

        QQC2.Label {
            visible: tempSensor.visible
            text: i18n("A ksystemstats sensor id, as System Monitor lists them.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
