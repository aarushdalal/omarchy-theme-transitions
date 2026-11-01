import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as ShellCommons
import "ImportBatchModel.js" as BatchModel

Item {
    id: root
    readonly property string home: Quickshell.env("HOME")
    property bool opened: false
    property bool draftLoaded: false
    property bool busy: worker.busy || !draftLoaded
    property string page: "library"
    property var items: []
    property var groups: []
    property var candidates: []
    property var selected: ({})
    property var incoming: ({})
    property bool recursiveScan: false
    property var queuedBatches: []
    onQueuedBatchesChanged: if (draftLoaded) draftSaveTimer.restart()
    Component.onCompleted: draftWorker.send({action:"draft-load"})
    property var backgroundJobs: []
    property var browserPlaces: [{name: "Home", path: home}, {name: "File system", path: "/"}]
    property var folderScanOptions: ({})
    signal folderBatchesReady()
    readonly property var availableGroups: groups.concat(queuedBatches.map(function(b) { return b.group })).filter(function(value, index, all) { return value && all.indexOf(value) === index }).sort(function(a,b) { return a.toLowerCase().localeCompare(b.toLowerCase()) })
    property string draftFolder: ""
    readonly property int queuedCount: BatchModel.count(queuedBatches)
    readonly property var activeJobs: backgroundJobs.filter(function(j) { return j.state === "pending" || j.state === "running" })
    readonly property string backgroundText: activeJobs.length ? "Background: " + activeJobs[0].completed + "/" + activeJobs[0].total + " · batch " + activeJobs[0].batch + "/" + activeJobs[0].batches : ""
    function queueBatch(group, options) {
        try {
            queuedBatches = BatchModel.add(queuedBatches, selectedCandidates, group, Object.assign({},options,{target:target()}), draftFolder)
            var queuedSources = {}; selectedCandidates.forEach(function(i) { queuedSources[i.source] = true })
            candidates = candidates.filter(function(i) { return !queuedSources[i.source] }); incoming = ({}); chooseAll(true)
            statusText = queuedBatches.length + " batches queued"
            return true
        } catch (e) { statusText = e.message; details += e.message + "\n"; return false }
    }
    function setQueuedGroup(index, group) { var clean = (group && group !== "Ungrouped") ? group.trim() : ""; if (index >= 0 && index < queuedBatches.length && queuedBatches[index].group !== clean) queuedBatches = BatchModel.setGroup(queuedBatches, index, clean) }
    function removeBatch(index) { queuedBatches = queuedBatches.filter(function(b,i) { return i !== index }) }
    function moveBatch(index, direction) { var next = queuedBatches.slice(); var row = next.splice(index,1)[0]; next.splice(index+direction,0,row); queuedBatches = next }
    function startQueue() { confirmOperation({action:"queue-import",batches:queuedBatches,items:queuedBatches.map(function(b) { return {title:b.label + " → " + (b.group || "Ungrouped") + " · " + b.items.length + " wallpapers"} })}) }

    property string groupFilter: "All themes"
    property string search: ""
    property string statusText: "Ready"
    property string details: ""
    property var pending: null
    property var lastResult: ({})
    property string workerAction: ""
    property string operationSummary: ""
    property int failures: 0
    property color bg: ShellCommons.Color.background
    property color fg: ShellCommons.Color.foreground
    property color accent: ShellCommons.Color.accent
    property color surface: Qt.tint(bg, Qt.alpha(fg, 0.065))
    property color outline: Qt.alpha(fg, 0.18)
    readonly property string backend: Quickshell.env("HOME") + "/Projects/wallpaper-importer/wallpaper_manager.py"
    readonly property var visibleItems: items.filter(function(item) {
        return (groupFilter === "All themes" || (groupFilter === "Ungrouped" ? !item.group : item.group === groupFilter))
            && (!search || (item.title + " " + item.group + " " + item.slug).toLowerCase().indexOf(search.toLowerCase()) >= 0)
            && (mediaFilter.currentIndex === 0 || item.type === (mediaFilter.currentIndex === 1 ? "static" : "video"))
            && (desktopFilter.currentIndex === 0 || item.targets.indexOf(desktopFilter.currentIndex === 1 ? "omarchy" : "daemon-os") >= 0)
    })
    readonly property var selectedSlugs: Object.keys(selected).filter(function(key) { return selected[key] })
    readonly property var selectedCandidates: candidates.filter(function(item, index) { return incoming[String(index)] === true })

    function open() { opened = true; Qt.callLater(function() { card.forceActiveFocus() }); if (!busy) request({action: "snapshot"}) }
    function close() { opened = false }
    function toggle() { opened ? close() : open() }
    function request(payload) {
        if (busy) return false
        workerAction = payload.action
        lastResult = ({})
        statusText = payload.action === "snapshot" ? "Loading library…" : payload.action === "queue-import" ? "Starting background import…" : payload.action === "retry-preview" ? "Checking failed files…" : payload.action === "retry-failed" ? "Starting background retry…" : payload.action === "discover-folders" ? "Scanning selected folders…" : "Working…"
        return worker.send(payload)
    }
    function flip(key, adding) {
        var next = Object.assign({}, adding ? incoming : selected)
        next[String(key)] = !next[String(key)]
        if (adding) incoming = next; else selected = next
    }
    function updateCandidate(index, key, value) {
        var next = candidates.slice()
        var row = Object.assign({}, next[index]); row[key] = value; next[index] = row
        candidates = next
    }
    function chooseAll(adding) {
        var next = {}
        if (adding) candidates.forEach(function(item, index) { if (!item.installed) next[String(index)] = true })
        else visibleItems.forEach(function(item) { next[item.slug] = true })
        if (adding) incoming = next; else selected = next
    }
    function openFiles() { browser.pickFiles() }
    function openFolder() { browser.pickFolder() }
    function refreshBrowserPlaces() { placesWorker.send({action: "browser-places"}) }
    function discoverFolders(paths, options) {
        if (busy) return false
        page = "add"
        folderScanOptions = Object.assign({}, options, {target: target()})
        return request({action: "discover-folders", paths: paths, recursive: recursiveScan})
    }
    function discover(paths, recursive) { page = "add"; candidates = []; incoming = ({}); request({action: "discover", paths: paths, recursive: recursive === undefined ? recursiveScan : recursive}) }
    function confirmOperation(payload) { pending = payload; confirmation.open() }
    function target() { return ["both", "omarchy", "daemon-os"][targetBox.currentIndex] }
    function oneSelected() { return selectedSlugs.length === 1 ? selectedSlugs[0] : "" }
    function receive(event) {
        if (event.event === "progress") statusText = event.current + " / " + event.total + " · " + event.title
        if (event.event === "item") details += event.slug + ": " + event.status + "\n" + event.details + "\n"
        if (event.event !== "result") return
        lastResult = event
        if (!event.ok) { statusText = event.message; operationSummary = event.message; details += event.message + "\n"; if (workerAction === "retry-preview" || workerAction === "retry-failed") detailDialog.open(); return }
        if (event.jobs) backgroundJobs = event.jobs
        if (event.job_details !== undefined) { details = event.job_details; detailDialog.open() }
        if (event.queued_job && workerAction === "queue-import") { queuedBatches = []; candidates = []; incoming = ({}) }
        if (event.retry_preview) {
            var preview = event.retry_preview
            if (preview.count > 0) confirmOperation({action:"retry-failed",id:preview.id,retry_count:preview.count,retry_skipped:preview.skipped,items:preview.batches.map(function(batch) { return {title:batch.label + " → " + (batch.group || "Ungrouped") + " · " + batch.items.length + " wallpapers"} })})
            else { details = event.message; detailDialog.open() }
        }
        if (event.retry_empty) { details = event.message; detailDialog.open() }
        if (event.folder_batches) {
            var result = BatchModel.addFolders(queuedBatches, event.folder_batches, folderScanOptions, availableGroups)
            queuedBatches = result.batches
            statusText = result.added + " separate folder batches ready. Choose each group in Queue." + (result.skipped ? " " + result.skipped + " installed or queued sources skipped." : "")
            if (result.messages.length) { details += result.messages.join("\n") + "\n"; statusText += " See Details for empty folders or scan issues." }
            operationSummary = statusText
            folderBatchesReady()
        }
        if (event.items) { items = event.items; if (JSON.stringify(groups) !== JSON.stringify(event.groups)) groups = event.groups; selected = ({}); statusText = operationSummary || items.length + " themes · " + groups.length + " groups" }
        if (event.candidates) {
            candidates = event.candidates; incoming = ({})
            draftFolder = event.scan_folders && event.scan_folders.length ? event.scan_folders.join(", ") : candidates.length ? candidates[0].source.replace(/\/[^/]*$/, "") : ""
            chooseAll(true)
            var scope = event.scan_folders && event.scan_folders.length ? " · " + event.scan_folders.join(", ") + (event.recursive ? " (including subfolders)" : " (this folder only)") : ""
            statusText = candidates.length + " sources found" + scope + ". Review before importing."
            if (event.issues && event.issues.length) details += JSON.stringify(event.issues, null, 2) + "\n"
        }
        if (event.message) {
            operationSummary = event.message
            failures = event.results ? event.results.filter(function(r) { return r.status === "failed" }).length : 0
            statusText = event.message + (failures ? "  ·  " + failures + " failed — see Details" : "")
            operationSummary = statusText
        }
        if (event.results && workerAction === "import") {
            var selection = Object.assign({}, incoming)
            candidates = candidates.map(function(item, index) {
                var done = event.results.some(function(result) { return result.status === "done" && result.source === item.source && result.title === item.title })
                if (!done) return item
                selection[String(index)] = false
                return Object.assign({}, item, {installed: true})
            })
            incoming = selection
        }
    }
    IpcHandler {
        target: "daemon0.wallpaper-manager"
        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { root.toggle() }
        function status(): string { return JSON.stringify({revision: "modular-9-retry", draftLoaded: root.draftLoaded, places: root.browserPlaces, queuedBatches: root.queuedBatches.length, queuedWallpapers: root.queuedCount, jobs: root.backgroundJobs, opened: root.opened, busy: root.busy, page: root.page, themes: root.items.length, visible: root.visibleItems.length, groups: root.groups, selected: root.selectedSlugs, candidates: root.candidates.length, failures: root.failures, status: root.statusText, error: root.lastResult.ok === false ? root.lastResult.message : ""}) }
        function draft(): string { return JSON.stringify({batches:root.queuedBatches}) }
        function view(page: string): void {
            if (page === "folders") { root.page = "add"; root.open(); root.openFolder() }
            else if (page === "queue") { root.page = "add"; importPane.showQueue = true; root.open() }
            else if (page === "library" || page === "add") { root.page = page; root.open() }
        }
    }
    BackendRequest {
        id: worker
        backend: root.backend
        onEventReceived: event => root.receive(event)
        onDiagnostic: text => root.details += text + "\n"
        onFinished: {
            if (root.lastResult.ok && root.workerAction !== "snapshot" && root.workerAction !== "discover" && root.workerAction !== "discover-folders" && root.workerAction !== "retry-preview") {
                if (root.workerAction === "import" && !root.lastResult.results.some(function(r) { return r.status === "failed" })) {
                    root.candidates = []; root.incoming = ({}); root.page = "library"
                }
                refreshTimer.restart()
            }
        }
    }
    BackendRequest {
        id: draftWorker
        backend: root.backend
        onEventReceived: event => {
            if (event.draft_batches !== undefined) root.queuedBatches = event.draft_batches
            if (!event.ok) root.details += "Draft: " + event.message + "\n"
        }
        onFinished: {
            if (!root.draftLoaded) {
                root.draftLoaded = true
                if (root.opened) Qt.callLater(function() { root.request({action:"snapshot"}) })
            }
        }
    }
    Timer { id: draftSaveTimer; interval: 250; onTriggered: { if (draftWorker.busy) restart(); else draftWorker.send({action:"draft-save",batches:root.queuedBatches}) } }
    BackendRequest {
        id: placesWorker
        backend: root.backend
        onEventReceived: event => { if (event.ok && event.places) root.browserPlaces = event.places }
        onDiagnostic: text => root.details += text + "\n"
    }
    Process {
        id: jobPoll
        command: ["/usr/bin/python3", root.backend, "--request", '{"action":"jobs"}']
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var event = JSON.parse(text)
                    if (event.ok && event.jobs) {
                        var wasActive = root.activeJobs.length > 0
                        root.backgroundJobs = event.jobs
                        if (wasActive && !root.activeJobs.length && !root.busy) {
                            root.operationSummary = event.jobs.length ? event.jobs[0].message : "Background imports finished."
                            root.statusText = root.operationSummary
                            root.failures = event.jobs.length ? event.jobs[0].failed : 0
                            if (root.failures) root.details = root.operationSummary + "\nOpen Add wallpapers → Queue → Details for per-item results."
                            refreshTimer.restart()
                        }
                    }
                } catch(e) { }
            }
        }
    }
    Timer { interval: 1500; repeat: true; running: root.opened && root.activeJobs.length > 0; onTriggered: if (!jobPoll.running) jobPoll.running = true }
    Timer { id: refreshTimer; interval: 150; onTriggered: root.request({action: "snapshot"}) }
    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-wallpaper-manager"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        Rectangle { anchors.fill: parent; color: "#b0000000"; MouseArea { anchors.fill: parent; onClicked: root.close() } }
        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(1160, panel.width - 32); height: Math.min(780, panel.height - 32)
            color: root.bg; radius: 14; border.color: root.outline
            focus: true
            Keys.onPressed: function(event) {
                if (event.modifiers & Qt.ControlModifier) {
                    if (event.key === Qt.Key_F) { searchField.forceActiveFocus(); searchField.selectAll(); event.accepted = true }
                    else if (event.key === Qt.Key_A && !searchField.activeFocus && root.page === "library") { root.chooseAll(false); event.accepted = true }
                    else if (event.key === Qt.Key_O && !root.busy) { root.openFiles(); event.accepted = true }
                }
            }
            Keys.onEscapePressed: {
                if (browser.opened) browser.close()
                else if (confirmation.opened) confirmation.close()
                else if (detailDialog.opened) detailDialog.close()
                else root.close()
            }
            MouseArea { anchors.fill: parent; onClicked: card.forceActiveFocus() }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        spacing: 2
                        Label { text: "Wallpaper Manager"; color: root.fg; font.pixelSize: 22; font.bold: true }
                        Caption { text: "Your themes, your groups.  Super+Ctrl+M"; opacity: 0.65 }
                    }
                    Item { Layout.fillWidth: true }
                    ActionButton { text: "Library"; primary: root.page === "library"; onClicked: root.page = "library" }
                    ActionButton { text: "Add wallpapers"; primary: root.page === "add"; onClicked: root.page = "add" }
                    ActionButton { text: "Refresh"; enabled: !root.busy; onClicked: root.request({action: "snapshot"}) }
                    ActionButton { text: "Close"; onClicked: root.close() }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.outline }
                RowLayout {
                    visible: root.page === "library"
                    Layout.fillWidth: true
                    Field { id: searchField; placeholderText: "Search themes or groups…  Ctrl+F"; Layout.fillWidth: true; onTextChanged: root.search = text }
                    ThemedComboBox { id: mediaFilter; model: ["All media", "Static", "Video"]; implicitWidth: 112 }
                    ThemedComboBox { id: desktopFilter; model: ["All desktops", "Omarchy", "DaemonOS"]; implicitWidth: 132 }
                }
                LibraryPane { manager: root; Layout.fillWidth: true; Layout.fillHeight: true }
                ImportPane { id: importPane; manager: root; Layout.fillWidth: true; Layout.fillHeight: true }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.outline }
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: "Add / remove on:" }
                    ThemedComboBox { id: targetBox; currentIndex: 1; model: ["Both desktops", "Omarchy", "DaemonOS"]; implicitWidth: 145 }
                    BusyIndicator { running: root.busy; visible: root.busy; implicitWidth: 24; implicitHeight: 24 }
                    Caption { text: root.busy ? root.statusText : root.backgroundText || root.statusText; color: root.failures ? "#ffbd86" : root.fg; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
                    ActionButton { text: root.failures ? "Details (" + root.failures + ")" : "Details"; primary: root.failures > 0; onClicked: detailDialog.open() }
                    ActionButton { text: "Recovery"; onClicked: Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/Projects/wallpaper-importer/data/backups"]) }
                }
            }
            SourceBrowser { id: browser; manager: root; parent: card; anchors.centerIn: parent; onPicked: paths => { if (folderMode) root.discoverFolders(paths, importPane.batchOptions()); else root.discover(paths) } }
            Dialog {
                id: confirmation
                popupType: Popup.Item
                anchors.centerIn: parent; width: Math.min(560, card.width - 50); modal: true; title: root.pending && root.pending.action === "delete-group" ? "Dissolve group?" : "Review operation"
                standardButtons: Dialog.Ok | Dialog.Cancel
                contentItem: ColumnLayout {
                    spacing: 12
                    Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.pending ? root.pending.action === "retry-failed" ? "Retry " + root.pending.retry_count + " failed or unfinished wallpapers in the background?" : (root.pending.action === "delete-group" ? "Move all themes in “" + root.pending.old + "” out of the group. Their files are kept." : (root.pending.action === "queue-import" ? "Start " : root.pending.action === "import" ? "Import " : "Remove ") + root.pending.items.length + (root.pending.action === "queue-import" ? " batches in the background?" : " selected themes on " + root.pending.target + "?")) : "" }
                    Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.pending && root.pending.action === "retry-failed" ? "The retry keeps the original folders, groups and import settings. Your separate queue stays saved. You can close the window after starting." : root.pending && root.pending.action === "remove" ? "Active and packaged themes are protected. Originals are kept; installed files move into recovery." : root.pending && root.pending.action === "queue-import" ? "You can close the window. Batches run in order and a notification appears when finished. The current wallpaper stays selected." : "The current wallpaper will stay selected. Each item gets a result in Details." }
                    ScrollView { visible: root.pending && root.pending.items !== undefined; Layout.fillWidth: true; Layout.preferredHeight: 140
                        TextArea { readOnly: true; wrapMode: Text.Wrap; text: root.pending && root.pending.items ? root.pending.items.map(function(item) { return (item.title || item.slug) + (root.pending.action === "import" ? "  ·  " + (item.group || "Ungrouped") : "") }).join("\n") : "" }
                    }
                }
                onAccepted: if (root.pending) { var payload = Object.assign({}, root.pending); payload.confirmed = true; root.details = ""; root.request(payload); root.pending = null }
            }
            Dialog {
                id: detailDialog; popupType: Popup.Item; anchors.centerIn: parent; width: Math.min(800, card.width - 40); height: Math.min(500, card.height - 40); modal: true; title: "Operation details"; standardButtons: Dialog.Close
                contentItem: ScrollView { TextArea { text: root.details || "No operations yet."; readOnly: true; selectByMouse: true; wrapMode: Text.Wrap; font.pixelSize: 12 } }
            }
        }
    }
}
