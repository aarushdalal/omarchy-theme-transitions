import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
ColumnLayout {
    id: pane
    property var manager
    signal addFolderRequested()
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
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 8
        model: manager.queuedBatches
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            required property int index
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
                GroupPicker { objectName: "queue-group-" + index; enabled: !manager.busy; groups: manager.availableGroups || manager.groups; Layout.preferredWidth: 200; Component.onCompleted: setGroup(modelData.group); onGroupsChanged: Qt.callLater(function() { setGroup(modelData.group) }); onGroupEdited: value => manager.setQueuedGroup(index, value) }
                ActionButton { text: "↑"; enabled: !manager.busy && index > 0; onClicked: manager.moveBatch(index, -1) }
                ActionButton { text: "↓"; enabled: !manager.busy && index < manager.queuedBatches.length - 1; onClicked: manager.moveBatch(index, 1) }
                ActionButton { objectName: "remove-batch-" + index; text: "Remove"; enabled: !manager.busy; onClicked: manager.removeBatch(index) }
            }
        }
        Caption { anchors.centerIn: parent; visible: !manager.queuedBatches.length; text: "Prepare a folder, choose its group, then add it to the queue."; opacity: 0.65 }
    }
    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(manager.backgroundJobs.length * 72, Math.max(68, pane.height * 0.28))
        clip: true; spacing: 4
        model: manager.backgroundJobs
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            width: ListView.view.width; height: 68; radius: 8; color: manager.surface
            RowLayout {
                anchors.fill: parent; anchors.margins: 10
                ColumnLayout {
                    Layout.fillWidth: true
                    Caption { Layout.fillWidth: true; maximumLineCount: 1; elide: Text.ElideRight; text: modelData.state === "pending" ? "Waiting in the background queue" : modelData.state === "running" ? "Batch " + modelData.batch + "/" + modelData.batches + " · " + (modelData.current_title || modelData.label || "Importing…") : modelData.message }
                    Caption { text: modelData.completed + "/" + modelData.total + " processed · " + modelData.done + " imported · " + modelData.failed + " failed"; opacity: 0.65 }
                }
                ActionButton { text: "Details"; enabled: !manager.busy; onClicked: manager.request({action:"job-details",id:modelData.id}) }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Caption { Layout.fillWidth: true; text: "Imports keep running after you close this window. A notification appears when finished."; opacity: 0.7 }
        ActionButton { text: "Hide window"; onClicked: manager.close() }
        ActionButton { objectName: "start-background-queue"; text: "Start in background…"; primary: true; enabled: !manager.busy && manager.queuedBatches.length > 0; onClicked: manager.startQueue() }
    }
}
