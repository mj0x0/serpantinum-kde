import "../../../services/layout"
import "../../../services/theme"
import "../../../services/settings"
import "../../../services/wallpaper"
import QtQuick
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell

// The candidate at full size: grows out of the selected card, arrives through a plugin transition shader.
Item {
    id: root

    property var picker
    property bool open: false
    signal closed
    signal dismissed

    // A key change is a new candidate (transition); a url change under the same key upgrades in place.
    property string candidateKey: ""
    property string candidateUrl: ""
    // A sharper version of the same candidate, swapped in silently once it has decoded.
    property string candidateHiUrl: ""
    property string candidateName: ""
    property bool candidateIsVideo: false
    property string candidateVideoUrl: ""
    property var candidatePalette: []
    property string candidateStatus: ""
    property var originFn: null

    readonly property string shaderDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/plasma/wallpapers/org.serpantinum.wallpaper/contents/shaders"
    property string shaderUrl: ""
    readonly property bool useShader: root.shaderUrl !== ""
    readonly property real radius: Radius.outer(root.picker.s(16))
    readonly property rect stage: Qt.rect(root.picker.s(72), root.picker.contentTop, root.picker.width - 2 * root.picker.s(72), root.picker.height - root.picker.contentTop - root.picker.s(24))
    // The frame takes the candidate's own aspect inside the stage; 16:9 until the thumb says otherwise.
    property real aspect: 16 / 9
    readonly property rect target: {
        const a = root.stage;
        let w = a.width;
        let h = w / root.aspect;
        if (h > a.height) {
            h = a.height;
            w = h * root.aspect;
        }
        return Qt.rect(a.x + (a.width - w) / 2, a.y + (a.height - h) / 2, w, h);
    }
    readonly property string shaderName: root.shaderUrl === "" ? "" : root.shaderUrl.substring(root.shaderUrl.lastIndexOf("/") + 1).replace(".frag.qsb", "")

    property string lastKey: ""
    property string nextUrl: ""
    property string fromUrl: ""
    property string shownUrl: ""
    property bool completed: false
    property bool settled: false
    property bool pending: false
    property bool landed: false
    property real crossfade: 0

    function origin() {
        const r = root.originFn ? root.originFn() : null;
        return r ? r : root.target;
    }

    function syncAspect() {
        if (imgTo.status === Image.Ready && imgTo.implicitHeight > 0)
            root.aspect = imgTo.implicitWidth / imgTo.implicitHeight;
    }

    onTargetChanged: {
        if (!root.open || !root.completed)
            return;
        if (openAnim.running)
            openAnim.restart();
        else if (root.settled)
            retarget.restart();
    }

    function pickShader() {
        if (shaders.count <= 0)
            return "";
        return "file://" + root.shaderDir + "/" + shaders.get(Math.floor(Math.random() * shaders.count), "fileName");
    }

    function beginOpen() {
        closeAnim.stop();
        const o = root.origin();
        frame.x = o.x;
        frame.y = o.y;
        frame.width = o.width;
        frame.height = o.height;
        frame.opacity = 1;
        root.settled = false;
        root.lastKey = root.candidateKey;
        root.nextUrl = "";
        root.fromUrl = WallpaperService.still !== "" ? "file://" + WallpaperService.still : root.candidateUrl;
        root.shownUrl = root.candidateUrl;
        root.nextUrl = root.candidateHiUrl;
        root.reset();
        root.syncAspect();
        openAnim.restart();
    }

    function beginClose() {
        openAnim.stop();
        kick.stop();
        root.pending = false;
        root.settled = false;
        const o = root.origin();
        closeX.to = o.x;
        closeY.to = o.y;
        closeW.to = o.width;
        closeH.to = o.height;
        closeAnim.restart();
    }

    function reset() {
        play.stop();
        fade.stop();
        fx.progress = 0;
        root.crossfade = 0;
        root.landed = false;
    }

    function tryStart() {
        if (!root.open || !root.settled)
            return;
        if (imgTo.status === Image.Loading || root.shownUrl === "") {
            root.pending = true;
            return;
        }
        root.pending = false;
        root.startTransition();
    }

    function startTransition() {
        root.reset();
        root.shaderUrl = root.pickShader();
        if (root.useShader) {
            fx.seed = Math.random();
            play.restart();
        } else {
            fade.restart();
        }
    }

    // Key and url arrive as separate bindings in no fixed order, so decide once both have settled.
    onCandidateKeyChanged: Qt.callLater(root.sync)
    onCandidateUrlChanged: Qt.callLater(root.sync)
    onCandidateHiUrlChanged: Qt.callLater(root.sync)

    function sync() {
        if (root.candidateKey !== root.lastKey) {
            root.lastKey = root.candidateKey;
            root.nextUrl = "";
            if (!root.open || !root.completed)
                return;
            root.fromUrl = root.shownUrl;
            root.shownUrl = root.candidateUrl;
            root.reset();
            root.pending = false;
            kick.restart();
            root.nextUrl = root.candidateHiUrl;
        } else if (root.open && root.completed) {
            const want = root.candidateHiUrl !== "" ? root.candidateHiUrl : root.candidateUrl;
            if (want !== root.shownUrl)
                root.nextUrl = want;
        }
    }

    onOpenChanged: {
        if (!root.completed)
            return;
        if (root.open)
            root.beginOpen();
        else
            root.beginClose();
    }

    Component.onCompleted: {
        root.completed = true;
        if (root.open)
            root.beginOpen();
    }

    FolderListModel {
        id: shaders
        folder: "file://" + root.shaderDir
        nameFilters: ["*.frag.qsb"]
        showDirs: false
    }

    Timer {
        id: kick
        interval: 60
        onTriggered: root.tryStart()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismissed()
    }

    // Warms the cache for an in-place upgrade so imgTo swaps without a reload.
    Image {
        id: imgNext
        visible: false
        source: root.nextUrl
        sourceSize: Qt.size(Math.round(root.stage.width), Math.round(root.stage.height))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        onStatusChanged: {
            if (imgNext.status === Image.Ready && root.nextUrl !== "" && (root.nextUrl === root.candidateHiUrl || root.nextUrl === root.candidateUrl))
                root.shownUrl = root.nextUrl;
        }
    }

    Item {
        id: frame

        ParallelAnimation {
            id: openAnim
            NumberAnimation {
                target: frame
                property: "x"
                to: root.target.x
                duration: 320
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: frame
                property: "y"
                to: root.target.y
                duration: 320
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: frame
                property: "width"
                to: root.target.width
                duration: 320
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: frame
                property: "height"
                to: root.target.height
                duration: 320
                easing.type: Easing.OutCubic
            }
            onFinished: {
                root.settled = true;
                if (!kick.running)
                    root.tryStart();
            }
        }

        ParallelAnimation {
            id: retarget
            NumberAnimation {
                target: frame
                property: "x"
                to: root.target.x
                duration: 260
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: frame
                property: "y"
                to: root.target.y
                duration: 260
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: frame
                property: "width"
                to: root.target.width
                duration: 260
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: frame
                property: "height"
                to: root.target.height
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        ParallelAnimation {
            id: closeAnim
            NumberAnimation {
                id: closeX
                target: frame
                property: "x"
                duration: 240
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                id: closeY
                target: frame
                property: "y"
                duration: 240
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                id: closeW
                target: frame
                property: "width"
                duration: 240
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                id: closeH
                target: frame
                property: "height"
                duration: 240
                easing.type: Easing.InCubic
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 140
                }
                NumberAnimation {
                    target: frame
                    property: "opacity"
                    to: 0
                    duration: 100
                }
            }
            onFinished: root.closed()
        }

        // Eats clicks so the backdrop does not dismiss; wheel is left alone and falls through.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Rectangle {
            id: mask
            anchors.fill: content
            radius: root.radius
            color: root.picker.theme.crust
            layer.enabled: true
        }

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: root.picker.theme.crust
            border.width: 1
            border.color: root.picker.theme.surface1
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: root.picker.s(6)
            layer.enabled: root.radius > 0
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Image {
                id: imgFrom
                anchors.fill: parent
                source: root.fromUrl
                sourceSize: Qt.size(Math.round(root.stage.width), Math.round(root.stage.height))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: !(root.useShader && root.landed)
            }

            Image {
                id: imgTo
                anchors.fill: parent
                source: root.shownUrl
                sourceSize: Qt.size(Math.round(root.stage.width), Math.round(root.stage.height))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                opacity: root.useShader ? 1 : root.crossfade
                onStatusChanged: {
                    root.syncAspect();
                    if (root.pending && imgTo.status !== Image.Loading)
                        root.tryStart();
                }
            }

            ShaderEffectSource {
                id: sFrom
                sourceItem: root.useShader && !root.landed ? imgFrom : null
                hideSource: true
            }

            ShaderEffectSource {
                id: sTo
                sourceItem: root.useShader && !root.landed ? imgTo : null
                hideSource: true
            }

            ShaderEffect {
                id: fx
                anchors.fill: parent
                visible: root.useShader && !root.landed
                property variant from: sFrom
                property variant to: sTo
                property real progress: 0
                property real ratio: width / Math.max(1, height)
                property real seed: 0
                property vector2d size: Qt.vector2d(width, height)
                fragmentShader: root.shaderUrl
            }

            NumberAnimation {
                id: play
                target: fx
                property: "progress"
                from: 0
                to: 1
                duration: 900
                easing.type: Easing.Linear
                onFinished: root.landed = true
            }

            NumberAnimation {
                id: fade
                target: root
                property: "crossfade"
                from: 0
                to: 1
                duration: 600
                onFinished: root.landed = true
            }

            Loader {
                id: video
                anchors.fill: parent
                active: root.candidateIsVideo && root.landed && root.open
                sourceComponent: Item {
                    MediaPlayer {
                        source: root.candidateVideoUrl
                        loops: MediaPlayer.Infinite
                        audioOutput: AudioOutput {
                            muted: true
                        }
                        videoOutput: out
                        Component.onCompleted: play()
                    }

                    VideoOutput {
                        id: out
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                }
            }
        }

        Rectangle {
            anchors.left: content.left
            anchors.bottom: content.bottom
            anchors.margins: root.picker.s(12)
            width: captionRow.implicitWidth + root.picker.s(16)
            height: Math.max(caption.implicitHeight, root.picker.s(12)) + root.picker.s(8)
            radius: Radius.outer(root.picker.s(6))
            color: Qt.rgba(root.picker.theme.base.r, root.picker.theme.base.g, root.picker.theme.base.b, 0.7)
            visible: captionRow.hasContent
            opacity: root.settled ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            Row {
                id: captionRow
                anchors.centerIn: parent
                spacing: root.picker.s(8)
                readonly property var palette: ShellSettings.previewColors ? (root.candidatePalette || []) : []
                readonly property bool hasContent: caption.text !== "" || captionRow.palette.length > 0

                Text {
                    id: caption
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: [ShellSettings.previewShader ? root.shaderName : "", ShellSettings.previewName ? root.candidateName : "", root.candidateStatus].filter(t => t !== "").join("  \u00b7  ")
                    color: Qt.rgba(root.picker.theme.text.r, root.picker.theme.text.g, root.picker.theme.text.b, 0.9)
                    font.family: Fonts.ui
                    font.pixelSize: root.picker.s(13)
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.picker.s(4)
                    visible: captionRow.palette.length > 0

                    Repeater {
                        model: captionRow.palette
                        delegate: Rectangle {
                            required property string modelData
                            width: root.picker.s(12)
                            height: width
                            radius: width / 2
                            color: modelData
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.25)
                        }
                    }
                }
            }
        }
    }
}
