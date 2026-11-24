//@ pragma Env QT_IMAGEIO_MAXALLOC=128
//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import qs.DCommon.Common
import qs.DCommon.FileBrowser

ShellRoot {
    id: test
    property int phase: 0
    property int waitTicks: 0
    readonly property string first: Quickshell.env("TEST_FIRST")
    readonly property string second: Quickshell.env("TEST_SECOND")
    readonly property string broken: Quickshell.env("TEST_BROKEN")

    ThemeBridge { id: theme }
    ViewerWindow { id: viewer }

    Component.onCompleted: {
        Style.theme = Qt.binding(() => theme.tokens);
        Style.settings = Qt.binding(() => theme.settings);
        viewer.openUrl(test.first);
    }

    FileView {
        id: paletteWriter
        path: theme.cache + "/dms/dms-colors.json"
        printErrors: false
    }

    function check(condition, message) {
        if (!condition)
            throw new Error(message);
    }

    function findItem(item, name) {
        if (item.objectName === name)
            return item;
        for (const child of item.children || []) {
            const found = findItem(child, name);
            if (found)
                return found;
        }
        return null;
    }

    function checkPixels() {
        const image = findItem(viewer.contentItem, "imageView");
        check(image && Math.abs(image.width * viewer.devicePixelRatio - viewer.pixelWidth * viewer.zoomFactor) < 0.01, "Physical-pixel image width");
        check(Math.abs(image.height * viewer.devicePixelRatio - viewer.pixelHeight * viewer.zoomFactor) < 0.01, "Physical-pixel image height");
    }

    Timer {
        interval: 25
        running: true
        repeat: true
        onTriggered: {
            try {
                switch (test.phase) {
                case 0:
                    if (!viewer.loaded || viewer.currentIndex < 0 || theme.tokens.primary !== "#e91e63")
                        return;
                    const strip = test.findItem(viewer.contentItem, "thumbnails");
                    strip.forceLayout();
                    const preview = test.findItem(viewer.contentItem, "thumbnail-image-0");
                    if (!strip.currentItem || !preview || preview.status !== Image.Ready)
                        return;
                    test.check(viewer.pixelWidth === 1600 && viewer.pixelHeight === 900, "Original image dimensions");
                    test.check(viewer.imageCount === 2 && viewer.currentIndex === 0, "Sorted folder navigation, including uppercase extensions");
                    test.check(viewer.folderPath === FilePaths.parentOf(test.first), "Opening a file opens its containing folder");
                    test.check(viewer.displayName === FilePaths.baseName(viewer.folderPath) && viewer.title.endsWith(" - Images"), "Images branding and folder title");
                    test.check(viewer.thumbnailsVisible && strip.visible && strip.count === 2, "Multiple images show thumbnails");
                    test.check(strip.currentIndex === 0 && strip.currentItem.selected && strip.currentItem.filePath === test.first, "Thumbnail selection follows the image");
                    test.check(preview.sourceSize.width <= Math.ceil(preview.width * viewer.devicePixelRatio) && preview.sourceSize.height <= Math.ceil(preview.height * viewer.devicePixelRatio), "Thumbnail decoding is bounded to display size");
                    test.check(viewer.fitMode && viewer.zoomFactor > 0 && viewer.zoomFactor <= 1, "Fit mode");
                    test.check(Math.abs(viewer.devicePixelRatio - Number(Quickshell.env("QT_SCALE_FACTOR"))) < 0.01, "Fractional display scaling");
                    test.check(Qt.colorEqual(Style.primary, "#e91e63"), "DMS accent reaches real shared widgets");
                    viewer.actualSize();
                    test.phase++;
                    break;
                case 1:
                    test.check(!viewer.fitMode && viewer.zoomFactor === 1, "Actual-pixel mode");
                    test.checkPixels();
                    viewer.zoomAt(2);
                    test.check(viewer.zoomFactor === 2, "Zoom in");
                    viewer.zoomAt(Infinity);
                    test.check(viewer.zoomFactor === 2, "Reject non-finite zoom");
                    viewer.zoomAt(1e9);
                    test.check(viewer.zoomFactor === 32, "Upper zoom bound");
                    viewer.zoomAt(1e-9);
                    test.check(viewer.zoomFactor === 0.01, "Lower zoom bound");
                    viewer.rotate();
                    test.check(viewer.quarterTurns === 1 && viewer.rotatedWidth === 900 && viewer.rotatedHeight === 1600, "Rotation bounds");
                    viewer.fit();
                    viewer.step(1);
                    test.phase++;
                    break;
                case 2:
                    if (!viewer.loaded || viewer.filePath !== test.second)
                        return;
                    test.check(viewer.quarterTurns === 0 && viewer.fitMode, "New images reset the view");
                    const thumbnails = test.findItem(viewer.contentItem, "thumbnails");
                    thumbnails.forceLayout();
                    test.check(thumbnails.currentIndex === 1 && thumbnails.currentItem.selected, "Navigation updates the thumbnail highlight");
                    viewer.step(1);
                    test.check(viewer.filePath === test.second, "Stop at the last image");
                    thumbnails.itemAtIndex(0).click();
                    test.phase++;
                    break;
                case 3:
                    if (!viewer.loaded || viewer.filePath !== test.first)
                        return;
                    viewer.step(-1);
                    test.check(viewer.filePath === test.first, "Stop at the first image");
                    test.check(!viewer.openUrl("https://example.invalid/image.png") && viewer.filePath === test.first, "Reject remote URLs");
                    viewer.fullscreen = true;
                    test.check(viewer.fullscreen, "Enter fullscreen");
                    viewer.fullscreen = false;
                    viewer.openUrl(test.broken);
                    test.phase++;
                    break;
                case 4:
                    if (!viewer.failed)
                        return;
                    test.check(!viewer.loaded, "Corrupt images show an error, not stale content");
                    viewer.openUrl(test.broken + ".missing");
                    test.phase++;
                    break;
                case 5:
                    if (!viewer.failed)
                        return;
                    viewer.openUrl(Quickshell.env("TEST_VECTOR"));
                    test.phase++;
                    break;
                case 6:
                    if (!viewer.loaded)
                        return;
                    test.check(viewer.pixelWidth === 640 && viewer.pixelHeight === 480, "SVG pixel dimensions at fractional scaling");
                    test.checkPixels();
                    viewer.openUrl(Quickshell.env("TEST_RETINA"));
                    test.phase++;
                    break;
                case 7:
                    if (!viewer.loaded)
                        return;
                    test.check(viewer.pixelWidth === 400 && viewer.pixelHeight === 200, "Retina-image pixel dimensions");
                    test.checkPixels();
                    viewer.openUrl(Quickshell.env("TEST_ORIENTED"));
                    test.phase++;
                    break;
                case 8:
                    if (!viewer.loaded)
                        return;
                    test.check(viewer.pixelWidth === 2 && viewer.pixelHeight === 4, "EXIF photo orientation");
                    test.checkPixels();
                    test.check(!viewer.openFolder("https://example.invalid/folder"), "Reject remote folder URLs");
                    viewer.openFolder(FilePaths.toFileUrl(Quickshell.env("TEST_FOLDER")) + "/");
                    test.phase++;
                    break;
                case 9:
                    if (!viewer.loaded || viewer.filePath !== test.first)
                        return;
                    test.check(viewer.currentIndex === 0 && viewer.imageCount === 2, "Folders select the first supported image");
                    viewer.step(1);
                    test.phase++;
                    break;
                case 10:
                    if (!viewer.loaded || viewer.filePath !== test.second)
                        return;
                    viewer.openFolder(Quickshell.env("TEST_FOLDER"));
                    test.phase++;
                    break;
                case 11:
                    if (!viewer.loaded || viewer.filePath !== test.first)
                        return;
                    test.check(viewer.fitMode && viewer.quarterTurns === 0, "Reopening the same folder resets to its first image");
                    viewer.openFolder(Quickshell.env("TEST_EMPTY_FOLDER"));
                    test.phase++;
                    break;
                case 12:
                    if (!viewer.emptyFolder)
                        return;
                    test.check(!viewer.loaded && !viewer.failed && viewer.imageCount === 0 && viewer.filePath === "", "Empty folders ignore non-images and subfolders");
                    viewer.openUrl(FilePaths.toFileUrl(test.first));
                    test.phase++;
                    break;
                case 13:
                    if (!viewer.loaded || viewer.filePath !== test.first)
                        return;
                    test.check(viewer.folderPath === FilePaths.parentOf(test.first) && viewer.currentIndex === 0, "Opening an image stays in folder mode");
                    viewer.selectImage(-1);
                    viewer.selectImage(Infinity);
                    viewer.selectImage(500);
                    test.check(viewer.filePath === test.first, "Invalid thumbnail selections are ignored");
                    viewer.openUrl(Quickshell.env("TEST_SINGLE"));
                    test.phase++;
                    break;
                case 14:
                    if (!viewer.loaded || viewer.currentIndex !== 0 || viewer.imageCount !== 1)
                        return;
                    test.check(!viewer.thumbnailsVisible && !test.findItem(viewer.contentItem, "thumbnails").visible, "Single-image folders hide the thumbnail strip");
                    test.check(viewer.folderPath === FilePaths.parentOf(Quickshell.env("TEST_SINGLE")), "Single images still have folder context");
                    viewer.openFolder(Quickshell.env("TEST_MANY"));
                    test.phase++;
                    break;
                case 15:
                    if (!viewer.loaded || viewer.imageCount !== 24 || viewer.currentIndex !== 0)
                        return;
                    viewer.selectImage(23);
                    test.phase++;
                    break;
                case 16:
                    if (!viewer.loaded || viewer.currentIndex !== 23)
                        return;
                    const lastStrip = test.findItem(viewer.contentItem, "thumbnails");
                    lastStrip.forceLayout();
                    test.check(lastStrip.currentItem?.filePath === viewer.filePath && lastStrip.currentItem.selected, "Off-screen thumbnail selection");
                    test.check(lastStrip.currentItem.x >= lastStrip.contentX - 1 && lastStrip.currentItem.x + lastStrip.currentItem.width <= lastStrip.contentX + lastStrip.width + 1, "Selected thumbnails scroll into view");
                    let instantiated = 0;
                    for (const item of lastStrip.contentItem.children) {
                        if (item.objectName.startsWith("thumbnail-") && item.index >= 0)
                            instantiated++;
                    }
                    test.check(instantiated < lastStrip.count, "Only nearby thumbnails are instantiated");
                    viewer.step(-1);
                    test.phase++;
                    break;
                case 17:
                    if (!viewer.loaded || viewer.currentIndex !== 22)
                        return;
                    viewer.openFolder(Quickshell.env("TEST_EMPTY_FOLDER"));
                    test.phase++;
                    break;
                case 18:
                    if (!viewer.emptyFolder)
                        return;
                    test.check(!viewer.thumbnailsVisible, "Empty folders have no thumbnails");
                    paletteWriter.setText(JSON.stringify({mode: "dark", colors: {dark: {primary: "#00aaff", on_primary: "#000000"}}}));
                    test.phase++;
                    break;
                case 19:
                    if (theme.tokens.primary !== "#00aaff")
                        return;
                    test.check(Qt.colorEqual(Style.primary, "#00aaff"), "Live DMS theme changes");
                    test.check(viewer.emptyFolder && !viewer.loaded && !viewer.failed, "Empty folder state");
                    paletteWriter.setText("{");
                    test.phase++;
                    break;
                case 20:
                    if (++test.waitTicks < 12)
                        return;
                    test.check(theme.tokens.primary === "#00aaff", "Malformed theme preserves the last valid palette");
                    viewer.openUrl(Quickshell.env("TEST_XPM"));
                    test.phase++;
                    break;
                case 21:
                    if (!viewer.loaded || viewer.currentIndex < 0)
                        return;
                    test.check(viewer.pixelWidth === 2 && viewer.pixelHeight === 2, "XPM decoding and folder navigation");
                    viewer.openUrl(Quickshell.env("TEST_XBM"));
                    test.phase++;
                    break;
                case 22:
                    if (!viewer.loaded || viewer.currentIndex < 0)
                        return;
                    test.check(viewer.pixelWidth === 8 && viewer.pixelHeight === 2, "XBM decoding and folder navigation");
                    console.log("DUX_IMAGES_TEST_PASS");
                    Qt.quit();
                }
            } catch (error) {
                console.error("DUX_IMAGES_TEST_FAIL:", error.message);
                Qt.quit();
            }
        }
    }

    Timer {
        interval: 15000
        running: true
        onTriggered: {
            console.error("DUX_IMAGES_TEST_FAIL: timeout in phase", test.phase, "loaded", viewer.loaded, "failed", viewer.failed, "count", viewer.imageCount, "index", viewer.currentIndex, "accent", theme.tokens.primary, "path", viewer.filePath);
            Qt.quit();
        }
    }
}
