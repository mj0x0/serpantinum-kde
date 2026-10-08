// Theme picker for Settings -> Appearance: serpantinum v2's guide/theme/ThemeTab.qml grid on
// ShellSettings. A tile per palette in its own base colour with plain circle swatches, search,
// and a Matugen tile under the current wallpaper. Order comes from helpers/theme-sort.py.
import "../../services/layout"
import "../../services/reusables" as V2
import "../../services/settings"
import "../../services/theme"
import "../../services/wallpaper"
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property var host      // the Settings window: s(), palette, fonts
    implicitHeight: col.implicitHeight

    readonly property string current: "" + ShellSettings.value("appearance.theme", "matugen")
    property var themes: []
    property string query: ""
    readonly property real gap: root.host.s(8)
    readonly property real tileH: root.host.s(40)
    readonly property real tileR: Radius.inner(root.host.s(10), root.host.s(16))

    // The sorter's list minus non-matches; dividers collapse to one between kept groups.
    readonly property var shown: {
        var q = root.query.trim().toLowerCase(), out = [], pending = false;
        for (var i = 0; i < root.themes.length; i++) {
            var t = root.themes[i];
            if (t.isDivider) { pending = out.length > 0; continue; }
            if (q !== "" && ("" + t.name).toLowerCase().indexOf(q) < 0) continue;
            if (pending) { out.push({ isDivider: true }); pending = false; }
            out.push(t);
        }
        return out;
    }
    readonly property int themeCount: root.themes.filter(t => !t.isDivider).length

    MatugenColors { id: live }

    // matugen's own colours outlive a static theme through the hook's colors-matugen.json copy.
    property var savedMd3: null
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/colors-matugen.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.savedMd3 = JSON.parse(text()).md3 || null; } catch (e) { root.savedMd3 = null; }
        }
    }
    readonly property var matugenTile: {
        var m = Colors.isStatic ? root.savedMd3 : null;
        return m ? { base: m.surface, text: m.on_surface,
                     dots: [m.on_surface, m.primary, m.primary, m.tertiary, m.secondary, m.error] }
                 : { base: live.base, text: live.text,
                     dots: [live.text, live.blue, live.mauve, live.peach, live.green, live.red] };
    }

    function tileBase(t) { return t.isMatugen ? root.matugenTile.base : t.colors.base; }
    function tileText(t) { return t.isMatugen ? root.matugenTile.text : t.colors.text; }
    function tileDots(t) {
        if (t.isMatugen) return root.matugenTile.dots;
        var c = t.colors;
        return [c.text, c.blue, c.mauve, c.peach, c.green, c.red];
    }
    function pick(t) {
        if (t.id !== root.current) ShellSettings.setValue("appearance.theme", t.id);
    }

    Process {
        running: true
        command: ["python3", ("" + Quickshell.shellDir).replace(/^file:\/\//, "") + "/helpers/theme-sort.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.themes = JSON.parse(this.text); } catch (e) { root.themes = []; }
            }
        }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: root.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: root.host.s(12)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: "Theme"
                    font.family: root.host.fontFamily
                    font.pixelSize: root.host.s(12)
                    color: root.host.text
                }
                Text {
                    Layout.fillWidth: true
                    text: "Matugen follows the wallpaper; a palette themes the shell and every app alike"
                    font.family: root.host.fontFamily
                    font.pixelSize: root.host.s(9)
                    color: root.host.overlay0
                    wrapMode: Text.Wrap
                }
            }

            V2.Input {
                Layout.preferredWidth: root.host.s(200)
                Layout.preferredHeight: root.host.s(32)
                placeholderText: "Search " + root.themeCount + " themes"
                baseColor: root.host.surface0
                accentColor: root.host.accent
                textColor: root.host.text
                subTextColor: root.host.subtext0
                borderColor: Qt.alpha(root.host.surface2, 0.6)
                cornerRadius: Radius.outer(root.host.s(8))
                fontPixelSize: root.host.s(11)
                onTextEdited: t => root.query = t
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(grid.implicitHeight, root.host.s(300))
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            GridLayout {
                id: grid
                width: flick.width
                columns: 3
                rowSpacing: root.gap
                columnSpacing: root.gap

                Repeater {
                    model: root.shown
                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property bool divider: modelData.isDivider === true
                        readonly property bool selected: !divider && modelData.id === root.current
                        readonly property color baseC: divider ? "transparent" : root.tileBase(modelData)
                        readonly property color textC: divider ? "transparent" : root.tileText(modelData)

                        Layout.columnSpan: divider ? 3 : 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: divider ? root.host.s(9) : root.tileH

                        Rectangle {
                            visible: cell.divider
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 1
                            color: root.host.surface2
                        }

                        Rectangle {
                            id: tile
                            visible: !cell.divider
                            anchors.fill: parent
                            radius: root.tileR
                            color: cell.baseC
                            scale: ma.pressed ? 0.97 : (ma.containsMouse ? 1.03 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }

                            // The Matugen tile carries the wallpaper, blurred and faded into its base colour.
                            Loader {
                                anchors.fill: parent
                                active: !cell.divider && cell.modelData.isMatugen === true && WallpaperService.still !== ""
                                sourceComponent: Item {
                                    Rectangle {
                                        id: mask
                                        anchors.fill: parent
                                        radius: tile.radius
                                        visible: false
                                        layer.enabled: true
                                    }
                                    Item {
                                        id: art
                                        anchors.fill: parent
                                        visible: false
                                        layer.enabled: true
                                        Image {
                                            id: wall
                                            anchors.fill: parent
                                            source: "file://" + WallpaperService.still
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            sourceSize.width: 320
                                            visible: false
                                        }
                                        MultiEffect {
                                            anchors.fill: parent
                                            source: wall
                                            blurEnabled: true
                                            blurMax: 32
                                            blur: 0.5
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: Qt.alpha(cell.baseC, 0.35) }
                                                GradientStop { position: 1.0; color: Qt.alpha(cell.baseC, 0.85) }
                                            }
                                        }
                                    }
                                    MultiEffect {
                                        anchors.fill: parent
                                        source: art
                                        maskEnabled: true
                                        maskSource: mask
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: tile.radius
                                color: cell.textC
                                opacity: cell.selected ? 0.15 : (ma.containsMouse ? 0.08 : 0.0)
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: tile.radius
                                color: "transparent"
                                border.color: cell.selected ? cell.textC : "transparent"
                                border.width: 2
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: root.host.s(10)
                                anchors.rightMargin: root.host.s(10)
                                spacing: root.host.s(6)
                                Text {
                                    Layout.fillWidth: true
                                    text: cell.divider ? "" : cell.modelData.name
                                    font.family: root.host.fontFamily
                                    font.pixelSize: root.host.s(11)
                                    font.weight: cell.selected ? Font.Bold : Font.Medium
                                    color: cell.textC
                                    elide: Text.ElideRight
                                }
                                Row {
                                    spacing: root.host.s(4)
                                    Repeater {
                                        model: cell.divider ? [] : root.tileDots(cell.modelData)
                                        Rectangle {
                                            required property var modelData
                                            width: root.host.s(8)
                                            height: width
                                            radius: width / 2
                                            color: modelData
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pick(cell.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
