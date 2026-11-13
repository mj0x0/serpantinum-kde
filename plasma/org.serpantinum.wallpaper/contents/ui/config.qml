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
    property real cfg_Brightness
    property real cfg_BrightnessDefault
    property real cfg_Contrast
    property real cfg_ContrastDefault
    property real cfg_Saturation
    property real cfg_SaturationDefault
    property int cfg_CornerRadius
    property int cfg_CornerRadiusDefault
    property string cfg_BackdropColor
    property string cfg_BackdropColorDefault

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

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Look")
    }

    component GradeSpinBox: QQC2.SpinBox {
        from: -100
        to: 100
        stepSize: 5
        textFromValue: (value, locale) => i18n("%1 %", (value > 0 ? "+" : "") + value)
        valueFromText: (text, locale) => parseInt(text, 10) || 0
    }

    GradeSpinBox {
        Kirigami.FormData.label: i18n("Brightness:")
        value: Math.round(root.cfg_Brightness * 100)
        onValueModified: root.cfg_Brightness = value / 100

        KCM.SettingHighlighter {
            highlight: Math.round(root.cfg_BrightnessDefault * 100) != Math.round(root.cfg_Brightness * 100)
        }
    }

    GradeSpinBox {
        Kirigami.FormData.label: i18n("Contrast:")
        value: Math.round(root.cfg_Contrast * 100)
        onValueModified: root.cfg_Contrast = value / 100

        KCM.SettingHighlighter {
            highlight: Math.round(root.cfg_ContrastDefault * 100) != Math.round(root.cfg_Contrast * 100)
        }
    }

    GradeSpinBox {
        Kirigami.FormData.label: i18n("Saturation:")
        value: Math.round(root.cfg_Saturation * 100)
        onValueModified: root.cfg_Saturation = value / 100

        KCM.SettingHighlighter {
            highlight: Math.round(root.cfg_SaturationDefault * 100) != Math.round(root.cfg_Saturation * 100)
        }
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: i18n("Corner radius:")
        from: 0
        to: 200
        stepSize: 2
        value: root.cfg_CornerRadius
        onValueModified: root.cfg_CornerRadius = value
        textFromValue: (value, locale) => i18n("%1 px", value)
        valueFromText: (text, locale) => parseInt(text, 10) || 0

        KCM.SettingHighlighter {
            highlight: root.cfg_CornerRadiusDefault != root.cfg_CornerRadius
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Outside corners:")
        spacing: Kirigami.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
            radius: Kirigami.Units.cornerRadius
            color: root.cfg_BackdropColor
            border.color: Kirigami.Theme.textColor
            border.width: 1
        }

        QQC2.TextField {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            text: root.cfg_BackdropColor
            validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
            onEditingFinished: if (acceptableInput) root.cfg_BackdropColor = text.toLowerCase()
        }

        QQC2.Button {
            text: i18n("Choose…")
            icon.name: "color-picker"
            onClicked: colorDialog.open()
        }

        KCM.SettingHighlighter {
            highlight: root.cfg_BackdropColorDefault != root.cfg_BackdropColor
        }
    }

    ColorDialog {
        id: colorDialog
        title: i18n("Outside corners")
        selectedColor: root.cfg_BackdropColor
        onAccepted: root.cfg_BackdropColor = selectedColor.toString().slice(0, 7)
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
