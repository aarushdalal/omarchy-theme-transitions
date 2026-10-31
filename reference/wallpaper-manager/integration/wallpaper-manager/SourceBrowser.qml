import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import "Selection.js" as Selection
Dialog {
    id: browser
    property var manager
    property bool folderMode: false
    property var chosen: ({})
    property string anchor: ""
    readonly property var selectedPaths: Object.keys(chosen).filter(function(key) { return chosen[key] })
    readonly property var places: manager.browserPlaces || [{name: "Home", path: manager.home}, {name: "File system", path: "/"}]
    readonly property string currentPath: modelPath(folders.folder)
    readonly property int entryCount: folders.count
    signal picked(var paths)
    width: Math.min(960, parent.width - 32)
    height: Math.min(660, parent.height - 32)
    modal: true
    popupType: Popup.Item
    title: folderMode ? "Choose folders to scan" : "Choose wallpaper files"
    onOpened: if (typeof manager.refreshBrowserPlaces === "function") manager.refreshBrowserPlaces()
    header: Label { text: browser.title; padding: 10; color: browser.manager.fg; font.pixelSize: 16; font.bold: true; background: Rectangle { color: "transparent" } }
    function pickFiles() { folderMode = false; chosen = ({}); anchor = ""; open() }
    function pickFolder() { folderMode = true; chosen = ({}); anchor = ""; open() }
    function localPath(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")) }
    // FolderListModel resolves a local file URL, then reparses its path as a
    // URL again. Protect percent/query/fragment characters through both passes.
    function modelUrl(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/").replace(/%/g, "%25") }
    function modelPath(url) { return decodeURIComponent(localPath(url)) }
    function normalizedPath(value) {
        value = value.trim()
        if (value.indexOf("file://") === 0) value = localPath(value)
        if (value === "~") return manager.home
        if (value.indexOf("~/") === 0) return manager.home + value.substring(1)
        return value.charAt(0) === "/" ? value : manager.home + "/" + value
    }
    function navigate(path) {
        if (!folderMode) chosen = ({})
        anchor = ""
        path = normalizedPath(path)
        location.text = path
        folders.folder = modelUrl(path)
    }
    function keys() { var result = []; for (var i = 0; i < folders.count; i++) result.push(folders.get(i, "filePath")); return result }
    function select(index, modifiers, toggle) {
        var key = folders.get(index, "filePath")
        var visibleKeys = keys()
        var result = Selection.select(visibleKeys, chosen, key, modifiers, anchor, toggle)
        if (folderMode) selectedPaths.forEach(function(path) { if (visibleKeys.indexOf(path) < 0) result.selected[path] = true })
        chosen = result.selected; anchor = result.anchor; entries.currentIndex = index; entries.forceActiveFocus()
    }
    function selectAll() {
        var next = folderMode ? Object.assign({}, chosen) : {}
        for (var i = 0; i < folders.count; i++) if (folderMode || !folders.get(i, "fileIsDir")) next[folders.get(i, "filePath")] = true
        chosen = next
    }
    function scanPaths() { return selectedPaths.length ? selectedPaths : [normalizedPath(location.text)] }
    function scanPath() { return scanPaths()[0] }
    function removePath(path) { var next = Object.assign({}, chosen); delete next[path]; chosen = next }
    function addCurrent() { var next = Object.assign({}, chosen); next[normalizedPath(location.text)] = true; chosen = next }
    function acceptSelection() {
        var paths = folderMode ? scanPaths() : selectedPaths
        if (!paths.length) return
        close(); picked(paths)
    }
    function activate(index) {
        if (index < 0) return
        if (folders.get(index, "fileIsDir")) navigate(folders.get(index, "filePath"))
        else { select(index, 0, false); acceptSelection() }
    }
    FolderListModel {
        id: folders
        folder: browser.modelUrl(browser.manager.home)
        showDotAndDotDot: false; showDirsFirst: true; showHidden: false; caseSensitive: false
        showFiles: !browser.folderMode
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp", "*.tiff", "*.gif", "*.mp4", "*.mkv", "*.webm", "*.mov", "*.m4v", "*.avi", "*.pkg", "*.tex"]
        onFolderChanged: { if (!browser.folderMode) browser.chosen = ({}); browser.anchor = ""; location.text = browser.modelPath(folders.folder) }
    }
    contentItem: ColumnLayout {
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            ActionButton { text: "Up"; onClicked: browser.navigate(browser.currentPath.split("/").slice(0,-1).join("/") || "/") }
            Field { id: location; objectName: "browser-location"; Layout.fillWidth: true; text: browser.currentPath; selectByMouse: true; onAccepted: browser.navigate(browser.normalizedPath(text)) }
            ActionButton { text: "Home"; onClicked: browser.navigate(browser.manager.home) }
        }
        Caption { Layout.fillWidth: true; text: browser.folderMode ? "Check folders, or use Ctrl / Shift to select several. Open folders to browse; selections stay while you navigate. Each folder gets its own batch." : "Click to select · Ctrl-click to add/remove · Shift-click for a range · Double-click folders to open" }
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
            ColumnLayout {
                Layout.preferredWidth: Math.min(190, browser.width * 0.23); Layout.maximumWidth: Math.min(190, browser.width * 0.23); Layout.fillWidth: false; Layout.fillHeight: true
                Caption { text: "Places"; font.bold: true }
                ListView {
                    id: placesList
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 3
                    model: browser.places
                    ScrollBar.vertical: ScrollBar {}
                    delegate: ActionButton {
                        required property var modelData
                        objectName: "browser-place-" + modelData.path
                        width: ListView.view.width
                        text: modelData.name + (modelData.read_only ? " (read only)" : "")
                        primary: browser.currentPath === modelData.path
                        onClicked: browser.navigate(modelData.path)
                    }
                }
                ActionButton { objectName: "refresh-places"; text: "Refresh drives"; Layout.fillWidth: true; onClicked: if (typeof browser.manager.refreshBrowserPlaces === "function") browser.manager.refreshBrowserPlaces() }
            }
        ListView {
            id: entries
            activeFocusOnTab: true
            Layout.fillWidth: true; Layout.minimumWidth: 150; Layout.fillHeight: true; clip: true; model: folders; spacing: 2
            keyNavigationEnabled: true
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) { browser.selectAll(); event.accepted = true }
                else if (event.key === Qt.Key_Space && currentIndex >= 0) { browser.select(currentIndex, event.modifiers, true); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { browser.activate(currentIndex); event.accepted = true }
                else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && count) {
                    var next = Math.max(0, Math.min(count - 1, currentIndex + (event.key === Qt.Key_Up ? -1 : 1)))
                    if (event.modifiers & Qt.ControlModifier) currentIndex = next
                    else browser.select(next, event.modifiers, false)
                    positionViewAtIndex(next, ListView.Contain); event.accepted = true
                }
            }
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property int index
                required property string fileName
                required property string filePath
                required property bool fileIsDir
                objectName: "browser-row-" + fileName
                width: ListView.view.width; height: 38; radius: 5
                color: browser.chosen[filePath] ? Qt.alpha(browser.manager.accent, 0.2) : "transparent"
                MouseArea {
                    anchors.fill: parent
                    property var beforeClick: ({})
                    onClicked: mouse => { beforeClick = Object.assign({}, browser.chosen); browser.select(index, mouse.modifiers, false) }
                    onDoubleClicked: mouse => {
                        // Browsing a folder must not silently add that folder
                        // to the persistent scan selection on the first click.
                        if (fileIsDir) browser.chosen = beforeClick
                        mouse.accepted = true
                        browser.activate(index)
                    }
                }
                RowLayout {
                    anchors.fill: parent; anchors.margins: 3
                    SelectionCheckBox { objectName: "browser-file-" + fileName; visible: browser.folderMode || !fileIsDir; checked: browser.chosen[filePath] === true; onClicked: browser.select(index, 0, true) }
                    Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: (fileIsDir ? "▸  " : "") + fileName; color: "#ffffff"; elide: Text.ElideMiddle; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                    ActionButton { objectName: "browser-open-" + fileName; visible: fileIsDir; text: "Open"; implicitHeight: 30; onClicked: browser.navigate(filePath) }
                }
            }
        }
        }
        ListView {
            visible: browser.folderMode && browser.selectedPaths.length > 0
            Layout.fillWidth: true; Layout.preferredHeight: Math.min(84, browser.selectedPaths.length * 28)
            clip: true; model: browser.selectedPaths
            ScrollBar.vertical: ScrollBar {}
            delegate: RowLayout {
                required property string modelData
                width: ListView.view.width; height: 28
                Caption { Layout.fillWidth: true; maximumLineCount: 1; elide: Text.ElideMiddle; text: modelData }
                ActionButton { text: "×"; implicitHeight: 26; onClicked: browser.removePath(modelData) }
            }
        }
        Caption { Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideMiddle; text: browser.folderMode ? (browser.selectedPaths.length ? browser.selectedPaths.length + " folders selected · separate batches · subfolders only if enabled" : "Scan current folder: " + browser.scanPath()) : browser.selectedPaths.length + " selected" }
        RowLayout {
            Layout.fillWidth: true
            ActionButton { visible: browser.folderMode; text: "Add current folder"; onClicked: browser.addCurrent() }
            ActionButton { objectName: "browser-clear"; visible: browser.selectedPaths.length > 0; text: "Clear selection"; onClicked: browser.chosen = ({}) }
            Item { Layout.fillWidth: true }
            ActionButton { text: "Cancel"; onClicked: browser.close() }
            ActionButton { objectName: "browser-accept"; primary: true; text: browser.folderMode ? (browser.selectedPaths.length ? "Scan " + browser.selectedPaths.length + " folders" : "Scan current folder") : "Use selection"; enabled: browser.folderMode || browser.selectedPaths.length > 0; onClicked: browser.acceptSelection() }
        }
    }
    background: Rectangle { color: browser.manager.bg; radius: 10; border.color: browser.manager.outline }
}
