import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "transitions.js" as Transitions

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout

    property string cfg_Image
    property string cfg_ImageDefault
    property int cfg_FillMode
    property int cfg_FillModeDefault
    property string cfg_Transition
    property string cfg_TransitionDefault
    property int cfg_Duration
    property int cfg_DurationDefault

    onCfg_FillModeChanged: fillModeComboBox.setMethod()
    onCfg_TransitionChanged: transitionComboBox.setMethod()

    RowLayout {
        Kirigami.FormData.label: i18n("Image:")
        spacing: Kirigami.Units.smallSpacing

        QQC2.TextField {
            Layout.fillWidth: true
            text: root.cfg_Image
            onEditingFinished: root.cfg_Image = text
        }

        QQC2.Button {
            text: i18n("Browse…")
            icon.name: "document-open"
            onClicked: fileDialog.open()
        }
    }

    QQC2.ComboBox {
        id: fillModeComboBox
        Kirigami.FormData.label: i18n("Positioning:")
        model: [
            { label: i18n("Scaled and cropped"), fillMode: Image.PreserveAspectCrop },
            { label: i18n("Scaled"), fillMode: Image.Stretch },
            { label: i18n("Scaled, keep proportions"), fillMode: Image.PreserveAspectFit },
            { label: i18n("Centered"), fillMode: Image.Pad }
        ]
        textRole: "label"
        onActivated: root.cfg_FillMode = model[currentIndex]["fillMode"]
        Component.onCompleted: setMethod()

        KCM.SettingHighlighter {
            highlight: root.cfg_FillModeDefault != root.cfg_FillMode
        }

        function setMethod() {
            for (let i = 0; i < model.length; i++) {
                if (model[i]["fillMode"] === root.cfg_FillMode) {
                    currentIndex = i;
                    break;
                }
            }
        }
    }

    QQC2.ComboBox {
        id: transitionComboBox
        Kirigami.FormData.label: i18n("Transition:")
        model: [{ label: i18n("Random"), value: "random" }].concat(Transitions.names.map(name => ({ label: name, value: name })))
        textRole: "label"
        onActivated: root.cfg_Transition = model[currentIndex]["value"]
        Component.onCompleted: setMethod()

        KCM.SettingHighlighter {
            highlight: root.cfg_TransitionDefault != root.cfg_Transition
        }

        function setMethod() {
            for (let i = 0; i < model.length; i++) {
                if (model[i]["value"] === root.cfg_Transition) {
                    currentIndex = i;
                    break;
                }
            }
        }
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: i18n("Duration:")
        from: 0
        to: 10000
        stepSize: 100
        value: root.cfg_Duration
        onValueModified: root.cfg_Duration = value
        textFromValue: (value, locale) => i18n("%1 ms", value)
        valueFromText: (text, locale) => parseInt(text, 10) || 0

        KCM.SettingHighlighter {
            highlight: root.cfg_DurationDefault != root.cfg_Duration
        }
    }

    FileDialog {
        id: fileDialog
        title: i18n("Open Image")
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/Wallpapers"
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.svg)")]
        fileMode: FileDialog.OpenFile
        options: FileDialog.ReadOnly
        onAccepted: root.cfg_Image = selectedFile.toString()
    }
}
