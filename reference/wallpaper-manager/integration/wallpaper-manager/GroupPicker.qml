import QtQuick
import QtQuick.Controls.Basic as Basic
import qs.Commons as ShellCommons
Basic.ComboBox {
    id: picker
    property var groups: []
    readonly property string groupValue: editText.trim() === "Ungrouped" ? "" : editText.trim()
    signal groupEdited(string value)
    model: ["Ungrouped"].concat(groups)
    editable: true
    implicitWidth: 190
    implicitHeight: 34
    palette.text: ShellCommons.Color.foreground
    palette.buttonText: ShellCommons.Color.foreground
    palette.base: ShellCommons.Color.background
    palette.button: ShellCommons.Color.background
    palette.window: ShellCommons.Color.background
    palette.windowText: ShellCommons.Color.foreground
    palette.highlight: Qt.alpha(ShellCommons.Color.accent, 0.28)
    palette.highlightedText: ShellCommons.Color.foreground
    background: Rectangle { color: Qt.tint(ShellCommons.Color.background, Qt.alpha(ShellCommons.Color.foreground, 0.04)); radius: 6; border.color: picker.activeFocus ? ShellCommons.Color.accent : Qt.alpha(ShellCommons.Color.foreground, 0.2) }
    function setGroup(value) { var i = model.indexOf(value || "Ungrouped"); currentIndex = i >= 0 ? i : 0; editText = value || "Ungrouped" }
    onActivated: groupEdited(groupValue)
    onAccepted: groupEdited(groupValue)
    onActiveFocusChanged: if (!activeFocus) groupEdited(groupValue)
}
