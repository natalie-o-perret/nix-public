import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Qt.labs.folderlistmodel
import Quickshell
import qs.DCommon.Common
import qs.DCommon.Widgets
import qs.DCommon.FileBrowser

FloatingWindow {
    id: viewer

    property string filePath: ""
    property string folderPath: ""
    property bool selectFirstPending: false
    property bool fitMode: true
    property real manualZoom: 1
    property int quarterTurns: 0
    readonly property bool loaded: image.status === Image.Ready
    readonly property bool failed: image.status === Image.Error
    readonly property bool dialogOpen: picker.visible || folderPicker.visible
    // SVG and @2x implicit sizes are logical. Zoom needs the actual source pixels.
    readonly property real pixelWidth: Math.max(0, image.sourceSize.width)
    readonly property real pixelHeight: Math.max(0, image.sourceSize.height)
    readonly property real rotatedWidth: quarterTurns % 2 ? pixelHeight : pixelWidth
    readonly property real rotatedHeight: quarterTurns % 2 ? pixelWidth : pixelHeight
    readonly property real fitZoom: loaded ? Math.min(1, viewport.width * devicePixelRatio / rotatedWidth, viewport.height * devicePixelRatio / rotatedHeight) : 1
    readonly property real zoomFactor: fitMode ? fitZoom : manualZoom
    readonly property int imageCount: folder.count
    readonly property bool emptyFolder: folderPath !== "" && !filePath && folder.status === FolderListModel.Ready && folder.count === 0
    readonly property string displayName: FilePaths.baseName(folderPath) || folderPath || "Images"
    readonly property int currentIndex: folder.status === FolderListModel.Ready && folder.count > 0 && filePath !== "" ? folder.indexOf(FilePaths.toFileUrl(filePath)) : -1
    readonly property bool thumbnailsVisible: folder.status === FolderListModel.Ready && imageCount > 1 && FilePaths.parentOf(folder.get(0, "filePath")) === folderPath
    readonly property var imageFilters: ["*.bmp", "*.gif", "*.ico", "*.jpeg", "*.jpg", "*.png", "*.svg", "*.svgz", "*.tif", "*.tiff", "*.webp", "*.xbm", "*.xpm"]

    title: folderPath ? displayName + " - Images" : displayName
    implicitWidth: 1000
    implicitHeight: 720
    minimumSize: Qt.size(620, 360)
    color: Style.surface
    visible: true

    onFilePathChanged: {
        fitMode = true;
        manualZoom = 1;
        quarterTurns = 0;
    }
    onFolderPathChanged: Qt.callLater(syncDirectory)
    Component.onCompleted: syncDirectory()

    function syncDirectory() {
        // shortcut: Qt 6.11 reparses decoded folders as URLs, remove this extra escaping once its resolvePath is fixed.
        folder.folder = FilePaths.toFileUrl(folderPath).replace(/%/g, "%25");
        selectFirstImage();
    }

    function openUrl(url) {
        const path = FilePaths.fromUrl(url);
        if (!path.startsWith("/"))
            return false;
        selectFirstPending = false;
        folderPath = FilePaths.parentOf(path);
        filePath = path;
        return true;
    }

    function openFolder(url) {
        const path = FilePaths.fromUrl(url);
        if (!path.startsWith("/"))
            return false;
        selectFirstPending = false;
        filePath = "";
        folderPath = path.replace(/\/+$/, "") || "/";
        selectFirstPending = true;
        Qt.callLater(selectFirstImage);
        return true;
    }

    function selectFirstImage() {
        if (!selectFirstPending || folder.status !== FolderListModel.Ready || folder.count === 0)
            return;
        selectImage(0);
    }

    function selectImage(index) {
        if (!Number.isInteger(index) || index < 0 || index >= folder.count)
            return;
        const path = folder.get(index, "filePath");
        if (FilePaths.parentOf(path) !== folderPath)
            return;
        selectFirstPending = false;
        filePath = path;
    }

    function step(direction) {
        if (currentIndex >= 0)
            selectImage(currentIndex + direction);
    }

    function centerImage() {
        viewport.contentX = Math.max(0, (viewport.contentWidth - viewport.width) / 2);
        viewport.contentY = Math.max(0, (viewport.contentHeight - viewport.height) / 2);
    }

    function fit() {
        fitMode = true;
        Qt.callLater(centerImage);
    }

    function actualSize() {
        manualZoom = 1;
        fitMode = false;
        Qt.callLater(centerImage);
    }

    function zoomAt(factor, x = viewport.width / 2, y = viewport.height / 2) {
        if (!loaded || !Number.isFinite(factor) || factor <= 0)
            return;
        const before = zoomFactor;
        const pointX = (viewport.contentX + x - viewport.contentWidth / 2) / before;
        const pointY = (viewport.contentY + y - viewport.contentHeight / 2) / before;
        manualZoom = Math.max(0.01, Math.min(32, before * factor));
        fitMode = false;
        viewport.contentX = Math.max(0, Math.min(viewport.contentWidth - viewport.width, viewport.contentWidth / 2 + pointX * manualZoom - x));
        viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height, viewport.contentHeight / 2 + pointY * manualZoom - y));
    }

    function rotate() {
        quarterTurns = (quarterTurns + 1) % 4;
        Qt.callLater(centerImage);
    }

    FolderListModel {
        id: folder
        nameFilters: viewer.imageFilters
        showDirs: false
        showOnlyReadable: true
        caseSensitive: false
        sortCaseSensitive: false
        sortField: FolderListModel.Name
        onStatusChanged: viewer.selectFirstImage()
        onCountChanged: viewer.selectFirstImage()
    }

    FileDialog {
        id: picker
        parentWindow: viewport.Window.window
        title: "Open image"
        currentFolder: viewer.folderPath ? FilePaths.toFileUrl(viewer.folderPath) : StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: ["Images (" + viewer.imageFilters.join(" ") + ")", "All files (*)"]
        onAccepted: viewer.openUrl(selectedFile)
    }

    FolderDialog {
        id: folderPicker
        parentWindow: viewport.Window.window
        title: "Open image folder"
        currentFolder: picker.currentFolder
        onAccepted: viewer.openFolder(selectedFolder)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        DWindowHeader {
            Layout.fillWidth: true
            controls: windowControls
            title: viewer.displayName
            subtitle: FilePaths.baseName(viewer.filePath)
            onCloseRequested: Qt.quit()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.spacingM
            Layout.rightMargin: Style.spacingM
            Layout.bottomMargin: Style.spacingS
            spacing: Style.spacingXS

            DIconButton {
                iconName: "add_photo_alternate"
                tooltipText: "Open image (Ctrl+O)"
                onClicked: picker.open()
            }
            DIconButton {
                iconName: "folder_open"
                tooltipText: "Open folder (Ctrl+Shift+O)"
                onClicked: folderPicker.open()
            }
            DIconButton {
                iconName: "navigate_before"
                tooltipText: "Previous image (Left)"
                enabled: viewer.currentIndex > 0
                onClicked: viewer.step(-1)
            }
            DIconButton {
                iconName: "navigate_next"
                tooltipText: "Next image (Right)"
                enabled: viewer.currentIndex >= 0 && viewer.currentIndex + 1 < viewer.imageCount
                onClicked: viewer.step(1)
            }
            Item { Layout.fillWidth: true }
            DIconButton {
                iconName: "remove"
                tooltipText: "Zoom out (Ctrl+-)"
                enabled: viewer.loaded
                onClicked: viewer.zoomAt(1 / 1.25)
            }
            DButton {
                text: Math.round(viewer.zoomFactor * 100) + "%"
                variant: "text"
                tooltipText: "Actual pixels (1)"
                enabled: viewer.loaded
                onClicked: viewer.actualSize()
            }
            DIconButton {
                iconName: "add"
                tooltipText: "Zoom in (Ctrl++)"
                enabled: viewer.loaded
                onClicked: viewer.zoomAt(1.25)
            }
            DIconButton {
                iconName: "fit_screen"
                tooltipText: "Fit image (F)"
                variant: viewer.fitMode ? "tonal" : "standard"
                enabled: viewer.loaded
                onClicked: viewer.fit()
            }
            DIconButton {
                iconName: "rotate_right"
                tooltipText: "Rotate view (R), without changing the file"
                enabled: viewer.loaded
                onClicked: viewer.rotate()
            }
            DIconButton {
                iconName: viewer.fullscreen ? "fullscreen_exit" : "fullscreen"
                tooltipText: "Fullscreen (F11)"
                onClicked: viewer.fullscreen = !viewer.fullscreen
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Style.spacingM
            Layout.rightMargin: Style.spacingM
            radius: Style.cornerRadiusL
            color: Style.surfaceContainerLow

            DFlickable {
                id: viewport
                anchors.fill: parent
                anchors.margins: Style.spacingS
                clip: true
                contentWidth: Math.max(width, viewer.rotatedWidth * viewer.zoomFactor / viewer.devicePixelRatio)
                contentHeight: Math.max(height, viewer.rotatedHeight * viewer.zoomFactor / viewer.devicePixelRatio)
                wheelEnabled: false
                fadeEdges: false
                flickableDirection: Flickable.HorizontalAndVerticalFlick
                onWidthChanged: if (viewer.fitMode) Qt.callLater(viewer.centerImage)
                onHeightChanged: if (viewer.fitMode) Qt.callLater(viewer.centerImage)

                // shortcut: full-image decoding uses Qt's 128 MiB allocation limit; add tiled decoding for larger panoramas.
                Image {
                    id: image
                    objectName: "imageView"
                    anchors.centerIn: parent
                    source: FilePaths.toFileUrl(viewer.filePath)
                    asynchronous: true
                    autoTransform: true
                    cache: false
                    mipmap: true
                    width: viewer.pixelWidth * viewer.zoomFactor / viewer.devicePixelRatio
                    height: viewer.pixelHeight * viewer.zoomFactor / viewer.devicePixelRatio
                    rotation: viewer.quarterTurns * 90
                    Accessible.role: Accessible.Graphic
                    Accessible.name: FilePaths.baseName(viewer.filePath)
                    onStatusChanged: if (status === Image.Ready) Qt.callLater(viewer.centerImage)
                }

                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse
                    onWheel: event => {
                        viewer.zoomAt(Math.pow(1.0015, event.angleDelta.y), event.x, event.y);
                        event.accepted = true;
                    }
                }
                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.TouchPad
                    acceptedModifiers: Qt.ControlModifier
                    onWheel: event => {
                        viewer.zoomAt(Math.pow(1.0015, event.angleDelta.y), event.x, event.y);
                        event.accepted = true;
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - Style.spacingXL * 2, 480)
                spacing: Style.spacingL
                visible: !viewer.loaded

                DIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: viewer.failed ? "broken_image" : "image"
                    size: 56
                    color: viewer.failed ? Style.error : Style.primary
                }
                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: {
                        if (viewer.failed)
                            return "Couldn't open this image. It may be damaged, unsupported, or too large.";
                        if (viewer.emptyFolder)
                            return "No supported images in this folder.";
                        if (viewer.selectFirstPending)
                            return "Loading folder...";
                        return viewer.filePath ? "Loading image..." : "Drop an image here, or choose an image or folder.";
                    }
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.spacingS
                    visible: image.status !== Image.Loading
                    DButton {
                        text: "Open image"
                        iconName: "add_photo_alternate"
                        onClicked: picker.open()
                    }
                    DButton {
                        text: "Open folder"
                        iconName: "folder_open"
                        variant: "tonal"
                        onClicked: folderPicker.open()
                    }
                }
            }

            DropArea {
                anchors.fill: parent
                onEntered: drag => drag.accepted = drag.hasUrls && drag.urls.length === 1 && String(drag.urls[0]).startsWith("file:///")
                onDropped: drop => {
                    if (drop.urls.length === 1 && viewer.openUrl(drop.urls[0]))
                        drop.acceptProposedAction();
                }
            }
        }

        DCarousel {
            id: thumbnails
            objectName: "thumbnails"
            Layout.fillWidth: true
            Layout.preferredHeight: 104
            Layout.leftMargin: Style.spacingM
            Layout.rightMargin: Style.spacingM
            Layout.topMargin: Style.spacingS
            visible: viewer.thumbnailsVisible
            model: folder
            preferredItemWidth: 120
            currentIndex: viewer.currentIndex
            keyNavigationEnabled: false
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: DActionButton {
                id: thumbnail
                required property int index
                required property string filePath
                required property string fileName
                readonly property bool selected: ListView.isCurrentItem

                objectName: "thumbnail-" + index
                width: thumbnails.itemWidth
                height: thumbnails.height
                circular: false
                radius: Style.cornerRadiusM
                backgroundColor: selected ? Style.selectedContainer : Style.surfaceContainer
                border.width: selected ? Style.focusRingWidth : 0
                border.color: Style.primary
                tooltipText: fileName
                Accessible.role: Accessible.ListItem
                Accessible.name: fileName
                Accessible.selected: selected
                onClicked: viewer.selectImage(index)

                Image {
                    id: preview
                    objectName: "thumbnail-image-" + thumbnail.index
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Style.spacingS
                    height: thumbnail.height - Style.spacingS * 3 - fileLabel.implicitHeight
                    source: FilePaths.toFileUrl(thumbnail.filePath)
                    sourceSize: Qt.size(Math.max(1, Math.ceil(width * viewer.devicePixelRatio)), Math.max(1, Math.ceil(height * viewer.devicePixelRatio)))
                    asynchronous: true
                    autoTransform: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                }
                DIcon {
                    anchors.centerIn: preview
                    name: preview.status === Image.Error ? "broken_image" : "image"
                    color: Style.surfaceTextMedium
                    visible: preview.status !== Image.Ready
                }
                StyledText {
                    id: fileLabel
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.spacingS
                    text: thumbnail.fileName
                    font.pixelSize: Style.fontSizeSmall
                    color: thumbnail.selected ? Style.primary : Style.surfaceText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.NoWrap
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.margins: Style.spacingM
            font.pixelSize: Style.fontSizeSmall
            color: Style.surfaceTextMedium
            text: viewer.loaded ? viewer.pixelWidth + " x " + viewer.pixelHeight + " px" + (viewer.currentIndex >= 0 ? "   |   " + (viewer.currentIndex + 1) + " / " + viewer.imageCount : "") + "   |   Scroll to zoom, drag to pan" : "F: fit   |   1: actual pixels   |   R: rotate   |   F11: fullscreen"
            Accessible.name: text
        }
    }

    FloatingWindowControls {
        id: windowControls
        targetWindow: viewer
    }

    Shortcut { sequence: "Ctrl+O"; enabled: !viewer.dialogOpen; onActivated: picker.open() }
    Shortcut { sequence: "Ctrl+Shift+O"; enabled: !viewer.dialogOpen; onActivated: folderPicker.open() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequences: ["Left", "PgUp"]; enabled: !viewer.dialogOpen; onActivated: viewer.step(-1) }
    Shortcut { sequences: ["Right", "PgDown"]; enabled: !viewer.dialogOpen; onActivated: viewer.step(1) }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; enabled: viewer.loaded && !viewer.dialogOpen; onActivated: viewer.zoomAt(1.25) }
    Shortcut { sequence: "Ctrl+-"; enabled: viewer.loaded && !viewer.dialogOpen; onActivated: viewer.zoomAt(1 / 1.25) }
    Shortcut { sequence: "1"; enabled: viewer.loaded && !viewer.dialogOpen; onActivated: viewer.actualSize() }
    Shortcut { sequence: "F"; enabled: viewer.loaded && !viewer.dialogOpen; onActivated: viewer.fit() }
    Shortcut { sequence: "R"; enabled: viewer.loaded && !viewer.dialogOpen; onActivated: viewer.rotate() }
    Shortcut { sequence: "F11"; enabled: !viewer.dialogOpen; onActivated: viewer.fullscreen = !viewer.fullscreen }
    Shortcut {
        sequence: "Escape"
        enabled: !viewer.dialogOpen
        onActivated: {
            if (viewer.fullscreen)
                viewer.fullscreen = false;
            else
                Qt.quit();
        }
    }
}
