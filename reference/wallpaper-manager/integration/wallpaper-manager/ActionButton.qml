import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons as ShellCommons

Button {
    id: button
    property bool primary: false
    property bool quiet: false
    property bool destructive: false
    readonly property color roleColor: destructive ? "#c99c9c" : ShellCommons.Color.accent
    ManagerMotion { id: motion }
    focusPolicy: Qt.ClickFocus | Qt.TabFocus
    implicitHeight: 36
    Layout.minimumWidth: 0
    leftPadding: 14; rightPadding: 14
    scale: button.down && !motion.reducedMotion ? 0.985 : 1
    Behavior on scale { enabled: !motion.reducedMotion; NumberAnimation { duration: motion.micro; easing.type: motion.easing } }
    contentItem: Text {
        text: button.text
        color: button.enabled ? (button.destructive ? button.roleColor : ShellCommons.Color.foreground) : Qt.alpha(ShellCommons.Color.foreground, 0.42)
        font.pixelSize: 12
        font.weight: button.primary ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 8
        color: button.down && button.enabled ? Qt.tint(ShellCommons.Color.background, Qt.alpha(button.roleColor, 0.24))
            : button.hovered && button.enabled ? Qt.tint(ShellCommons.Color.background, Qt.alpha(button.roleColor, 0.13))
            : button.primary ? Qt.tint(ShellCommons.Color.background, Qt.alpha(button.roleColor, button.enabled ? 0.14 : 0.045))
            : button.quiet ? "transparent" : Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.04))
        border.color: button.activeFocus ? button.roleColor
            : button.primary && button.enabled ? Qt.alpha(button.roleColor, 0.58)
            : button.quiet ? "transparent" : Qt.alpha(ShellCommons.Color.foreground, button.enabled ? 0.14 : 0.08)
        Behavior on color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
        Behavior on border.color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
    }
}
