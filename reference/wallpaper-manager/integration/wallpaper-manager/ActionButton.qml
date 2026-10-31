import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons as ShellCommons
Button {
    id: button
    property bool primary: false
    implicitHeight: 34
    Layout.minimumWidth: 0
    leftPadding: 12; rightPadding: 12
    contentItem: Text {
        text: button.text
        color: button.enabled ? ShellCommons.Color.foreground : Qt.alpha(ShellCommons.Color.foreground, 0.42)
        font.pixelSize: 12; elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 7
        color: button.down ? Qt.alpha(ShellCommons.Color.accent, 0.4) : button.hovered ? Qt.alpha(ShellCommons.Color.accent, 0.24) : button.primary ? Qt.alpha(ShellCommons.Color.accent, 0.18) : Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.065))
        border.color: button.primary ? ShellCommons.Color.accent : Qt.alpha(ShellCommons.Color.foreground, 0.18)
    }
}
