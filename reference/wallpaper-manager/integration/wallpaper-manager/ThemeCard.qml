import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    id: card
    objectName: "theme-card-" + theme.slug
    required property var theme
    required property var manager
    readonly property bool selected: manager.selected[theme.slug] === true
    signal toggleRequested()
    signal selectionRequested(int modifiers)
    signal applyRequested()
    Rectangle {
        anchors.fill: parent; anchors.margins: 4
        radius: 9; clip: true; color: card.manager.surface
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? card.manager.accent : card.manager.outline
        Column {
            anchors.fill: parent; anchors.margins: 2; spacing: 0
            Item {
                width: parent.width; height: 94; clip: true
                Image { anchors.fill: parent; source: card.theme.preview; asynchronous: true; fillMode: Image.PreserveAspectCrop; sourceSize.width: 480 }
                Rectangle {
                    x: 6; y: 6; width: badge.implicitWidth + 12; height: 21; radius: 5; color: "#e5161619"
                    Text { id: badge; anchors.centerIn: parent; text: card.theme.active ? "Active" : card.theme.type === "video" ? "Video" : card.theme.stock ? "Default" : "Static"; color: "white"; font.pixelSize: 10 }
                }
            }
            Item {
                width: parent.width; height: 64
                Column {
                    anchors.fill: parent; anchors.margins: 7; spacing: 4
                    Text { width: parent.width; height: 32; text: card.theme.title; color: card.manager.fg; font.pixelSize: 12; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                    Text { width: parent.width; text: card.theme.group || "Ungrouped"; color: Qt.alpha(card.manager.fg, 0.6); font.pixelSize: 10; elide: Text.ElideRight }
                }
            }
        }
        MouseArea { anchors.fill: parent; onClicked: mouse => card.selectionRequested(mouse.modifiers); onDoubleClicked: mouse => { if (mouse.modifiers === Qt.NoModifier) card.applyRequested() } }
        CheckBox {
            id: check
            objectName: "theme-checkbox-" + card.theme.slug
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 5
            checked: card.selected
            onClicked: card.toggleRequested()
            padding: 3
            indicator: Rectangle {
                implicitWidth: 23; implicitHeight: 23; radius: 5
                color: card.selected ? card.manager.accent : "#ed17191c"
                border.color: card.selected ? card.manager.accent : "#c5c8ce"; border.width: 1.5
                Text { anchors.centerIn: parent; text: card.selected ? "✓" : ""; font.pixelSize: 17; font.bold: true; color: card.manager.bg }
            }
        }
    }
}
