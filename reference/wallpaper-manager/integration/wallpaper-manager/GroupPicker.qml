import QtQuick
import QtQuick.Controls.Basic as Basic
import qs.Commons as ShellCommons

Basic.ComboBox {
    id: picker
    property var groups: []
    property string currentGroup: ""
    readonly property string groupValue: currentGroup
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

    Timer {
        id: commitTimer
        interval: 250
        repeat: false
        onTriggered: picker.commit()
    }

    function commit() {
        commitTimer.stop()
        var val = editText ? editText.trim() : ""
        if (val === "Ungrouped") val = ""
        currentGroup = val
        groupEdited(val)
        applyGroup()
    }

    onEditTextChanged: if (activeFocus) commitTimer.restart()

    function applyGroup() {
        var target = currentGroup || "Ungrouped"
        var idx = -1
        for (var i = 0; i < model.length; i++) {
            if (model[i] && model[i].toLowerCase() === target.toLowerCase()) {
                idx = i
                break
            }
        }
        currentIndex = idx
        editText = currentGroup || "Ungrouped"
    }

    function setGroup(value) {
        var clean = (value && value !== "Ungrouped") ? value.trim() : ""
        if (currentGroup === clean && editText === (clean || "Ungrouped")) return
        currentGroup = clean
        applyGroup()
    }

    onModelChanged: Qt.callLater(applyGroup)

    onActivated: (index) => {
        commitTimer.stop()
        var chosen = model[index] || ""
        var val = (chosen === "Ungrouped") ? "" : chosen
        currentGroup = val
        editText = chosen
        groupEdited(val)
    }

    onAccepted: commit()
    onActiveFocusChanged: if (!activeFocus) commit()
}
