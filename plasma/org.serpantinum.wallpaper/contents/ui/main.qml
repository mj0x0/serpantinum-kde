import QtQuick
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    loading: stage.item ? stage.item.loading : true

    onOpenUrlRequested: url => {
        root.configuration.Image = url;
        root.configuration.writeConfig();
    }

    // The stamp defeats plasmashell's per-session QML cache; this Loader is the permanent child the effects widget hooks.
    Loader {
        id: stage
        anchors.fill: parent
        Component.onCompleted: setSource(Qt.resolvedUrl("Stage.qml?" + Date.now()), {
            wallpaper: root
        })
    }
}
