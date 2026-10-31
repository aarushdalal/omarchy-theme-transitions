import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Dialog {
    id: history
    property var manager
    width: Math.min(860, parent.width - 24)
    height: Math.min(440, parent.height - 16)
    modal: true; popupType: Popup.Item
    title: "Import history"
    standardButtons: Dialog.Close
    contentItem: ListView {
        clip: true; spacing: 8; model: history.manager.backgroundJobs
        ScrollBar.vertical: ScrollBar {}
        delegate: Rectangle {
            required property var modelData
            width: ListView.view.width; height: 82; radius: 8; color: history.manager.surface
            RowLayout {
                anchors.fill: parent; anchors.margins: 10
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    Caption { Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight; text: modelData.message }
                    Caption { Layout.fillWidth: true; maximumLineCount: 1; elide: Text.ElideRight; opacity: 0.65; text: modelData.id + " · " + modelData.completed + "/" + modelData.total + " processed · " + modelData.failed + " failed" }
                }
                ActionButton { text: "Details"; enabled: !history.manager.busy; onClicked: { history.close(); history.manager.request({action:"job-details",id:modelData.id}) } }
            }
        }
    }
    background: Rectangle { color: history.manager.bg; radius: 10; border.color: history.manager.outline }
}
