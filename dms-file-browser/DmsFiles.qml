import QtQuick
import Quickshell.Io
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    FileManagerWindow {
        id: browser
    }
    IpcHandler {
        target: "dmsFiles"

        function open(): string {
            browser.show();
            return "opened";
        }
        function openPath(path): string {
            return browser.showPath(String(path || "")) ? "opening" : "invalid path";
        }
        function status(): string {
            return browser.statusJson();
        }
        function toggle(): string {
            browser.toggle();
            return browser.visible ? "opened" : "closed";
        }
    }
}
