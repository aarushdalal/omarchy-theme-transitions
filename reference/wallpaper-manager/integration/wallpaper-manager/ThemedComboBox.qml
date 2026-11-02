import QtQuick
import QtQuick.Controls.Basic as Basic
import qs.Commons as ShellCommons

// Keep Qt's selection, popup and keyboard behavior; only the local material changes.
Basic.ComboBox {
    id: picker
    implicitWidth: 140
    implicitHeight: 36
    ManagerMotion { id: motion }
    font.pixelSize: 12
    hoverEnabled: true
    focusPolicy: Qt.ClickFocus | Qt.TabFocus

    palette.text: picker.enabled ? ShellCommons.Color.foreground : Qt.alpha(ShellCommons.Color.foreground, 0.42)
    palette.buttonText: picker.enabled ? ShellCommons.Color.foreground : Qt.alpha(ShellCommons.Color.foreground, 0.42)
    palette.base: ShellCommons.Color.background
    palette.button: Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.04))
    palette.window: Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.04))
    palette.windowText: ShellCommons.Color.foreground
    palette.dark: Qt.alpha(ShellCommons.Color.foreground, 0.7)
    palette.mid: Qt.alpha(ShellCommons.Color.foreground, 0.18)
    palette.highlight: Qt.alpha(ShellCommons.Color.accent, 0.28)
    palette.highlightedText: ShellCommons.Color.foreground
    palette.disabled.text: Qt.alpha(ShellCommons.Color.foreground, 0.42)
    palette.disabled.buttonText: Qt.alpha(ShellCommons.Color.foreground, 0.42)
    palette.disabled.windowText: Qt.alpha(ShellCommons.Color.foreground, 0.42)

    background: Rectangle {
        radius: 8
        color: picker.hovered && picker.enabled
            ? Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.08))
            : picker.palette.button
        border.color: picker.activeFocus ? ShellCommons.Color.accent
            : Qt.alpha(ShellCommons.Color.foreground, picker.enabled ? 0.18 : 0.1)
        Behavior on color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
        Behavior on border.color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
    }
}
