import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property bool current: false
    property bool cut: false
    property var dragUrls: []
    property bool dropEnabled: true
    property bool dropHover: false
    required property bool fileIsDir
    required property var fileModified
    required property string fileName
    required property string filePath
    required property var fileSize
    required property url fileUrl
    property bool gridMode: false
    readonly property bool imageFile: !fileIsDir && ["avif", "bmp", "gif", "heif", "ico", "jpeg", "jpg", "jxl", "png", "svg", "webp"].includes(suffix)
    required property int index
    property bool selected: false
    property int sizeColumnWidth: 84
    readonly property string suffix: {
        const dot = fileName.lastIndexOf(".");
        return dot > 0 ? fileName.slice(dot + 1).toLowerCase() : "";
    }
    property int timeColumnWidth: 160
    property int typeColumnWidth: 104
    readonly property string typeText: fileIsDir ? "Folder" : (suffix ? suffix.toUpperCase() + " file" : "File")

    signal clicked(int index, int modifiers)
    signal contextRequested(var sender, real x, real y, int index)
    signal doubleClicked(int index)
    signal filesDropped(var urls, string destination, int action)
    signal prepareDrag(int index)

    function acceptDropAction(event) {
        if (isInternalDrag(event))
            return event.proposedAction;
        return Qt.CopyAction;
    }
    function formatSize(bytes) {
        const size = Number(bytes) || 0;
        if (size < 1024)
            return size + " B";
        if (size < 1048576)
            return (size / 1024).toFixed(1) + " KB";
        if (size < 1073741824)
            return (size / 1048576).toFixed(1) + " MB";
        return (size / 1073741824).toFixed(1) + " GB";
    }
    function iconForFile() {
        const lower = fileName.toLowerCase();
        if (lower.startsWith("dockerfile"))
            return "docker";
        return suffix || "file";
    }
    function isInternalDrag(event) {
        const source = event.source;
        if (!source)
            return false;
        if (source.Window && source.Window.window && source.Window.window === root.Window.window)
            return true;
        return false;
    }
    function supportsDrop(event) {
        if (!dropEnabled || !event.hasUrls)
            return false;
        if (!(event.supportedActions & Qt.CopyAction))
            return false;
        if (event.proposedAction !== Qt.CopyAction && event.proposedAction !== Qt.MoveAction)
            return false;
        if (!(event.supportedActions & event.proposedAction))
            return false;
        if (event.urls.length === 0)
            return false;
        for (let i = 0; i < event.urls.length; ++i) {
            if (!String(event.urls[i]).startsWith("file:///"))
                return false;
        }
        return true;
    }

    Accessible.focusable: true
    Accessible.focused: current
    Accessible.name: fileName + (fileIsDir ? ", folder" : "")
    Accessible.role: Accessible.ListItem
    Accessible.selectable: true
    Accessible.selected: selected
    Drag.active: dragHandler.active
    Drag.dragType: Drag.Automatic
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.mimeData: ({
            "text/uri-list": root.dragUrls.join("\r\n") + "\r\n"
        })
    Drag.proposedAction: dragHandler.centroid.modifiers & Qt.ControlModifier ? Qt.CopyAction : Qt.MoveAction
    Drag.source: root
    Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
    border.color: current ? Theme.primary : (selected ? Theme.outlineStrong : "transparent")
    border.width: current ? 2 : (selected ? 1 : 0)
    color: {
        if (dropHover)
            return Theme.primaryHover;
        if (selected)
            return Theme.primaryContainer;
        if (itemArea.containsMouse)
            return Theme.surfaceContainerHigh;
        return "transparent";
    }
    opacity: cut ? 0.55 : 1
    radius: Theme.cornerRadius

    Accessible.onPressAction: {
        root.clicked(root.index, Qt.NoModifier);
        root.doubleClicked(root.index);
    }

    Item {
        id: iconFrame

        height: root.gridMode ? Math.min(96, root.height - 48) : 30
        width: root.gridMode ? Math.min(96, root.width - Theme.spacingL) : 30
        x: root.gridMode ? Math.round((root.width - width) / 2) : Theme.spacingS
        y: root.gridMode ? Theme.spacingS : Math.round((root.height - height) / 2)

        Image {
            id: preview

            anchors.fill: parent
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectFit
            retainWhileLoading: false
            source: root.imageFile ? root.fileUrl : ""
            sourceSize: Qt.size(root.gridMode ? 128 : 40, root.gridMode ? 128 : 40)
            visible: root.imageFile && status === Image.Ready
        }
        DankNFIcon {
            anchors.centerIn: parent
            color: root.fileIsDir ? Theme.primary : Theme.surfaceText
            name: root.fileIsDir ? "folder" : root.iconForFile()
            size: root.gridMode ? Math.min(52, iconFrame.width * 0.56) : 22
            visible: !root.imageFile || preview.status !== Image.Ready
        }
    }
    StyledText {
        id: nameLabel

        color: Theme.surfaceText
        elide: root.gridMode ? Text.ElideNone : Text.ElideRight
        font.pixelSize: Theme.fontSizeSmall
        height: root.gridMode ? root.height - y - Theme.spacingXS : root.height
        horizontalAlignment: root.gridMode ? Text.AlignHCenter : Text.AlignLeft
        maximumLineCount: root.gridMode ? 2 : 1
        text: root.fileName
        verticalAlignment: root.gridMode ? Text.AlignTop : Text.AlignVCenter
        width: root.gridMode ? root.width - Theme.spacingM : Math.max(40, root.width - x - root.sizeColumnWidth - root.timeColumnWidth - root.typeColumnWidth - Theme.spacingM * 2)
        wrapMode: root.gridMode ? Text.Wrap : Text.NoWrap
        x: root.gridMode ? Theme.spacingS : iconFrame.x + iconFrame.width + Theme.spacingS
        y: root.gridMode ? iconFrame.y + iconFrame.height + Theme.spacingXS : 0
    }
    StyledText {
        id: sizeLabel

        anchors.left: nameLabel.right
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.surfaceTextMedium
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignRight
        text: root.fileIsDir ? "" : root.formatSize(root.fileSize)
        visible: !root.gridMode
        width: root.sizeColumnWidth
    }
    StyledText {
        anchors.left: sizeLabel.right
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.surfaceTextMedium
        elide: Text.ElideRight
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignRight
        text: Qt.formatDateTime(root.fileModified, "yyyy-MM-dd HH:mm")
        visible: !root.gridMode
        width: root.timeColumnWidth - Theme.spacingM
    }
    StyledText {
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.surfaceTextMedium
        elide: Text.ElideRight
        font.pixelSize: Theme.fontSizeSmall
        horizontalAlignment: Text.AlignRight
        text: root.typeText
        visible: !root.gridMode
        width: root.typeColumnWidth - Theme.spacingS
    }
    DropArea {
        anchors.fill: parent
        enabled: root.fileIsDir && root.dropEnabled

        onDropped: drop => {
            root.dropHover = false;
            if (!root.supportsDrop(drop)) {
                drop.accepted = false;
                return;
            }
            const action = root.acceptDropAction(drop);
            const urls = [];
            for (let i = 0; i < drop.urls.length; ++i)
                urls.push(String(drop.urls[i]));
            root.filesDropped(urls, root.filePath, action);
            drop.accept(action);
        }
        onEntered: drag => {
            if (root.supportsDrop(drag)) {
                root.dropHover = true;
                drag.accept(root.acceptDropAction(drag));
            } else {
                root.dropHover = false;
                drag.accepted = false;
            }
        }
        onExited: root.dropHover = false
    }
    MouseArea {
        id: itemArea

        acceptedButtons: Qt.LeftButton | Qt.RightButton
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.contextRequested(root, mouse.x, mouse.y, root.index);
            else
                root.clicked(root.index, mouse.modifiers);
        }
        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.doubleClicked(root.index);
        }
    }
    DragHandler {
        id: dragHandler

        acceptedButtons: Qt.LeftButton
        target: null

        onActiveChanged: {
            if (active)
                root.prepareDrag(root.index);
        }
    }
}
