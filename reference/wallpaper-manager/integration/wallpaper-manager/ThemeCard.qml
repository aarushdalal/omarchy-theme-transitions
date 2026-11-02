import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: card
    objectName: "theme-card-" + theme.slug
    required property var theme
    required property var manager
    property bool keyboardFocused: false
    readonly property bool selected: manager.selected[theme.slug] === true
    signal toggleRequested()
    signal selectionRequested(int modifiers)
    signal applyRequested()
    ManagerMotion { id: motion }

    Rectangle {
        id: body
        objectName: "theme-card-surface"
        anchors.fill: parent; anchors.margins: 5
        radius: 12
        color: Qt.tint(card.manager.bg, Qt.alpha(card.manager.fg, card.selected ? 0.075 : hoverArea.containsMouse ? 0.055 : 0.032))
        border.width: card.selected || card.keyboardFocused ? 2 : 1
        border.color: card.selected || card.keyboardFocused ? Qt.alpha(card.manager.accent, 0.85)
            : Qt.alpha(card.manager.fg, hoverArea.containsMouse ? 0.26 : 0.12)
        Behavior on color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
        Behavior on border.color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }

        Column {
            anchors.fill: parent; anchors.margins: 6; spacing: 0
            Item {
                width: parent.width; height: Math.max(92, body.height - 78); clip: true
                Rectangle { anchors.fill: parent; color: Qt.alpha(card.manager.fg, 0.025) }
                Image {
                    id: artwork
                    anchors.fill: parent
                    source: card.theme.preview
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 480
                }
                Text {
                    anchors.centerIn: parent
                    visible: artwork.status !== Image.Ready
                    text: artwork.status === Image.Error ? "Preview unavailable" : "Loading preview…"
                    color: Qt.alpha(card.manager.fg, 0.64); font.pixelSize: 11
                }
                Rectangle {
                    x: 7; y: 7; width: badge.implicitWidth + 14; height: 22; radius: 6
                    color: Qt.alpha(card.manager.bg, 0.94)
                    border.color: Qt.alpha(card.manager.fg, card.theme.active ? 0.28 : 0.12)
                    Text {
                        id: badge; anchors.centerIn: parent
                        text: card.theme.active ? "●  Active" : card.theme.type === "video" ? "Video" : card.theme.stock ? "Default" : "Static"
                        color: card.theme.active ? card.manager.accent : Qt.alpha(card.manager.fg, 0.84)
                        font.pixelSize: 10; font.weight: Font.Medium
                    }
                }
            }
            Item {
                width: parent.width; height: 66
                Column {
                    anchors.fill: parent; anchors.leftMargin: 4; anchors.rightMargin: 4; anchors.topMargin: 9; spacing: 5
                    Text {
                        width: parent.width; height: 32; text: card.theme.title
                        color: card.manager.fg; font.pixelSize: 12; font.weight: Font.Medium
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text { width: parent.width; text: card.theme.group || "Ungrouped"; color: Qt.alpha(card.manager.fg, 0.62); font.pixelSize: 10; elide: Text.ElideRight }
                }
            }
        }
        MouseArea {
            id: hoverArea
            anchors.fill: parent; hoverEnabled: true
            onClicked: mouse => card.selectionRequested(mouse.modifiers)
            onDoubleClicked: mouse => { if (mouse.modifiers === Qt.NoModifier) card.applyRequested() }
        }
        CheckBox {
            id: check
            objectName: "theme-checkbox-" + card.theme.slug
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
            checked: card.selected
            onClicked: card.toggleRequested()
            padding: 3
            focusPolicy: Qt.ClickFocus | Qt.TabFocus
            indicator: Rectangle {
                implicitWidth: 22; implicitHeight: 22; radius: 6
                color: card.selected ? card.manager.accent : Qt.alpha(card.manager.bg, 0.94)
                border.color: check.activeFocus ? card.manager.accent : card.selected ? card.manager.accent : Qt.alpha(card.manager.fg, 0.6)
                border.width: check.activeFocus ? 2 : 1
                Text { anchors.centerIn: parent; text: card.selected ? "✓" : ""; font.pixelSize: 15; font.bold: true; color: card.manager.bg }
                Behavior on color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
            }
        }
    }
}
