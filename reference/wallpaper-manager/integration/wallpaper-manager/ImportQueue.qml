import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
ColumnLayout {
    id: pane
    property var manager
    readonly property var runningJobs: manager.backgroundJobs.filter(function(job) { return job.state === "running" || job.state === "pending" })
    signal addFolderRequested()
    function syncRows() {
        var rows = manager.queuedBatches
        while (batchRows.count > rows.length) batchRows.remove(batchRows.count - 1)
        rows.forEach(function(row, index) {
            var serialized = JSON.stringify(row)
            if (index >= batchRows.count) batchRows.append({batchJson: serialized})
            else if (batchRows.get(index).batchJson !== serialized) batchRows.setProperty(index, "batchJson", serialized)
        })
    }
    Component.onCompleted: syncRows()
    Connections { target: pane.manager; function onQueuedBatchesChanged() { pane.syncRows() } }
    ListModel { id: batchRows }
    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
    RowLayout {
        Layout.fillWidth: true
        Caption { Layout.fillWidth: true; text: manager.queuedBatches.length + " batches · " + manager.queuedCount + " wallpapers queued"; font.bold: true }
        ActionButton { text: "Add folders…"; enabled: !manager.busy; onClicked: pane.addFolderRequested() }
        ActionButton { text: "Clear queue"; enabled: !manager.busy && manager.queuedBatches.length > 0; onClicked: manager.queuedBatches = [] }
    }
    Caption { Layout.fillWidth: true; text: "Each folder stays separate. Choose a group for each batch, or leave it ungrouped. Nothing imports until you start."; opacity: 0.7 }
    ListView {
        id: batches
        objectName: "queue-batch-list"
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
        model: batchRows
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property string batchJson
            property var modelData: JSON.parse(batchJson)
            required property int index
            onModelDataChanged: Qt.callLater(function() { groupChoice.setGroup(modelData.group) })
            width: ListView.view.width; height: 96; radius: 8; color: manager.surface
            RowLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 10
                Caption { text: (index + 1) + "."; opacity: 0.6 }
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    Caption { Layout.fillWidth: true; text: modelData.label.split("/").pop() || modelData.label; elide: Text.ElideMiddle; maximumLineCount: 1; font.bold: true }
                    Caption { Layout.fillWidth: true; text: modelData.label; elide: Text.ElideMiddle; maximumLineCount: 1; opacity: 0.65; font.pixelSize: 10 }
                    Caption { text: modelData.items.length + " wallpapers · " + modelData.target; opacity: 0.6 }
                }
                GroupPicker { id: groupChoice; objectName: "queue-group-" + index; enabled: !manager.busy; groups: manager.availableGroups || manager.groups; Layout.preferredWidth: 200; Component.onCompleted: setGroup(modelData.group); onGroupsChanged: Qt.callLater(function() { setGroup(modelData.group) }); onGroupEdited: value => manager.setQueuedGroup(index, value) }
                ActionButton { text: "↑"; enabled: !manager.busy && index > 0; onClicked: manager.moveBatch(index, -1) }
                ActionButton { text: "↓"; enabled: !manager.busy && index < manager.queuedBatches.length - 1; onClicked: manager.moveBatch(index, 1) }
                ActionButton { objectName: "remove-batch-" + index; text: "Remove"; enabled: !manager.busy; onClicked: manager.removeBatch(index) }
            }
        }
        Caption { anchors.centerIn: parent; visible: !manager.queuedBatches.length; text: "Prepare a folder, choose its group, then add it to the queue."; opacity: 0.65 }
    }
    Rectangle {
        objectName: "active-job-progress"
        visible: pane.runningJobs.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? 72 : 0
        radius: 8; color: manager.surface
        readonly property var job: pane.runningJobs.length ? pane.runningJobs[0] : ({})
            RowLayout {
                anchors.fill: parent; anchors.margins: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    Caption { Layout.fillWidth: true; maximumLineCount: 1; elide: Text.ElideRight; text: pane.runningJobs.length ? "Background: " + pane.runningJobs[0].completed + "/" + pane.runningJobs[0].total + " · " + (pane.runningJobs[0].current_title || "Waiting to import…") : "" }
                    Caption { text: pane.runningJobs.length ? pane.runningJobs[0].done + " imported · " + pane.runningJobs[0].failed + " failed" + (pane.runningJobs.length > 1 ? " · " + (pane.runningJobs.length-1) + " more jobs waiting" : "") : ""; opacity: 0.65 }
                }
                ActionButton { text: "Details"; enabled: !manager.busy && pane.runningJobs.length > 0; onClicked: manager.request({action:"job-details",id:pane.runningJobs[0].id}) }
            }
    }
    RowLayout {
        Layout.fillWidth: true
        Caption { Layout.fillWidth: true; text: "Imports keep running after you close this window. A notification appears when finished."; opacity: 0.7 }
        ActionButton { text: "Hide window"; onClicked: manager.close() }
        ActionButton { objectName: "start-background-queue"; text: "Start in background…"; primary: true; enabled: !manager.busy && manager.queuedBatches.length > 0; onClicked: manager.startQueue() }
    }
}
