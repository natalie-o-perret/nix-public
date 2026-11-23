//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma Env QT_IMAGEIO_MAXALLOC=128
//@ pragma UseQApplication
//@ pragma AppId local.dux.images

import QtQuick
import QtCore
import Quickshell
import qs.DCommon.Common as DC

ShellRoot {
    ThemeBridge { id: theme }

    Component.onCompleted: {
        DC.Style.theme = Qt.binding(() => theme.tokens);
        DC.Style.settings = Qt.binding(() => theme.settings);
        const folder = Quickshell.env("DIMAGES_FOLDER");
        const file = Quickshell.env("DIMAGES_FILE");
        if (folder)
            viewer.openFolder(folder);
        else if (file)
            viewer.openUrl(file);
        else if (!viewer.openFolder(StandardPaths.locate(StandardPaths.PicturesLocation, "", StandardPaths.LocateDirectory)))
            viewer.openFolder(StandardPaths.writableLocation(StandardPaths.HomeLocation));
    }

    ViewerWindow {
        id: viewer
        onClosed: Qt.quit()
    }
}
