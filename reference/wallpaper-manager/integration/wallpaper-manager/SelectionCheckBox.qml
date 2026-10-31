import QtQuick
import QtQuick.Controls
import qs.Commons as ShellCommons
CheckBox {
    id: control
    implicitHeight: 30
    implicitWidth: 26 + (text ? 8 + label.implicitWidth : 0)
    padding: 2; spacing: 8
    indicator: Rectangle {
        x: control.leftPadding; y: (control.height - height) / 2
        implicitWidth: 22; implicitHeight: 22; radius: 5
        color: control.checked ? ShellCommons.Color.accent : Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.06))
        border.color: control.checked ? ShellCommons.Color.accent : Qt.alpha(ShellCommons.Color.foreground, 0.65)
        border.width: 1.5
        Text { anchors.centerIn: parent; text: control.checked ? "✓" : ""; color: ShellCommons.Color.background; font.pixelSize: 16; font.bold: true }
    }
    contentItem: Text { id: label; text: control.text; leftPadding: control.indicator.width + control.spacing; verticalAlignment: Text.AlignVCenter; color: ShellCommons.Color.foreground; font.pixelSize: 12 }
}
