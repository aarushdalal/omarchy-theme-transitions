import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons as ShellCommons

TextField {
    id: field
    property bool transparentBackground: false
    ManagerMotion { id: motion }
    Layout.minimumWidth: 0
    hoverEnabled: true
    color: ShellCommons.Color.foreground
    selectByMouse: true
    font.pixelSize: 12
    leftPadding: 12; rightPadding: 12
    placeholderTextColor: Qt.alpha(color, 0.52)
    selectionColor: Qt.alpha(ShellCommons.Color.accent, 0.28)
    selectedTextColor: color
    background: Rectangle {
        implicitHeight: 36
        radius: 8
        color: field.transparentBackground ? "transparent" : Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, field.activeFocus ? 0.05 : 0.028))
        border.color: field.activeFocus ? Qt.alpha(ShellCommons.Color.accent, 0.86) : Qt.alpha(ShellCommons.Color.foreground, field.hovered ? 0.26 : 0.14)
        Behavior on color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
        Behavior on border.color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
    }
}
