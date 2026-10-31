import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Dialog {
    id: history
    property var manager
    readonly property var activeRetries: manager.backgroundJobs.filter(function(job) { return job.retry_of && (job.state === "pending" || job.state === "running") }).map(function(job) { return job.retry_of })
    width: Math.min(860, parent.width - 24)
    height: Math.min(440, parent.height - 16)
    modal: true; popupType: Popup.Item
    title: "Import history"
    header: Label { text: history.title; padding: 10; color: history.manager.fg; font.pixelSize: 16; font.bold: true; background: Rectangle { color: "transparent" } }
    footer: Item {
        implicitHeight: 44
        ActionButton { objectName: "history-close"; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Close"; onClicked: history.close() }
    }
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
                ActionButton { objectName: "history-details-" + modelData.id; text: "Details"; enabled: !history.manager.busy; onClicked: { history.close(); history.manager.request({action:"job-details",id:modelData.id}) } }
                ActionButton {
                    objectName: "retry-failed-" + modelData.id
                    visible: modelData.failed > 0 || modelData.state === "interrupted" || modelData.state === "failed"
                    text: history.activeRetries.indexOf(modelData.id) >= 0 ? "Retry running" : modelData.state === "pending" || modelData.state === "running" ? "Retry after finish" : "Retry failed…"
                    enabled: !history.manager.busy && modelData.state !== "pending" && modelData.state !== "running" && history.activeRetries.indexOf(modelData.id) < 0
                    onClicked: { history.close(); history.manager.request({action:"retry-preview",id:modelData.id}) }
                }
            }
        }
    }
    background: Rectangle { color: history.manager.bg; radius: 10; border.color: history.manager.outline }
}
