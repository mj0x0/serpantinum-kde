import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "faces.js" as Faces

KCM.SimpleKCM {
    id: page

    property string cfg_face
    property alias cfg_use24hFormat: hourFormat.currentIndex
    property alias cfg_showSeconds: showSeconds.checked
    property alias cfg_smoothHands: smoothHands.checked

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

        QQC2.ComboBox {
            id: hourFormat
            Kirigami.FormData.label: i18n("Time display:")
            model: [i18n("12-Hour"), i18n("Use region defaults"), i18n("24-Hour")]
        }

        QQC2.CheckBox {
            id: showSeconds
            Kirigami.FormData.label: i18n("Seconds:")
            text: i18n("Show seconds")
        }

        QQC2.CheckBox {
            id: smoothHands
            Kirigami.FormData.label: i18n("Analog:")
            text: i18n("Sweep the hands")
        }

        QQC2.Label {
            visible: smoothHands.checked
            text: i18n("Renders continuously; on NVIDIA that leaks memory unless explicit sync is disabled.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
