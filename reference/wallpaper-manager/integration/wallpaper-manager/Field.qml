import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons as ShellCommons
TextField {
    id: field
    property bool transparentBackground: false
    Layout.minimumWidth: 0
    color: ShellCommons.Color.foreground; selectByMouse: true; font.pixelSize: 12
    placeholderTextColor: Qt.alpha(color, 0.5)
    selectionColor: Qt.alpha(ShellCommons.Color.accent, 0.28)
    selectedTextColor: color
    background: Rectangle { implicitHeight: 34; radius: 6; color: field.transparentBackground ? "transparent" : Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.025)); border.color: field.activeFocus ? ShellCommons.Color.accent : Qt.alpha(ShellCommons.Color.foreground, 0.18) }
}
