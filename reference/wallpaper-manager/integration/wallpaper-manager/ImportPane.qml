import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Selection.js" as Selection
import "ImportBatchModel.js" as BatchModel
ColumnLayout {
                    id: pane
                    property string anchor: ""
                    property bool showQueue: false
                    function batchOptions() { return {mode: ["auto", "static", "video"][importMode.currentIndex], allow_static_scenes: allowStatic.checked, replace: replaceExisting.checked} }
                    function selectRow(index, modifiers, toggle) {
                        var keys = manager.candidates.map(function(item, i) { return String(i) })
                        var result = Selection.select(keys, manager.incoming, String(index), modifiers, anchor, toggle)
                        manager.incoming = result.selected; anchor = result.anchor
                        incomingList.currentIndex = index; incomingList.forceActiveFocus()
                    }
                    property var manager
                    visible: manager.page === "add"; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton { text: "Prepare batch"; primary: !pane.showQueue; onClicked: pane.showQueue = false }
                        ActionButton { objectName: "queue-tab"; text: "Queue (" + manager.queuedBatches.length + ")"; primary: pane.showQueue; onClicked: pane.showQueue = true }
                        Caption { Layout.fillWidth: true; text: manager.queuedCount + " wallpapers queued"; opacity: 0.65 }
                        ActionButton { objectName: "job-history"; text: "History (" + manager.backgroundJobs.length + ")"; enabled: !manager.busy && manager.backgroundJobs.length > 0; onClicked: history.open() }
                    }
                    JobHistory { id: history; objectName: "job-history-dialog"; manager: pane.manager; parent: pane; anchors.centerIn: parent }
                    ImportQueue { manager: pane.manager; visible: pane.showQueue; onAddFolderRequested: { pane.showQueue = false; manager.openFolder() } }
                    ColumnLayout {
                    visible: !pane.showQueue; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton { objectName: "choose-files"; text: "Choose files…"; primary: true; enabled: !manager.busy; onClicked: manager.openFiles() }
                        ActionButton { text: "Scan folders…"; enabled: !manager.busy; onClicked: manager.openFolder() }
                        Field { id: sourcePath; Layout.fillWidth: true; placeholderText: "Or paste a file, folder or Workshop ID"; onAccepted: if (text.trim() && !manager.busy) manager.discover([text.trim()], subfolders.checked) }
                        ActionButton { text: "Scan"; enabled: !manager.busy && sourcePath.text.trim().length > 0; onClicked: manager.discover([sourcePath.text.trim()], subfolders.checked) }
                    }
                    SelectionCheckBox { id: subfolders; objectName: "include-subfolders"; text: "Include subfolders"; checked: false; onToggled: manager.recursiveScan = checked }
                    Caption { Layout.fillWidth: true; text: "Click a row · Ctrl-click to add/remove · Shift-click for a range. Review names and choose a group for this batch. Blank means ungrouped. Imports do not change your current wallpaper."; opacity: 0.7 }
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton { text: "Select available"; onClicked: manager.chooseAll(true) }
                        ActionButton { text: "Clear"; onClicked: { manager.incoming = ({}); pane.anchor = "" } }
                        Caption { text: "Batch group:" }
                        GroupPicker { id: batchGroup; objectName: "batch-group"; groups: manager.groups; Layout.fillWidth: true }
                    }
                    ListView {
                        id: incomingList
                        activeFocusOnTab: true
                        keyNavigationEnabled: true
                        Keys.onPressed: function(event) {
                            if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) { manager.chooseAll(true); event.accepted = true }
                            else if (event.key === Qt.Key_Space && currentIndex >= 0) { pane.selectRow(currentIndex, event.modifiers, true); event.accepted = true }
                            else if ((event.key === Qt.Key_Up || event.key === Qt.Key_Down) && count) {
                                var next = Math.max(0, Math.min(count - 1, currentIndex + (event.key === Qt.Key_Up ? -1 : 1)))
                                if (event.modifiers & Qt.ControlModifier) currentIndex = next
                                else pane.selectRow(next, event.modifiers, false)
                                positionViewAtIndex(next, ListView.Contain); event.accepted = true
                            }
                        }
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6; model: manager.candidates
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            objectName: "import-row-" + index
                            readonly property bool packageSource: [".pkg", ".tex", ".json"].indexOf(modelData.type) >= 0
                            width: ListView.view.width; height: packageSource ? 116 : 80; color: manager.incoming[String(index)] ? Qt.tint(manager.surface, Qt.alpha(manager.accent, 0.18)) : manager.surface; radius: 8
                            border.color: manager.incoming[String(index)] ? manager.accent : "transparent"
                            MouseArea { anchors.fill: parent; onClicked: mouse => pane.selectRow(index, mouse.modifiers, false) }
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 8
                                SelectionCheckBox { checked: manager.incoming[String(index)] === true; onClicked: pane.selectRow(index, 0, true) }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 5
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Field { Layout.fillWidth: true; transparentBackground: true; color: "#ffffff"; text: modelData.title; onEditingFinished: manager.updateCandidate(index, "title", text) }
                                        Caption { Layout.preferredWidth: Math.min(230, parent.width * 0.32); Layout.minimumWidth: 100; text: batchGroup.groupValue || "Ungrouped"; elide: Text.ElideRight; maximumLineCount: 1 }
                                        Caption { text: modelData.installed ? "Installed" : modelData.type }
                                    }
                                    Text { Layout.fillWidth: true; text: modelData.source; elide: Text.ElideMiddle; color: Qt.alpha(manager.fg, 0.55); font.pixelSize: 10 }
                                    Field { visible: packageSource; Layout.fillWidth: true; transparentBackground: true; color: "#ffffff"; text: modelData.asset || ""; placeholderText: "Asset filename (optional; choose from Details if a package contains several)"; onEditingFinished: manager.updateCandidate(index, "asset", text) }
                                }
                            }
                        }
                        Label { anchors.centerIn: parent; visible: !manager.candidates.length; text: "Choose files or scan a folder to start"; color: Qt.alpha(manager.fg, 0.5) }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        ThemedComboBox { id: importMode; implicitWidth: 160; Layout.minimumWidth: 160; model: ["Automatic media", "Static image", "Video only"] }
                        SelectionCheckBox { id: allowStatic; text: "Allow still recovery for scenes" }
                        SelectionCheckBox { id: replaceExisting; text: "Replace existing (with backup)" }
                        Item { Layout.fillWidth: true }
                        ActionButton { objectName: "add-batch-queue"; text: "Add " + manager.selectedCandidates.length + " to queue"; primary: true; enabled: !manager.busy && manager.selectedCandidates.length > 0; onClicked: if (manager.queueBatch(batchGroup.groupValue, pane.batchOptions())) pane.showQueue = true }
                    }
                    }
                    Connections {
                        target: pane.manager
                        ignoreUnknownSignals: true
                        function onFolderBatchesReady() { pane.showQueue = true }
                        function onDraftFolderChanged() {
                            var name = pane.manager.draftFolder.split("/").pop()
                            batchGroup.setGroup(BatchModel.matchKnownGroup(name, pane.manager.groups))
                        }
                    }
                }
