import Qt.labs.folderlistmodel
import QtCore
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Widgets

FloatingWindow {
    id: root

    readonly property int activeJobs: {
        let count = 0;
        for (const job of jobs) {
            if (["queued", "running", "cancelling"].includes(job.status))
                ++count;
        }
        return count;
    }
    property string appliedSearchText: ""
    property bool backendReady: false
    property var conflictEvents: ({})
    property var conflictQueue: []
    property var currentConflict: null
    property int currentIndex: -1
    property string currentItemPath: ""
    property string currentPath: "/"
    property var cutPathMap: ({})
    property bool disablePopupTransparency: true
    readonly property var displayJob: {
        for (let i = jobs.length - 1; i >= 0; --i) {
            if (["queued", "running", "cancelling"].includes(jobs[i].status))
                return jobs[i];
        }
        return jobs.length > 0 ? jobs[jobs.length - 1] : null;
    }
    readonly property real displayProgress: {
        const job = displayJob;
        if (!job)
            return 0;
        if (job.bytesTotal > 0)
            return Math.max(0, Math.min(1, job.bytesDone / job.bytesTotal));
        if (job.itemsTotal > 0)
            return Math.max(0, Math.min(1, job.itemsDone / job.itemsTotal));
        return job.status === "ok" ? 1 : 0;
    }
    property var fileClipboard: ({
            "sources": [],
            "cut": false
        })
    readonly property int gridCellHeight: 146
    readonly property int gridCellWidth: 132
    readonly property int gridColumns: Math.max(1, Math.floor(fileGrid.width / gridCellWidth))
    property int historyIndex: -1
    property var historyPaths: []
    readonly property string homePath: normalizePath(String(StandardPaths.writableLocation(StandardPaths.HomeLocation))) || "/"
    property var jobs: []
    property string modelFolder: ""
    property int nextRequestId: 1
    property bool pathEditLossGuard: false
    property bool pathEditMode: false
    readonly property var places: [
        {
            "name": "Home",
            "icon": "home",
            "path": homePath
        },
        {
            "name": "Desktop",
            "icon": "desktop_windows",
            "path": normalizePath(String(StandardPaths.writableLocation(StandardPaths.DesktopLocation)))
        },
        {
            "name": "Documents",
            "icon": "description",
            "path": normalizePath(String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation)))
        },
        {
            "name": "Downloads",
            "icon": "download",
            "path": normalizePath(String(StandardPaths.writableLocation(StandardPaths.DownloadLocation)))
        },
        {
            "name": "Personal",
            "icon": "person",
            "path": homePath + "/Personal"
        },
        {
            "name": "Professional",
            "icon": "work",
            "path": homePath + "/Professional"
        },
        {
            "name": "Music",
            "icon": "music_note",
            "path": normalizePath(String(StandardPaths.writableLocation(StandardPaths.MusicLocation)))
        },
        {
            "name": "Pictures",
            "icon": "image",
            "path": normalizePath(String(StandardPaths.writableLocation(StandardPaths.PicturesLocation)))
        },
        {
            "name": "Videos",
            "icon": "movie",
            "path": normalizePath(String(StandardPaths.writableLocation(StandardPaths.MoviesLocation)))
        },
        {
            "name": "File System",
            "icon": "storage",
            "path": "/"
        }
    ]
    property var propertyItems: []
    property var queuedNavigation: null
    property var requestRecords: ({})
    property string searchText: ""
    property bool searchVisible: false
    property var selectedDragUrls: []
    property var selectedPathMap: ({})
    property var selection: []
    property int selectionAnchor: -1
    property bool settingsLoaded: false
    readonly property bool shouldBeVisible: root.visible
    property bool showHidden: false
    property bool showJobBar: false
    property bool showSidebar: true
    property bool sortAscending: true
    property string sortBy: "name"
    property bool statusIsError: false
    property string statusMessage: ""
    property string viewMode: "list"

    function activateCurrentItem() {
        if (!currentItemPath)
            return;
        const index = folderModel.indexOf(fileUrl(currentItemPath));
        if (index < 0) {
            clearSelection();
            return;
        }
        currentIndex = index;
        activateItem(index);
    }
    function activateItem(index) {
        const item = itemAt(index);
        if (!item)
            return;
        if (item.isDir)
            requestNavigation(item.path, "push", -1, false);
        else
            Qt.openUrlExternally(fileUrl(item.path));
    }
    function activateSelection() {
        if (selection.length === 1 && selection[0].isDir) {
            requestNavigation(selection[0].path, "push", -1, false);
            return;
        }
        for (const item of selection) {
            if (!item.isDir)
                Qt.openUrlExternally(fileUrl(item.path));
        }
    }
    function basename(path) {
        const normalized = normalizePath(path);
        if (normalized === "/")
            return "/";
        return normalized.slice(normalized.lastIndexOf("/") + 1);
    }
    function blankMenuItems() {
        return [
            {
                "text": "New Folder",
                "icon": "create_new_folder",
                "shortcut": "Ctrl+Shift+N",
                "enabled": backendReady,
                "action": () => createItem(true)
            },
            {
                "text": "New File",
                "icon": "note_add",
                "shortcut": "Ctrl+Shift+T",
                "enabled": backendReady,
                "action": () => createItem(false)
            },
            {
                "text": "Paste",
                "icon": "content_paste",
                "shortcut": "Ctrl+V",
                "enabled": backendReady && fileClipboard.sources.length > 0,
                "action": () => paste(currentPath)
            },
            {
                "type": "separator"
            },
            {
                "text": "Refresh",
                "icon": "refresh",
                "shortcut": "F5",
                "action": refreshFolder
            },
            {
                "text": "Properties",
                "icon": "info",
                "shortcut": "Ctrl+I",
                "action": () => showProperties([])
            }
        ];
    }
    function breadcrumbs() {
        const crumbs = [
            {
                "name": "/",
                "path": "/"
            }
        ];
        let path = "";
        for (const part of currentPath.split("/")) {
            if (!part)
                continue;
            path += "/" + part;
            crumbs.push({
                "name": path === homePath ? "Home" : part,
                "path": path
            });
        }
        return crumbs;
    }
    function cancelJob(id) {
        if (!backendReady || id < 0)
            return;
        const index = jobIndex(id);
        if (index < 0 || !["queued", "running"].includes(jobs[index].status))
            return;
        patchJob(id, {
            "status": "cancelling",
            "message": "Cancelling"
        });
        backendProcess.write(JSON.stringify({
            "id": id,
            "op": "cancel"
        }) + "\n");
    }
    function clearSelection() {
        setSelection([]);
        currentIndex = -1;
        currentItemPath = "";
        selectionAnchor = -1;
    }
    function commitNavigation(path, mode, targetHistoryIndex) {
        const normalized = normalizePath(path);
        if (mode === "reset") {
            historyPaths = [normalized];
            historyIndex = 0;
        } else if (mode === "history") {
            historyIndex = targetHistoryIndex;
        } else if (normalized !== currentPath || historyIndex < 0) {
            const next = historyPaths.slice(0, historyIndex + 1);
            next.push(normalized);
            historyPaths = next;
            historyIndex = next.length - 1;
        }
        currentPath = normalized;
        modelFolder = fileUrl(normalized);
        pathEditMode = false;
        searchField.text = "";
        searchText = "";
        appliedSearchText = "";
        clearSelection();
        scheduleSettingsSave();
    }
    function copyPaths() {
        if (selection.length > 0)
            Quickshell.clipboardText = selectedPaths().join("\n");
    }
    function copySelection(cut) {
        if (!backendReady || selection.length === 0)
            return;
        setFileClipboard(selectedPaths(), cut);
        setStatus(selection.length + (cut ? " item(s) ready to move" : " item(s) ready to copy"), false);
    }
    function createItem(directory) {
        if (!backendReady)
            return;
        inputModal.showWithOptions({
            "title": directory ? "New Folder" : "New File",
            "message": "Create in " + currentPath,
            "placeholder": directory ? "Folder name" : "File name",
            "confirmText": "Create",
            "onConfirm": name => {
                const cleanName = String(name || "").trim();
                if (!validName(cleanName)) {
                    setStatus("Names cannot be empty or contain '/'", true);
                    return;
                }
                submitJob({
                    "op": directory ? "mkdir" : "touch",
                    "destination": joinPath(currentPath, cleanName)
                });
            }
        });
    }
    function createMenuItems() {
        return blankMenuItems().slice(0, 2);
    }
    function duplicateSelection() {
        if (!backendReady || selection.length === 0)
            return;
        submitJob({
            "op": "copy",
            "sources": selectedPaths(),
            "destination": currentPath,
            "policy": "rename"
        });
    }
    function ensureCurrentVisible() {
        if (currentIndex < 0)
            return;
        if (viewMode === "grid")
            fileGrid.positionViewAtIndex(currentIndex, GridView.Contain);
        else
            fileList.positionViewAtIndex(currentIndex, ListView.Contain);
    }
    function fileUrl(path) {
        if (!path)
            return "";
        if (String(path).startsWith("file:"))
            return String(path);
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }
    function finishJob(id, event) {
        const record = requestRecords[id];
        const index = jobIndex(id);
        const job = index >= 0 ? jobs[index] : null;
        const status = event.status || "error";
        if (status === "ok") {
            patchJob(id, {
                "status": "ok",
                "itemsDone": job?.itemsTotal || 1,
                "message": "Completed"
            });
            removeRequest(id);
            if (record?.options?.clearClipboard)
                setFileClipboard([], false);
            removeSelectionPaths(record?.options?.removeSelection || []);
            refreshFolder();
            setStatus((job?.label || "File operation") + " completed", false);
            if (typeof record?.options?.afterOk === "function")
                Qt.callLater(record.options.afterOk);
        } else if (status === "cancelled") {
            patchJob(id, {
                "status": "cancelled",
                "message": event.message || "Cancelled"
            });
            reconcilePartialJob(record, job);
            removeRequest(id);
            setStatus((job?.label || "File operation") + " cancelled", false);
        } else if (status === "conflict") {
            patchJob(id, {
                "status": "conflict",
                "message": event.message || "Destination exists"
            });
            reconcilePartialJob(record, job);
            queueConflict(id);
        } else {
            patchJob(id, {
                "status": "error",
                "message": event.message || "Operation failed"
            });
            reconcilePartialJob(record, job);
            removeRequest(id);
            setStatus(event.message || "File operation failed", true);
        }
        if (activeJobs === 0)
            jobHideTimer.restart();
    }
    function focusWindow() {
        if (typeof requestActivate === "function")
            requestActivate();
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
    function goBack() {
        if (historyIndex > 0)
            requestNavigation(historyPaths[historyIndex - 1], "history", historyIndex - 1, false);
    }
    function goForward() {
        if (historyIndex >= 0 && historyIndex < historyPaths.length - 1)
            requestNavigation(historyPaths[historyIndex + 1], "history", historyIndex + 1, false);
    }
    function handleBackendExit(exitCode) {
        backendReady = false;
        const nextJobs = jobs.slice();
        for (let i = 0; i < nextJobs.length; ++i) {
            if (["queued", "running", "cancelling"].includes(nextJobs[i].status))
                nextJobs[i] = Object.assign({}, nextJobs[i], {
                    "status": "error",
                    "message": "Backend stopped"
                });
        }
        jobs = nextJobs;
        requestRecords = ({});
        conflictEvents = ({});
        conflictQueue = [];
        currentConflict = null;
        setStatus("File operations backend stopped" + (exitCode ? " (exit " + exitCode + ")" : ""), true);
        backendRestartTimer.restart();
    }
    function handleBackendLine(line) {
        const value = String(line || "").trim();
        if (!value)
            return;
        let event;
        try {
            event = JSON.parse(value);
        } catch (error) {
            setStatus("Backend returned invalid data", true);
            return;
        }

        if (event.event === "ready") {
            backendReady = true;
            return;
        }
        const id = Number(event.id);
        if (!Number.isFinite(id))
            return;

        switch (event.event) {
        case "started":
            patchJob(id, {
                "status": "running"
            });
            break;
        case "progress":
            patchJob(id, {
                "status": "running",
                "itemsDone": Number(event.itemsDone || 0),
                "itemsTotal": Number(event.itemsTotal || 1),
                "bytesDone": Number(event.bytesDone || 0),
                "bytesTotal": Number(event.bytesTotal || 0),
                "current": pathFromUrl(event.current || "")
            });
            break;
        case "conflict":
            {
                const conflicts = Object.assign({}, conflictEvents);
                conflicts[id] = event;
                conflictEvents = conflicts;
                break;
            }
        case "rejected":
            rejectJob(id, event);
            break;
        case "finished":
            finishJob(id, event);
            break;
        }
    }
    function handleDrop(urls, destination, action) {
        if (!backendReady)
            return false;
        if (action !== Qt.CopyAction && action !== Qt.MoveAction)
            return false;
        const sources = [];
        for (const url of urls) {
            const value = String(url || "");
            if (!value.startsWith("file:///")) {
                setStatus("Only local file drops are supported", true);
                return false;
            }
            const path = pathFromUrl(value);
            if (!path) {
                setStatus("Only local file drops are supported", true);
                return false;
            }
            if (!sources.includes(path))
                sources.push(path);
        }
        if (sources.length === 0) {
            setStatus("Only local file drops are supported", true);
            return false;
        }
        return submitJob({
            "op": action === Qt.MoveAction ? "move" : "copy",
            "sources": sources,
            "destination": destination,
            "policy": "ask"
        }) >= 0;
    }
    function handleKey(event) {
        if (currentConflict) {
            event.accepted = true;
            return;
        }

        const control = !!(event.modifiers & Qt.ControlModifier);
        const shift = !!(event.modifiers & Qt.ShiftModifier);
        const alt = !!(event.modifiers & Qt.AltModifier);

        if (control && shift && event.key === Qt.Key_N) {
            createItem(true);
            event.accepted = true;
            return;
        }
        if (control && shift && event.key === Qt.Key_T) {
            createItem(false);
            event.accepted = true;
            return;
        }
        if (control) {
            switch (event.key) {
            case Qt.Key_A:
                selectAll();
                event.accepted = true;
                return;
            case Qt.Key_C:
                copySelection(false);
                event.accepted = true;
                return;
            case Qt.Key_X:
                copySelection(true);
                event.accepted = true;
                return;
            case Qt.Key_V:
                paste(currentPath);
                event.accepted = true;
                return;
            case Qt.Key_L:
                showPathEditor();
                event.accepted = true;
                return;
            case Qt.Key_F:
                showSearch();
                event.accepted = true;
                return;
            case Qt.Key_H:
                showHidden = !showHidden;
                clearSelection();
                scheduleSettingsSave();
                event.accepted = true;
                return;
            case Qt.Key_I:
                showProperties(selection);
                event.accepted = true;
                return;
            }
        }
        if (alt) {
            switch (event.key) {
            case Qt.Key_Left:
                goBack();
                event.accepted = true;
                return;
            case Qt.Key_Right:
                goForward();
                event.accepted = true;
                return;
            case Qt.Key_Up:
                navigateUp();
                event.accepted = true;
                return;
            case Qt.Key_Home:
                requestNavigation(homePath, "push", -1, false);
                event.accepted = true;
                return;
            }
        }

        switch (event.key) {
        case Qt.Key_Left:
            moveCursor(viewMode === "grid" ? -1 : 0, shift);
            event.accepted = true;
            break;
        case Qt.Key_Right:
            moveCursor(viewMode === "grid" ? 1 : 0, shift);
            event.accepted = true;
            break;
        case Qt.Key_Up:
            moveCursor(viewMode === "grid" ? -gridColumns : -1, shift);
            event.accepted = true;
            break;
        case Qt.Key_Down:
            moveCursor(viewMode === "grid" ? gridColumns : 1, shift);
            event.accepted = true;
            break;
        case Qt.Key_Home:
            moveCursorTo(0, shift);
            event.accepted = true;
            break;
        case Qt.Key_End:
            moveCursorTo(folderModel.count - 1, shift);
            event.accepted = true;
            break;
        case Qt.Key_PageUp:
            moveCursor(-pageStep(), shift);
            event.accepted = true;
            break;
        case Qt.Key_PageDown:
            moveCursor(pageStep(), shift);
            event.accepted = true;
            break;
        case Qt.Key_Space:
            if (currentIndex < 0 && folderModel.count > 0)
                selectIndex(0, Qt.NoModifier);
            else if (currentIndex >= 0)
                selectIndex(currentIndex, Qt.ControlModifier);
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (currentIndex >= 0)
                activateCurrentItem();
            event.accepted = true;
            break;
        case Qt.Key_Escape:
            if (pathEditMode) {
                pathEditMode = false;
            } else if (searchVisible) {
                searchText = "";
                searchField.text = "";
                searchVisible = false;
            } else if (selection.length > 0) {
                clearSelection();
            } else {
                hide();
            }
            event.accepted = true;
            break;
        case Qt.Key_Backspace:
            navigateUp();
            event.accepted = true;
            break;
        case Qt.Key_F2:
            renameSelection();
            event.accepted = true;
            break;
        case Qt.Key_F5:
            refreshFolder();
            event.accepted = true;
            break;
        case Qt.Key_Delete:
            if (shift)
                permanentlyDeleteSelection();
            else
                trashSelection();
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            showKeyboardMenu();
            event.accepted = true;
            break;
        case Qt.Key_F6:
            if (placesList.rowCount() > 0)
                placesList.forceActiveFocus();
            event.accepted = true;
            break;
        }
    }
    function hide() {
        visible = false;
    }
    function indexAtPosition(x, y) {
        const view = viewMode === "grid" ? fileGrid : fileList;
        if (!view)
            return -1;
        const local = viewArea.mapFromItem(blankArea, x, y);
        const idx = view.indexAt(local.x - view.x, local.y - view.y);
        return idx;
    }
    function isCut(path) {
        return !!fileClipboard.cut && cutPathMap[path] === true;
    }
    function isSelected(path) {
        return selectedPathMap[path] !== undefined;
    }
    function itemAt(index) {
        if (index < 0 || index >= folderModel.count)
            return null;
        return {
            "path": String(folderModel.get(index, "filePath") || ""),
            "name": String(folderModel.get(index, "fileName") || ""),
            "isDir": !!folderModel.get(index, "fileIsDir"),
            "size": Number(folderModel.get(index, "fileSize") || 0),
            "modified": folderModel.get(index, "fileModified"),
            "suffix": String(folderModel.get(index, "fileSuffix") || "")
        };
    }
    function itemMenuItems() {
        const hasFiles = selection.some(item => !item.isDir);
        return [
            {
                "text": "Open",
                "icon": "open_in_new",
                "shortcut": "Enter",
                "enabled": selection.length > 0,
                "action": activateSelection
            },
            {
                "text": "Open With...",
                "icon": "apps",
                "enabled": hasFiles,
                "action": openWithSelection
            },
            {
                "type": "separator"
            },
            {
                "text": "Cut",
                "icon": "content_cut",
                "shortcut": "Ctrl+X",
                "enabled": operationEnabled(),
                "action": () => copySelection(true)
            },
            {
                "text": "Copy",
                "icon": "content_copy",
                "shortcut": "Ctrl+C",
                "enabled": operationEnabled(),
                "action": () => copySelection(false)
            },
            {
                "text": "Paste Into Folder",
                "icon": "content_paste",
                "shortcut": "Ctrl+V",
                "enabled": backendReady && fileClipboard.sources.length > 0,
                "action": () => paste(selection.length === 1 && selection[0].isDir ? selection[0].path : currentPath)
            },
            {
                "text": "Rename",
                "icon": "drive_file_rename_outline",
                "shortcut": "F2",
                "enabled": backendReady && selection.length === 1,
                "action": renameSelection
            },
            {
                "text": "Duplicate",
                "icon": "file_copy",
                "enabled": operationEnabled(),
                "action": duplicateSelection
            },
            {
                "type": "separator"
            },
            {
                "text": "Move to Trash",
                "icon": "delete",
                "shortcut": "Delete",
                "enabled": operationEnabled(),
                "action": trashSelection
            },
            {
                "text": "Delete Permanently",
                "icon": "delete_forever",
                "shortcut": "Shift+Delete",
                "enabled": operationEnabled(),
                "dangerous": true,
                "action": permanentlyDeleteSelection
            },
            {
                "type": "separator"
            },
            {
                "text": "Copy Path",
                "icon": "link",
                "enabled": selection.length > 0,
                "action": copyPaths
            },
            {
                "text": "Properties",
                "icon": "info",
                "shortcut": "Ctrl+I",
                "enabled": selection.length > 0,
                "action": () => showProperties(selection)
            }
        ];
    }
    function jobIndex(id) {
        return jobs.findIndex(job => job.id === id);
    }
    function jobLabel(request) {
        const count = request.sources?.length || 1;
        switch (request.op) {
        case "mkdir":
            return "Create folder";
        case "touch":
            return "Create file";
        case "rename":
            return "Rename";
        case "copy":
            return "Copy " + count + " item(s)";
        case "move":
            return "Move " + count + " item(s)";
        case "trash":
            return "Trash " + count + " item(s)";
        case "delete":
            return "Delete " + count + " item(s)";
        default:
            return "File operation";
        }
    }
    function joinPath(directory, name) {
        return directory === "/" ? "/" + name : directory + "/" + name;
    }
    function loadSettings() {
        const settings = CacheData.fileBrowserSettings?.fileManager || {};
        viewMode = settings.viewMode === "grid" ? "grid" : "list";
        sortBy = ["name", "size", "modified", "type"].includes(settings.sortBy) ? settings.sortBy : "name";
        sortAscending = settings.sortAscending !== undefined ? !!settings.sortAscending : true;
        showSidebar = settings.showSidebar !== undefined ? !!settings.showSidebar : true;
        showHidden = settings.showHidden !== undefined ? !!settings.showHidden : false;
        settingsLoaded = true;
        requestNavigation(settings.lastPath || homePath, "reset", -1, true);
    }
    function moveCursor(delta, extend) {
        if (folderModel.count === 0)
            return;
        const start = currentIndex >= 0 ? currentIndex : (delta < 0 ? folderModel.count : -1);
        const target = Math.max(0, Math.min(folderModel.count - 1, start + delta));
        selectIndex(target, extend ? Qt.ShiftModifier : Qt.NoModifier);
    }
    function moveCursorTo(index, extend) {
        if (folderModel.count === 0)
            return;
        selectIndex(Math.max(0, Math.min(folderModel.count - 1, index)), extend ? Qt.ShiftModifier : Qt.NoModifier);
    }
    function navigateUp() {
        if (currentPath !== "/")
            requestNavigation(parentPath(currentPath), "push", -1, false);
    }
    function normalizePath(value) {
        let path = String(value || "").trim();
        if (!path)
            return "";
        if (path.startsWith("file://")) {
            try {
                path = decodeURIComponent(path.slice(7));
            } catch (error) {
                return "";
            }
        }
        if (path === "~")
            path = String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "");
        else if (path.startsWith("~/"))
            path = String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "") + path.slice(1);
        if (!path.startsWith("/"))
            path = (currentPath || "/") + "/" + path;

        const parts = [];
        for (const part of path.split("/")) {
            if (!part || part === ".")
                continue;
            if (part === "..") {
                if (parts.length > 0)
                    parts.pop();
            } else {
                parts.push(part);
            }
        }
        return "/" + parts.join("/");
    }
    function openWithSelection() {
        for (const item of selection) {
            if (!item.isDir)
                Quickshell.execDetached(["dms", "open", item.path, "--type", "file"]);
        }
    }
    function operationEnabled() {
        return backendReady && selection.length > 0;
    }
    function pageStep() {
        if (viewMode === "grid")
            return gridColumns * Math.max(1, Math.floor(fileGrid.height / gridCellHeight) - 1);
        return Math.max(1, Math.floor(fileList.height / 44) - 1);
    }
    function parentPath(path) {
        const normalized = normalizePath(path);
        if (!normalized || normalized === "/")
            return "/";
        const slash = normalized.lastIndexOf("/");
        return slash <= 0 ? "/" : normalized.slice(0, slash);
    }
    function paste(destination) {
        if (!backendReady || !fileClipboard.sources || fileClipboard.sources.length === 0)
            return;
        submitJob({
            "op": fileClipboard.cut ? "move" : "copy",
            "sources": fileClipboard.sources.slice(),
            "destination": destination || currentPath,
            "policy": "ask"
        }, {
            "clearClipboard": !!fileClipboard.cut
        });
    }
    function patchJob(id, values) {
        const index = jobIndex(id);
        if (index < 0)
            return;
        const next = jobs.slice();
        next[index] = Object.assign({}, next[index], values);
        jobs = next;
    }
    function pathFromUrl(value) {
        return normalizePath(String(value || ""));
    }
    function permanentlyDeleteSelection() {
        if (!backendReady || selection.length === 0)
            return;
        const paths = selectedPaths();
        confirmModal.showWithOptions({
            "title": "Delete Permanently?",
            "message": "Delete " + paths.length + " item(s)? This cannot be undone.",
            "confirmText": "Delete",
            "confirmColor": Theme.error,
            "onConfirm": () => submitJob({
                    "op": "delete",
                    "sources": paths
                }, {
                    "removeSelection": paths
                })
        });
    }
    function promptConflictRename(conflict, request, options) {
        const destination = pathFromUrl(conflict.event.destination || request.destination);
        inputModal.showWithOptions({
            "title": "Choose Another Name",
            "message": "An item with this name already exists",
            "initialText": basename(destination) + " copy",
            "confirmText": "Retry",
            "onConfirm": name => {
                const cleanName = String(name || "").trim();
                if (!validName(cleanName)) {
                    setStatus("Names cannot be empty or contain '/'", true);
                } else {
                    request.destination = joinPath(parentPath(destination), cleanName);
                    submitJob(request, options);
                }
                Qt.callLater(showNextConflict);
            },
            "onCancel": () => Qt.callLater(showNextConflict)
        });
    }
    function propertiesText() {
        if (propertyItems.length === 0)
            return "";
        if (propertyItems.length === 1) {
            const item = propertyItems[0];
            const lines = ["Name: " + item.name, "Type: " + (item.isDir ? "Folder" : (item.suffix ? item.suffix.toUpperCase() + " file" : "File")), "Location: " + parentPath(item.path)];
            if (!item.isDir)
                lines.push("Size: " + formatSize(item.size));
            if (item.modified)
                lines.push("Modified: " + Qt.formatDateTime(item.modified, "yyyy-MM-dd HH:mm:ss"));
            lines.push("Path: " + item.path);
            return lines.join("\n");
        }
        let bytes = 0;
        const paths = [];
        for (const item of propertyItems) {
            if (!item.isDir)
                bytes += Number(item.size) || 0;
            if (paths.length < 8)
                paths.push(item.path);
        }
        let text = propertyItems.length + " items\nFile sizes: " + formatSize(bytes) + "\n\n" + paths.join("\n");
        if (propertyItems.length > paths.length)
            text += "\n...and " + (propertyItems.length - paths.length) + " more";
        return text;
    }
    function queueConflict(id) {
        const record = requestRecords[id];
        if (!record)
            return;
        const event = conflictEvents[id] || {
            "source": record.request.source || record.request.sources?.[0] || "",
            "destination": record.request.destination || ""
        };
        const next = conflictQueue.slice();
        next.push({
            "id": id,
            "record": record,
            "event": event
        });
        conflictQueue = next;
        showNextConflict();
    }
    function reconcilePartialJob(record, job) {
        const request = record?.request;
        if (!request || !["move", "trash", "delete"].includes(request.op))
            return;

        const sources = request.sources || [];
        const completedCount = Math.max(0, Math.min(sources.length, Math.floor(Number(job?.itemsDone || 0))));
        const completed = sources.slice(0, completedCount);
        removeSelectionPaths(completed);

        if (fileClipboard.cut && completed.length > 0) {
            const completedPaths = {};
            for (const path of completed)
                completedPaths[path] = true;
            const remaining = fileClipboard.sources.filter(path => !completedPaths[path]);
            setFileClipboard(remaining, remaining.length > 0);
        }
        refreshFolder();
    }
    function refreshFolder() {
        modelFolder = "";
        reloadFolderTimer.restart();
    }
    function rejectJob(id, event) {
        if (requestRecords[id] === undefined || jobIndex(id) < 0)
            return;
        patchJob(id, {
            "status": "error",
            "message": event.message || "Request rejected"
        });
        removeRequest(id);
        setStatus(event.message || "File operation request was rejected", true);
        if (activeJobs === 0)
            jobHideTimer.restart();
    }
    function removeRequest(id) {
        const records = Object.assign({}, requestRecords);
        delete records[id];
        requestRecords = records;
        const conflicts = Object.assign({}, conflictEvents);
        delete conflicts[id];
        conflictEvents = conflicts;
    }
    function removeSelectionPaths(paths) {
        if (!paths || paths.length === 0)
            return;
        const removed = {};
        for (const path of paths)
            removed[path] = true;
        const next = selection.filter(item => !removed[item.path]);
        setSelection(next);
        if (next.length === 0) {
            currentIndex = -1;
            currentItemPath = "";
            selectionAnchor = -1;
        } else if (removed[currentItemPath]) {
            currentItemPath = next[0].path;
            currentIndex = folderModel.indexOf(fileUrl(currentItemPath));
            selectionAnchor = -1;
        }
    }
    function renameSelection() {
        if (!backendReady || selection.length !== 1)
            return;
        const item = selection[0];
        inputModal.showWithOptions({
            "title": "Rename",
            "message": "Enter a new name",
            "initialText": item.name,
            "confirmText": "Rename",
            "onConfirm": name => {
                const cleanName = String(name || "").trim();
                if (!validName(cleanName)) {
                    setStatus("Names cannot be empty or contain '/'", true);
                    return;
                }
                if (cleanName === item.name)
                    return;
                submitJob({
                    "op": "rename",
                    "source": item.path,
                    "destination": joinPath(parentPath(item.path), cleanName)
                }, {
                    "removeSelection": [item.path]
                });
            }
        });
    }
    function requestNavigation(path, mode, targetHistoryIndex, fallbackHome) {
        const normalized = normalizePath(path);
        if (!normalized) {
            setStatus("Invalid folder path", true);
            return;
        }
        queuedNavigation = {
            "path": normalized,
            "mode": mode || "push",
            "historyIndex": targetHistoryIndex ?? -1,
            "fallbackHome": !!fallbackHome
        };
        startNavigationProbe();
    }
    function resolveConflict(policy) {
        const conflict = currentConflict;
        if (!conflict)
            return;
        currentConflict = null;
        const request = JSON.parse(JSON.stringify(conflict.record.request));
        const options = conflict.record.options || {};
        const oldJob = jobs[jobIndex(conflict.id)];
        removeRequest(conflict.id);

        if (request.op === "copy" || request.op === "move") {
            const completed = Math.max(0, Number(oldJob?.itemsDone || 0));
            request.sources = request.sources.slice(completed);
            request.policy = policy;
            request.policyOnce = true;
            submitJob(request, options);
            Qt.callLater(showNextConflict);
            return;
        }

        if (policy === "rename") {
            promptConflictRename(conflict, request, options);
        } else {
            setStatus("Conflict skipped", false);
            Qt.callLater(showNextConflict);
        }
    }
    function saveSettings() {
        if (!settingsLoaded)
            return;
        const allSettings = Object.assign({}, CacheData.fileBrowserSettings || {});
        allSettings.fileManager = {
            "lastPath": currentPath,
            "viewMode": viewMode,
            "sortBy": sortBy,
            "sortAscending": sortAscending,
            "showSidebar": showSidebar,
            "showHidden": showHidden
        };
        CacheData.fileBrowserSettings = allSettings;
        CacheData.saveCache();
    }
    function scheduleSettingsSave() {
        if (settingsLoaded)
            settingsSaveTimer.restart();
    }
    function selectAll() {
        const next = [];
        for (let i = 0; i < folderModel.count; ++i) {
            const item = itemAt(i);
            if (item)
                next.push(item);
        }
        setSelection(next);
        if (folderModel.count > 0) {
            currentIndex = Math.max(0, Math.min(folderModel.count - 1, currentIndex));
            currentItemPath = itemAt(currentIndex)?.path || "";
            selectionAnchor = currentIndex;
        }
    }
    function selectIndex(index, modifiers) {
        const item = itemAt(index);
        if (!item)
            return;
        const control = !!(modifiers & Qt.ControlModifier);
        const shift = !!(modifiers & Qt.ShiftModifier);
        currentIndex = index;
        currentItemPath = item.path;

        if (shift && selectionAnchor >= 0) {
            const first = Math.min(selectionAnchor, index);
            const last = Math.max(selectionAnchor, index);
            const next = control ? selection.slice() : [];
            for (let i = first; i <= last; ++i) {
                const candidate = itemAt(i);
                if (candidate && (!control || selectedPathMap[candidate.path] === undefined))
                    next.push(candidate);
            }
            setSelection(next);
        } else if (control) {
            const existing = selectedPathMap[item.path];
            const next = selection.slice();
            if (existing !== undefined)
                next.splice(existing, 1);
            else
                next.push(item);
            setSelection(next);
            selectionAnchor = index;
        } else {
            setSelection([item]);
            selectionAnchor = index;
        }
        ensureCurrentVisible();
    }
    function selectedPaths() {
        return selection.map(item => item.path);
    }
    function setFileClipboard(sources, cut) {
        const pathMap = {};
        if (cut) {
            for (const path of sources)
                pathMap[path] = true;
        }
        cutPathMap = pathMap;
        fileClipboard = {
            "sources": sources,
            "cut": !!cut
        };
    }
    function setSelection(items) {
        const pathMap = {};
        const dragUrls = [];
        for (let i = 0; i < items.length; ++i) {
            pathMap[items[i].path] = i;
            dragUrls.push(fileUrl(items[i].path));
        }
        selection = items;
        selectedPathMap = pathMap;
        selectedDragUrls = dragUrls;
    }
    function setSort(field) {
        if (sortBy === field)
            sortAscending = !sortAscending;
        else {
            sortBy = field;
            sortAscending = true;
        }
        clearSelection();
        scheduleSettingsSave();
    }
    function setStatus(message, error) {
        statusMessage = message || "";
        statusIsError = !!error;
        if (statusMessage)
            statusClearTimer.restart();
    }
    function show() {
        visible = true;
        focusWindow();
        Qt.callLater(() => contentRoot.forceActiveFocus());
    }
    function showKeyboardMenu() {
        const menuItems = selection.length > 0 ? itemMenuItems() : blankMenuItems();
        actionMenu.showAt(contentRoot, Math.max(16, contentRoot.width / 2 - 136), Math.max(16, contentRoot.height / 2 - 120), menuItems, true);
    }
    function showMenuForItem(sender, x, y, index) {
        if (!isSelected(String(folderModel.get(index, "filePath") || "")))
            selectIndex(index, Qt.NoModifier);
        const point = sender.mapToItem(contentRoot, x, y);
        actionMenu.showAt(contentRoot, point.x, point.y, itemMenuItems(), false);
    }
    function showNextConflict() {
        if (currentConflict)
            return;
        if (conflictQueue.length === 0) {
            if (visible)
                contentRoot.forceActiveFocus();
            return;
        }
        const next = conflictQueue.slice();
        currentConflict = next.shift();
        conflictQueue = next;
        Qt.callLater(() => conflictDialog.forceActiveFocus());
    }
    function showPath(path) {
        if (!normalizePath(path))
            return false;
        show();
        requestNavigation(path, "push", -1, false);
        return true;
    }
    function showPathEditor() {
        pathEditMode = true;
        pathField.text = currentPath;
        Qt.callLater(() => {
            pathField.forceActiveFocus();
            pathField.selectAll();
        });
    }
    function showProperties(items) {
        propertyItems = items && items.length > 0 ? items.slice() : [
            {
                "path": currentPath,
                "name": basename(currentPath),
                "isDir": true,
                "size": 0,
                "modified": null,
                "suffix": ""
            }
        ];
        propertiesPopup.open();
    }
    function showSearch() {
        searchVisible = true;
        Qt.callLater(() => {
            searchField.forceActiveFocus();
            searchField.selectAll();
        });
    }
    function sortMenuItems() {
        const result = [];
        for (const option of [
            {
                "name": "Name",
                "value": "name"
            },
            {
                "name": "Size",
                "value": "size"
            },
            {
                "name": "Modified",
                "value": "modified"
            },
            {
                "name": "Type",
                "value": "type"
            }
        ]) {
            const value = option.value;
            result.push({
                "text": option.name,
                "icon": sortBy === value ? "check" : "",
                "action": () => setSort(value)
            });
        }
        result.push({
            "type": "separator"
        });
        result.push({
            "text": sortAscending ? "Ascending" : "Descending",
            "icon": sortAscending ? "arrow_upward" : "arrow_downward",
            "action": () => {
                sortAscending = !sortAscending;
                clearSelection();
                scheduleSettingsSave();
            }
        });
        return result;
    }
    function startNavigationProbe() {
        if (pathProbe.running || !queuedNavigation)
            return;
        pathProbe.navigation = queuedNavigation;
        queuedNavigation = null;
        pathProbe.exec(["test", "-d", pathProbe.navigation.path, "-a", "-r", pathProbe.navigation.path, "-a", "-x", pathProbe.navigation.path]);
    }
    function statusJson() {
        return JSON.stringify({
            "visible": visible,
            "path": currentPath,
            "items": folderModel.count,
            "selected": selection.length,
            "backendReady": backendReady,
            "activeJobs": activeJobs
        });
    }
    function submitJob(request, options) {
        if (!backendReady) {
            setStatus("File operations backend is unavailable", true);
            return -1;
        }
        const cleanRequest = JSON.parse(JSON.stringify(request));
        const id = nextRequestId++;
        const wireRequest = Object.assign({
            "id": id
        }, cleanRequest);
        const records = Object.assign({}, requestRecords);
        records[id] = {
            "request": cleanRequest,
            "options": options || {}
        };
        requestRecords = records;

        const nextJobs = jobs.slice();
        nextJobs.push({
            "id": id,
            "request": cleanRequest,
            "label": options?.label || jobLabel(cleanRequest),
            "status": "queued",
            "itemsDone": 0,
            "itemsTotal": cleanRequest.sources?.length || 1,
            "bytesDone": 0,
            "bytesTotal": 0,
            "current": "",
            "message": ""
        });
        jobs = nextJobs.length > 40 ? nextJobs.slice(nextJobs.length - 40) : nextJobs;
        showJobBar = true;
        jobHideTimer.stop();
        backendProcess.write(JSON.stringify(wireRequest) + "\n");
        return id;
    }
    function supportsDrop(event) {
        if (!backendReady || !event.hasUrls || !(event.supportedActions & Qt.CopyAction))
            return false;
        if (event.proposedAction !== Qt.CopyAction && event.proposedAction !== Qt.MoveAction)
            return false;
        if (!(event.supportedActions & event.proposedAction) || event.urls.length === 0)
            return false;
        for (let i = 0; i < event.urls.length; ++i) {
            if (!String(event.urls[i]).startsWith("file:///"))
                return false;
        }
        return true;
    }
    function syncCurrentIndex() {
        if (!currentItemPath)
            return;
        const index = folderModel.indexOf(fileUrl(currentItemPath));
        if (index < 0) {
            clearSelection();
            return;
        }
        currentIndex = index;
        selectionAnchor = -1;
    }
    function toggle() {
        visible = !visible;
        if (visible) {
            focusWindow();
            Qt.callLater(() => contentRoot.forceActiveFocus());
        }
    }
    function trashSelection() {
        if (!backendReady || selection.length === 0)
            return;
        const paths = selectedPaths();
        submitJob({
            "op": "trash",
            "sources": paths
        }, {
            "removeSelection": paths
        });
    }
    function validName(name) {
        const value = String(name || "").trim();
        return value.length > 0 && value !== "." && value !== ".." && !value.includes("/");
    }

    color: Theme.surfaceContainer
    implicitHeight: 720
    implicitWidth: 1080
    minimumSize: Qt.size(360, 400)
    objectName: "dmsFileManager"
    title: "DMS Files"
    visible: false

    Component.onCompleted: loadSettings()
    onClosed: hide()
    onCurrentPathChanged: scheduleSettingsSave()
    onSearchTextChanged: {
        searchDebounce.restart();
        clearSelection();
    }
    onShowHiddenChanged: scheduleSettingsSave()
    onShowSidebarChanged: scheduleSettingsSave()
    onSortAscendingChanged: scheduleSettingsSave()
    onSortByChanged: scheduleSettingsSave()
    onViewModeChanged: scheduleSettingsSave()
    onVisibleChanged: {
        if (visible)
            Qt.callLater(() => contentRoot.forceActiveFocus());
    }

    Timer {
        id: settingsSaveTimer

        interval: 700

        onTriggered: root.saveSettings()
    }
    Timer {
        id: searchDebounce

        interval: 80

        onTriggered: root.appliedSearchText = root.searchText.trim()
    }
    Timer {
        id: statusClearTimer

        interval: 5000

        onTriggered: root.statusMessage = ""
    }
    Timer {
        id: reloadFolderTimer

        interval: 1

        onTriggered: root.modelFolder = root.fileUrl(root.currentPath)
    }
    Timer {
        id: jobHideTimer

        interval: 4500

        onTriggered: {
            if (root.activeJobs === 0)
                root.showJobBar = false;
        }
    }
    Timer {
        id: backendRestartTimer

        interval: 1500

        onTriggered: {
            if (!backendProcess.running)
                backendProcess.running = true;
        }
    }
    Process {
        id: pathProbe

        property var navigation: null

        running: false

        onExited: exitCode => {
            const navigation = pathProbe.navigation;
            pathProbe.navigation = null;
            if (navigation) {
                if (exitCode === 0) {
                    root.commitNavigation(navigation.path, navigation.mode, navigation.historyIndex);
                } else if (navigation.fallbackHome && navigation.path !== root.homePath) {
                    root.setStatus("Last folder is unavailable. Opened Home instead.", true);
                    root.commitNavigation(root.homePath, "reset", -1);
                } else {
                    root.setStatus("Folder does not exist or is not accessible: " + navigation.path, true);
                }
            }
            Qt.callLater(root.startNavigationProbe);
        }
    }
    Process {
        id: backendProcess

        command: ["dms-files-backend"]
        running: true
        stdinEnabled: true

        stderr: SplitParser {
            splitMarker: "\n"

            onRead: line => console.warn("dms-files-backend:", line)
        }
        stdout: SplitParser {
            splitMarker: "\n"

            onRead: line => root.handleBackendLine(line)
        }

        onExited: exitCode => root.handleBackendExit(exitCode)
        onStarted: root.backendReady = false
    }
    FolderListModel {
        id: folderModel

        caseSensitive: false
        folder: root.modelFolder
        nameFilters: root.appliedSearchText ? ["*" + root.appliedSearchText + "*"] : ["*"]
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showFiles: true
        showHidden: root.showHidden
        showOnlyReadable: true
        sortCaseSensitive: false
        sortField: {
            switch (root.sortBy) {
            case "size":
                return FolderListModel.Size;
            case "modified":
                return FolderListModel.Time;
            case "type":
                return FolderListModel.Type;
            default:
                return FolderListModel.Name;
            }
        }
        sortReversed: !root.sortAscending

        onStatusChanged: {
            if (status === FolderListModel.Ready)
                root.syncCurrentIndex();
        }
    }
    FocusScope {
        id: contentRoot

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => root.handleKey(event)

        Rectangle {
            id: titleBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            color: Theme.surfaceContainer
            height: 44

            MouseArea {
                anchors.fill: parent

                onDoubleClicked: windowControls.tryToggleMaximize()
                onPressed: windowControls.tryStartMove()
            }
            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.primary
                    name: "folder"
                    size: Theme.iconSize
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    text: "Files"
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DankActionButton {
                    Accessible.name: tooltipText
                    Accessible.role: Accessible.Button
                    circular: false
                    iconName: root.maximized ? "fullscreen_exit" : "fullscreen"
                    tooltipText: root.maximized ? "Restore" : "Maximise"
                    visible: windowControls.canMaximize

                    onClicked: windowControls.tryToggleMaximize()
                }
                DankActionButton {
                    Accessible.name: tooltipText
                    Accessible.role: Accessible.Button
                    circular: false
                    iconName: "close"
                    tooltipText: "Close"

                    onClicked: root.hide()
                }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBar.bottom
            color: Theme.outline
            height: 1
        }
        Rectangle {
            id: navigationBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBar.bottom
            anchors.topMargin: 1
            color: Theme.surfaceContainer
            height: 44

            Row {
                id: navigationButtons

                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                DankActionButton {
                    Accessible.name: tooltipText
                    Accessible.role: Accessible.Button
                    circular: false
                    enabled: root.historyIndex > 0
                    iconName: "arrow_back"
                    tooltipText: "Back (Alt+Left)"

                    onClicked: root.goBack()
                }
                DankActionButton {
                    Accessible.name: tooltipText
                    Accessible.role: Accessible.Button
                    circular: false
                    enabled: root.historyIndex >= 0 && root.historyIndex < root.historyPaths.length - 1
                    iconName: "arrow_forward"
                    tooltipText: "Forward (Alt+Right)"

                    onClicked: root.goForward()
                }
                DankActionButton {
                    Accessible.name: tooltipText
                    Accessible.role: Accessible.Button
                    circular: false
                    enabled: root.currentPath !== "/"
                    iconName: "arrow_upward"
                    tooltipText: "Parent (Alt+Up)"

                    onClicked: root.navigateUp()
                }
                DankActionButton {
                    Accessible.name: tooltipText
                    Accessible.role: Accessible.Button
                    circular: false
                    iconName: "home"
                    tooltipText: "Home (Alt+Home)"

                    onClicked: root.requestNavigation(root.homePath, "push", -1, false)
                }
            }
            Rectangle {
                id: locationBox

                anchors.left: navigationButtons.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: refreshButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                border.color: root.pathEditMode ? Theme.primary : Theme.outlineMedium
                border.width: root.pathEditMode ? 2 : 1
                clip: true
                color: Theme.surfaceContainerHigh
                height: 34
                radius: Theme.cornerRadius

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    enabled: !root.pathEditMode

                    onClicked: root.showPathEditor()
                }
                Flickable {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingS
                    anchors.rightMargin: Theme.spacingS
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    contentHeight: height
                    contentWidth: breadcrumbRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    visible: !root.pathEditMode

                    Row {
                        id: breadcrumbRow

                        height: parent.height
                        spacing: 2

                        Repeater {
                            model: root.breadcrumbs()

                            Rectangle {
                                id: crumb

                                required property var modelData

                                anchors.verticalCenter: parent.verticalCenter
                                color: crumbArea.containsMouse ? Theme.surfaceVariant : "transparent"
                                height: 28
                                radius: Theme.cornerRadius
                                width: crumbText.implicitWidth + Theme.spacingM * 2

                                StyledText {
                                    id: crumbText

                                    anchors.centerIn: parent
                                    color: crumb.modelData.path === root.currentPath ? Theme.primary : Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: crumb.modelData.path === root.currentPath ? Font.Medium : Font.Normal
                                    text: crumb.modelData.name
                                }
                                MouseArea {
                                    id: crumbArea

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true

                                    onClicked: root.requestNavigation(crumb.modelData.path, "push", -1, false)
                                }
                            }
                        }
                    }
                }
                DankTextField {
                    id: pathField

                    anchors.fill: parent
                    bottomPadding: Theme.spacingXS
                    placeholderText: "/path or ~/folder"
                    topPadding: Theme.spacingXS
                    visible: root.pathEditMode

                    Keys.onEscapePressed: {
                        text = root.currentPath;
                        root.pathEditMode = false;
                        contentRoot.forceActiveFocus();
                    }
                    onAccepted: {
                        root.pathEditMode = false;
                        root.requestNavigation(text, "push", -1, false);
                        contentRoot.forceActiveFocus();
                    }
                    onActiveFocusChanged: {
                        if (root.pathEditMode && !activeFocus && !pathEditLossGuard) {
                            pathEditLossGuard = true;
                            root.pathEditMode = false;
                            Qt.callLater(() => {
                                pathEditLossGuard = false;
                                if (text && text !== root.currentPath)
                                    root.requestNavigation(text, "push", -1, false);
                                contentRoot.forceActiveFocus();
                            });
                        }
                    }
                }
            }
            DankActionButton {
                id: refreshButton

                Accessible.name: tooltipText
                Accessible.role: Accessible.Button
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                circular: false
                iconName: "refresh"
                tooltipText: "Refresh (F5)"

                onClicked: root.refreshFolder()
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: navigationBar.bottom
            color: Theme.outline
            height: 1
        }
        Rectangle {
            id: toolBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: navigationBar.bottom
            anchors.topMargin: 1
            color: Theme.surfaceContainer
            height: 44

            Flickable {
                id: toolFlick

                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.right: searchBox.left
                anchors.rightMargin: root.searchVisible ? Theme.spacingS : 0
                anchors.top: parent.top
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                contentHeight: height
                contentWidth: toolButtons.implicitWidth
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: toolButtons

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    DankActionButton {
                        id: createButton

                        Accessible.name: tooltipText
                        Accessible.role: Accessible.Button
                        circular: false
                        enabled: root.backendReady
                        iconName: "add"
                        tooltipText: "Create"

                        onClicked: {
                            const point = mapToItem(contentRoot, 0, height);
                            actionMenu.showAt(contentRoot, point.x, point.y, root.createMenuItems(), false);
                        }
                    }
                    DankActionButton {
                        Accessible.name: tooltipText
                        Accessible.role: Accessible.Button
                        circular: false
                        iconName: root.viewMode === "grid" ? "view_list" : "grid_view"
                        tooltipText: root.viewMode === "grid" ? "List view" : "Grid view"

                        onClicked: {
                            root.viewMode = root.viewMode === "grid" ? "list" : "grid";
                            root.ensureCurrentVisible();
                        }
                    }
                    DankActionButton {
                        Accessible.name: tooltipText
                        Accessible.role: Accessible.Button
                        circular: false
                        iconColor: root.showHidden ? Theme.primary : Theme.surfaceText
                        iconName: root.showHidden ? "visibility_off" : "visibility"
                        tooltipText: "Show hidden files (Ctrl+H)"

                        onClicked: {
                            root.showHidden = !root.showHidden;
                            root.clearSelection();
                        }
                    }
                    DankActionButton {
                        id: sortButton

                        Accessible.name: tooltipText
                        Accessible.role: Accessible.Button
                        circular: false
                        iconName: root.sortAscending ? "sort_by_alpha" : "sort"
                        tooltipText: "Sort: " + root.sortBy

                        onClicked: {
                            const point = mapToItem(contentRoot, 0, height);
                            actionMenu.showAt(contentRoot, point.x, point.y, root.sortMenuItems(), false);
                        }
                    }
                    DankActionButton {
                        Accessible.name: tooltipText
                        Accessible.role: Accessible.Button
                        circular: false
                        iconColor: root.searchVisible ? Theme.primary : Theme.surfaceText
                        iconName: "search"
                        tooltipText: "Search (Ctrl+F)"

                        onClicked: {
                            if (root.searchVisible && !root.searchText) {
                                root.searchVisible = false;
                                contentRoot.forceActiveFocus();
                            } else {
                                root.showSearch();
                            }
                        }
                    }
                    DankActionButton {
                        Accessible.name: tooltipText
                        Accessible.role: Accessible.Button
                        circular: false
                        iconName: root.showSidebar ? "left_panel_close" : "left_panel_open"
                        tooltipText: "Toggle places sidebar"

                        onClicked: root.showSidebar = !root.showSidebar
                    }
                }
            }
            Item {
                id: searchBox

                anchors.right: parent.right
                anchors.rightMargin: root.searchVisible ? Theme.spacingS : 0
                anchors.verticalCenter: parent.verticalCenter
                height: 34
                visible: root.searchVisible
                width: root.searchVisible ? Math.min(280, Math.max(150, toolBar.width * 0.42)) : 0

                DankTextField {
                    id: searchField

                    anchors.fill: parent
                    bottomPadding: Theme.spacingXS
                    leftIconName: "search"
                    placeholderText: "Search this folder"
                    showClearButton: true
                    topPadding: Theme.spacingXS

                    Keys.onEscapePressed: {
                        text = "";
                        root.searchText = "";
                        root.searchVisible = false;
                        contentRoot.forceActiveFocus();
                    }
                    onAccepted: contentRoot.forceActiveFocus()
                    onTextEdited: {
                        if (root.searchText !== text)
                            root.searchText = text;
                    }
                }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: toolBar.bottom
            color: Theme.outline
            height: 1
        }
        Item {
            id: body

            anchors.bottom: jobBar.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: toolBar.bottom
            anchors.topMargin: 1

            Rectangle {
                id: sidebar

                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.top: parent.top
                clip: true
                color: Theme.surfaceContainer
                visible: width > 0
                width: root.showSidebar && root.width >= 680 ? 190 : 0

                StyledText {
                    id: placesTitle

                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: Theme.spacingM
                    color: Theme.surfaceTextMedium
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    text: "PLACES"
                }
                FocusScope {
                    id: placesList

                    property int currentIndex: 0

                    function navigate(path) {
                        if (!path)
                            return;
                        root.requestNavigation(path, "push", -1, false);
                        contentRoot.forceActiveFocus();
                    }
                    function rowCount() {
                        return root.places.length;
                    }

                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.spacingS
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.top: placesTitle.bottom
                    anchors.topMargin: Theme.spacingS
                    focus: false

                    Keys.onPressed: event => {
                        const count = rowCount();
                        if (count === 0)
                            return;
                        if (event.key === Qt.Key_Down) {
                            currentIndex = Math.min(count - 1, currentIndex + 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            currentIndex = Math.max(0, currentIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            currentIndex = 0;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            currentIndex = count - 1;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            navigate(root.places[currentIndex].path);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            event.accepted = false;
                        }
                    }

                    Column {
                        anchors.fill: parent
                        spacing: 2

                        Repeater {
                            model: root.places

                            Rectangle {
                                id: placeRow

                                required property int index
                                required property var modelData

                                Accessible.name: modelData.name
                                Accessible.role: Accessible.Button
                                border.color: placesList.currentIndex === placeRow.index && placesList.focus ? Theme.primary : "transparent"
                                border.width: placesList.currentIndex === placeRow.index && placesList.focus ? 1 : 0
                                color: {
                                    if (modelData.path === root.currentPath)
                                        return Theme.primaryContainer;
                                    if (placesList.currentIndex === placeRow.index && placesList.focus)
                                        return Theme.surfaceVariant;
                                    return placeArea.containsMouse ? Theme.surfaceVariant : "transparent";
                                }
                                enabled: !!modelData.path
                                height: 36
                                opacity: enabled ? 1 : 0.4
                                radius: Theme.cornerRadius
                                width: parent.width

                                DankIcon {
                                    id: placeIcon

                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: placeRow.modelData.path === root.currentPath ? Theme.primary : Theme.surfaceText
                                    name: placeRow.modelData.icon
                                    size: 19
                                }
                                StyledText {
                                    anchors.left: placeIcon.right
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: placeRow.modelData.path === root.currentPath ? Theme.primary : Theme.surfaceText
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeSmall
                                    text: placeRow.modelData.name
                                }
                                MouseArea {
                                    id: placeArea

                                    anchors.fill: parent
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    enabled: placeRow.enabled
                                    hoverEnabled: true

                                    onClicked: {
                                        placesList.currentIndex = placeRow.index;
                                        placesList.forceActiveFocus();
                                        placesList.navigate(placeRow.modelData.path);
                                    }
                                    onDoubleClicked: {
                                        placesList.currentIndex = placeRow.index;
                                        placesList.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: sidebar.right
                anchors.top: parent.top
                color: Theme.outline
                width: sidebar.visible ? 1 : 0
            }
            Item {
                id: filePane

                anchors.bottom: parent.bottom
                anchors.left: sidebar.right
                anchors.leftMargin: sidebar.visible ? 1 : 0
                anchors.right: parent.right
                anchors.top: parent.top

                Rectangle {
                    id: listHeader

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: Theme.surfaceContainerHigh
                    height: root.viewMode === "list" ? 32 : 0
                    visible: root.viewMode === "list"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS + 38
                        anchors.rightMargin: Theme.spacingS

                        Repeater {
                            model: [
                                {
                                    "name": "Name",
                                    "field": "name",
                                    "width": Math.max(120, listHeader.width - 38 - 84 - 160 - 104 - Theme.spacingM * 2)
                                },
                                {
                                    "name": "Size",
                                    "field": "size",
                                    "width": 84
                                },
                                {
                                    "name": "Modified",
                                    "field": "modified",
                                    "width": 160
                                },
                                {
                                    "name": "Type",
                                    "field": "type",
                                    "width": 104
                                }
                            ]

                            Rectangle {
                                id: heading

                                required property var modelData

                                color: headingArea.containsMouse ? Theme.surfaceVariant : "transparent"
                                height: parent.height
                                width: modelData.width

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingS
                                    anchors.verticalCenter: parent.verticalCenter
                                    layoutDirection: heading.modelData.field === "name" ? Qt.LeftToRight : Qt.RightToLeft
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        color: root.sortBy === heading.modelData.field ? Theme.primary : Theme.surfaceTextMedium
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.weight: Font.Medium
                                        text: heading.modelData.name
                                    }
                                    DankIcon {
                                        color: Theme.primary
                                        name: root.sortAscending ? "arrow_upward" : "arrow_downward"
                                        size: 14
                                        visible: root.sortBy === heading.modelData.field
                                    }
                                }
                                MouseArea {
                                    id: headingArea

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true

                                    onClicked: root.setSort(heading.modelData.field)
                                }
                            }
                        }
                    }
                }
                Item {
                    id: viewArea

                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: listHeader.bottom
                    clip: true

                    MouseArea {
                        id: blankArea

                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        anchors.fill: parent

                        onClicked: mouse => {
                            if (mouse.button !== Qt.RightButton)
                                return;
                            actionMenu.showAt(contentRoot, filePane.x + mouse.x, viewArea.y + mouse.y + body.y, root.blankMenuItems(), false);
                        }
                        onPositionChanged: mouse => {
                            if (rubberBand.dragging)
                                rubberBand.requestUpdate(mouse.x, mouse.y);
                        }
                        onPressed: mouse => {
                            if (mouse.button === Qt.RightButton)
                                return;
                            rubberBand.startX = mouse.x;
                            rubberBand.startY = mouse.y;
                            rubberBand.dragging = true;
                            rubberBand.requestUpdate(mouse.x, mouse.y);
                            if (mouse.modifiers === Qt.NoModifier)
                                root.clearSelection();
                            rubberBand.anchorIndex = root.indexAtPosition(mouse.x, mouse.y);
                        }
                        onReleased: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                rubberBand.dragging = false;
                                rubberBand.requestUpdate(mouse.x, mouse.y);
                                return;
                            }
                            rubberBand.dragging = false;
                            rubberBand.requestUpdate(mouse.x, mouse.y);
                            contentRoot.forceActiveFocus();
                        }
                    }
                    Rectangle {
                        id: rubberBand

                        property int anchorIndex: -1
                        property real currentX: 0
                        property real currentY: 0
                        property bool dragging: false
                        property real rectHeight: 0
                        property real rectWidth: 0
                        property real startX: 0
                        property real startY: 0
                        property real xPos: 0
                        property real yPos: 0

                        function requestUpdate(x, y) {
                            currentX = x;
                            currentY = y;
                            const left = Math.min(startX, currentX);
                            const top = Math.min(startY, currentY);
                            const right = Math.max(startX, currentX);
                            const bottom = Math.max(startY, currentY);
                            xPos = left;
                            yPos = top;
                            rectWidth = right - left;
                            rectHeight = bottom - top;
                            visible = dragging && rectWidth > 2 && rectHeight > 2;
                            if (!visible)
                                return;
                            const currentIndex = root.indexAtPosition(x, y);
                            if (currentIndex < 0 || anchorIndex < 0)
                                return;
                            const first = Math.min(anchorIndex, currentIndex);
                            const last = Math.max(anchorIndex, currentIndex);
                            const next = [];
                            for (let i = first; i <= last; ++i) {
                                const item = root.itemAt(i);
                                if (item)
                                    next.push(item);
                            }
                            root.setSelection(next);
                            root.currentIndex = currentIndex;
                        }

                        border.color: Theme.primary
                        border.width: 1
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        height: 0
                        visible: false
                        width: 0
                        x: 0
                        y: 0
                        z: 50

                        Binding on height {
                            restoreMode: Binding.RestoreBindingOrValue
                            value: rubberBand.rectHeight
                            when: rubberBand.dragging
                        }
                        Binding on width {
                            restoreMode: Binding.RestoreBindingOrValue
                            value: rubberBand.rectWidth
                            when: rubberBand.dragging
                        }
                        Binding on x {
                            restoreMode: Binding.RestoreBindingOrValue
                            value: rubberBand.xPos
                            when: rubberBand.dragging
                        }
                        Binding on y {
                            restoreMode: Binding.RestoreBindingOrValue
                            value: rubberBand.yPos
                            when: rubberBand.dragging
                        }
                    }
                    DropArea {
                        function acceptAction(drag) {
                            if (!root.supportsDrop(drag))
                                return -1;
                            const source = drag.source;
                            if (source && source.Window && source.Window.window && source.Window.window === root.Window.window)
                                return drag.proposedAction;
                            return Qt.CopyAction;
                        }

                        anchors.fill: parent

                        onDropped: drop => {
                            const realAction = acceptAction(drop);
                            if (realAction < 0) {
                                drop.accepted = false;
                                return;
                            }
                            const urls = [];
                            for (let i = 0; i < drop.urls.length; ++i)
                                urls.push(String(drop.urls[i]));
                            if (root.handleDrop(urls, root.currentPath, realAction))
                                drop.accept(realAction);
                            else
                                drop.accepted = false;
                        }
                        onEntered: drag => {
                            const realAction = acceptAction(drag);
                            if (realAction < 0)
                                drag.accepted = false;
                            else
                                drag.accept(realAction);
                        }
                    }
                    DankGridView {
                        id: fileGrid

                        acceptedButtons: Qt.NoButton
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: root.gridCellHeight * 3
                        cellHeight: root.gridCellHeight
                        cellWidth: root.gridCellWidth
                        clip: true
                        currentIndex: root.currentIndex
                        model: visible ? folderModel : null
                        reuseItems: true
                        visible: root.viewMode === "grid"

                        delegate: FileItemDelegate {
                            current: index === root.currentIndex
                            cut: root.isCut(filePath)
                            dragUrls: selected ? root.selectedDragUrls : [root.fileUrl(filePath)]
                            dropEnabled: root.backendReady
                            gridMode: true
                            height: root.gridCellHeight - Theme.spacingS
                            selected: root.isSelected(filePath)
                            width: root.gridCellWidth - Theme.spacingS

                            onClicked: (itemIndex, modifiers) => {
                                contentRoot.forceActiveFocus();
                                root.selectIndex(itemIndex, modifiers);
                            }
                            onContextRequested: (sender, x, y, itemIndex) => root.showMenuForItem(sender, x, y, itemIndex)
                            onDoubleClicked: itemIndex => root.activateItem(itemIndex)
                            onFilesDropped: (urls, destination, action) => root.handleDrop(urls, destination, action)
                            onPrepareDrag: itemIndex => {
                                if (!root.isSelected(filePath))
                                    root.selectIndex(itemIndex, Qt.NoModifier);
                            }
                        }
                    }
                    DankListView {
                        id: fileList

                        acceptedButtons: Qt.NoButton
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacingS
                        anchors.rightMargin: Theme.spacingS
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: 400
                        clip: true
                        currentIndex: root.currentIndex
                        model: visible ? folderModel : null
                        reuseItems: true
                        spacing: 1
                        visible: root.viewMode === "list"

                        delegate: FileItemDelegate {
                            current: index === root.currentIndex
                            cut: root.isCut(filePath)
                            dragUrls: selected ? root.selectedDragUrls : [root.fileUrl(filePath)]
                            dropEnabled: root.backendReady
                            gridMode: false
                            height: 44
                            selected: root.isSelected(filePath)
                            width: fileList.width

                            onClicked: (itemIndex, modifiers) => {
                                contentRoot.forceActiveFocus();
                                root.selectIndex(itemIndex, modifiers);
                            }
                            onContextRequested: (sender, x, y, itemIndex) => root.showMenuForItem(sender, x, y, itemIndex)
                            onDoubleClicked: itemIndex => root.activateItem(itemIndex)
                            onFilesDropped: (urls, destination, action) => root.handleDrop(urls, destination, action)
                            onPrepareDrag: itemIndex => {
                                if (!root.isSelected(filePath))
                                    root.selectIndex(itemIndex, Qt.NoModifier);
                            }
                        }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS
                        visible: folderModel.status === FolderListModel.Loading || (folderModel.status === FolderListModel.Ready && folderModel.count === 0)

                        DankIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Theme.surfaceTextMedium
                            name: folderModel.status === FolderListModel.Loading ? "hourglass_empty" : (root.appliedSearchText ? "search_off" : "folder_open")
                            size: 38
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Theme.surfaceTextMedium
                            font.pixelSize: Theme.fontSizeMedium
                            text: folderModel.status === FolderListModel.Loading ? "Loading..." : (root.appliedSearchText ? "No matching files" : "This folder is empty")
                        }
                    }
                }
            }
        }
        Rectangle {
            id: jobBar

            anchors.bottom: statusBar.top
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            color: Theme.surfaceContainerHigh
            height: root.showJobBar && root.displayJob ? 54 : 0
            visible: height > 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                color: Theme.outline
                height: 1
            }
            Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.right: cancelJobButton.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Row {
                    spacing: Theme.spacingS
                    width: parent.width

                    StyledText {
                        color: root.displayJob?.status === "error" ? Theme.error : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        text: root.displayJob?.label || ""
                    }
                    StyledText {
                        color: Theme.surfaceTextMedium
                        elide: Text.ElideMiddle
                        font.pixelSize: Theme.fontSizeSmall
                        text: {
                            const job = root.displayJob;
                            if (!job)
                                return "";
                            if (job.status === "queued")
                                return "Queued";
                            if (job.status === "cancelling")
                                return "Cancelling...";
                            if (job.current)
                                return root.basename(job.current);
                            return job.message || job.status;
                        }
                        width: Math.max(0, parent.width - x)
                    }
                }
                Rectangle {
                    color: Theme.surfaceVariant
                    height: 5
                    radius: 3
                    width: parent.width

                    Rectangle {
                        color: root.displayJob?.status === "error" ? Theme.error : Theme.primary
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * root.displayProgress
                    }
                }
            }
            DankActionButton {
                id: cancelJobButton

                Accessible.name: tooltipText
                Accessible.role: Accessible.Button
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                circular: false
                iconName: "close"
                tooltipText: "Cancel operation"
                visible: ["queued", "running"].includes(root.displayJob?.status || "")

                onClicked: root.cancelJob(root.displayJob?.id ?? -1)
            }
        }
        Rectangle {
            id: statusBar

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            color: Theme.surfaceContainer
            height: 30

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                color: Theme.outline
                height: 1
            }
            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.surfaceTextMedium
                font.pixelSize: Theme.fontSizeSmall
                text: folderModel.count + " item(s)" + (root.selection.length ? "  |  " + root.selection.length + " selected" : "")
            }
            StyledText {
                anchors.centerIn: parent
                color: root.statusIsError ? Theme.error : Theme.primary
                elide: Text.ElideMiddle
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                text: root.statusMessage
                visible: text.length > 0
                width: Math.max(0, parent.width - 320)
            }
            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                color: root.backendReady ? Theme.surfaceTextMedium : Theme.error
                font.pixelSize: Theme.fontSizeSmall
                text: root.backendReady ? (root.activeJobs + " active job(s)") : "Backend unavailable"
            }
        }
        FileActionMenu {
            id: actionMenu

            returnFocus: contentRoot
        }
        Popup {
            id: propertiesPopup

            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            dim: true
            focus: true
            height: Math.min(430, Math.max(230, propertyText.contentHeight + 120))
            modal: true
            padding: 0
            parent: Overlay.overlay
            width: Math.min(520, Math.max(328, parent.width - 32))
            x: Math.max(16, (parent.width - width) / 2)
            y: Math.max(16, (parent.height - height) / 2)

            background: Rectangle {
                color: "transparent"
            }
            contentItem: Rectangle {
                border.color: Theme.outlineMedium
                border.width: 1
                color: Theme.floatingSurface
                radius: Theme.cornerRadius

                StyledText {
                    id: propertiesTitle

                    anchors.left: parent.left
                    anchors.margins: Theme.spacingL
                    anchors.right: parent.right
                    anchors.top: parent.top
                    color: Theme.surfaceText
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    text: root.propertyItems.length === 1 ? "Properties - " + root.propertyItems[0].name : "Properties"
                }
                Flickable {
                    anchors.bottom: propertiesClose.top
                    anchors.left: parent.left
                    anchors.margins: Theme.spacingL
                    anchors.right: parent.right
                    anchors.top: propertiesTitle.bottom
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    contentHeight: propertyText.contentHeight
                    contentWidth: width

                    StyledText {
                        id: propertyText

                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        text: root.propertiesText()
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                    }
                }
                DankButton {
                    id: propertiesClose

                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.spacingL
                    anchors.right: parent.right
                    text: "Close"

                    onClicked: propertiesPopup.close()
                }
            }
        }
        FocusScope {
            id: conflictDialog

            readonly property var choices: transferConflict ? [
                {
                    "text": "Keep Both",
                    "icon": "file_copy",
                    "policy": "rename"
                },
                {
                    "text": "Merge/Replace This Item",
                    "icon": "sync",
                    "policy": "replace",
                    "dangerous": true
                },
                {
                    "text": "Skip",
                    "icon": "skip_next",
                    "policy": "skip"
                }
            ] : [
                {
                    "text": "Rename",
                    "icon": "drive_file_rename_outline",
                    "policy": "rename"
                },
                {
                    "text": "Cancel/Skip",
                    "icon": "close",
                    "policy": "skip"
                }
            ]
            property int selectedChoice: 0
            readonly property bool transferConflict: ["copy", "move"].includes(root.currentConflict?.record?.request?.op || "")

            anchors.fill: parent
            focus: visible
            visible: root.currentConflict !== null
            z: 500

            Keys.onPressed: event => {
                const count = choices.length;
                if (count === 0)
                    return;
                switch (event.key) {
                case Qt.Key_Left:
                case Qt.Key_Up:
                case Qt.Key_Backtab:
                    selectedChoice = (selectedChoice + count - 1) % count;
                    event.accepted = true;
                    break;
                case Qt.Key_Right:
                case Qt.Key_Down:
                case Qt.Key_Tab:
                    selectedChoice = (selectedChoice + 1) % count;
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    root.resolveConflict(choices[selectedChoice].policy);
                    event.accepted = true;
                    break;
                case Qt.Key_Escape:
                    root.resolveConflict("skip");
                    event.accepted = true;
                    break;
                }
            }
            onVisibleChanged: {
                if (visible)
                    selectedChoice = 0;
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.withAlpha(Theme.surfaceContainer, 0.72)

                MouseArea {
                    anchors.fill: parent
                }
            }
            Rectangle {
                Accessible.name: "File conflict"
                Accessible.role: Accessible.Dialog
                anchors.centerIn: parent
                border.color: Theme.outlineMedium
                border.width: 1
                color: Theme.floatingSurface
                height: conflictColumn.implicitHeight + Theme.spacingL * 2
                radius: Theme.cornerRadius
                width: Math.min(540, parent.width - Theme.spacingL * 2)

                Column {
                    id: conflictColumn

                    anchors.left: parent.left
                    anchors.margins: Theme.spacingL
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Theme.spacingM

                    StyledText {
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        text: conflictDialog.transferConflict ? "Transfer Conflict" : "Name Conflict"
                        width: parent.width
                    }
                    StyledText {
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        text: {
                            if (!root.currentConflict)
                                return "";
                            const event = root.currentConflict.event;
                            const explanation = conflictDialog.transferConflict ? "Keep Both creates a uniquely named copy. Merge/Replace This Item merges a folder and replaces every conflicting item inside it. Later selected items are still confirmed separately." : "Rename uses another name. Cancel/Skip leaves the existing destination unchanged.";
                            return "A destination already exists.\n\n" + explanation + "\n\n" + root.pathFromUrl(event.source || "") + "\n->\n" + root.pathFromUrl(event.destination || "");
                        }
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Theme.spacingS

                        Repeater {
                            model: conflictDialog.choices

                            DankButton {
                                backgroundColor: modelData.dangerous ? Theme.error : Theme.buttonBg
                                border.color: conflictDialog.selectedChoice === index ? (modelData.dangerous ? Theme.surfaceText : Theme.primary) : "transparent"
                                border.width: conflictDialog.selectedChoice === index ? 2 : 0
                                buttonHeight: 38
                                horizontalPadding: Theme.spacingM
                                iconName: modelData.icon
                                text: modelData.text
                                textColor: modelData.dangerous ? Theme.primaryText : Theme.buttonText

                                onClicked: root.resolveConflict(modelData.policy)
                            }
                        }
                    }
                }
            }
        }
    }
    InputModal {
        id: inputModal
    }
    ConfirmModal {
        id: confirmModal
    }
    FloatingWindowControls {
        id: windowControls

        targetWindow: root
    }
}
