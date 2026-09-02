import QtQuick
import Quickshell.Io
import qs.Modals.FileBrowser
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    function fileUrl(path) {
        if (path.startsWith("file:"))
            return path;
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    FileBrowserModal {
        id: browser

        browserTitle: "Files"
        browserType: "fileManager"
        fileExtensions: ["*"]
        keepContentLoaded: true

        onFileSelected: path => Qt.openUrlExternally(root.fileUrl(path))
    }

    IpcHandler {
        target: "dmsFiles"

        function open(): string {
            browser.open();
            return "opened";
        }

        function toggle(): string {
            if (browser.visible) {
                browser.close();
                return "closed";
            }
            browser.open();
            return "opened";
        }
    }
}
