import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtTest
import qs.Commons as ShellCommons
import "components" as Manager

TestCase {
    id: testCase
    name: "ManagerThemedComboBox"
    visible: true
    width: 460
    height: 360
    when: windowShown

    Manager.ThemedComboBox {
        id: picker
        x: 30; y: 30; width: 210
        model: ["All media", "Static", "Video"]
    }
    Button { id: nextControl; focusPolicy: Qt.ClickFocus | Qt.TabFocus; x: 30; y: 290; text: "Next" }
    SignalSpy { id: activatedSpy; target: picker; signalName: "activated" }

    function isDark(color) { return color.r < 0.2 && color.g < 0.2 && color.b < 0.2 }
    function init() {
        ShellCommons.Color.background = "#101216"
        ShellCommons.Color.foreground = "#dadde2"
        ShellCommons.Color.accent = "#9dbaff"
        picker.popup.close()
        picker.model = ["All media", "Static", "Video"]
        picker.enabled = true
        picker.currentIndex = 0
        nextControl.forceActiveFocus()
        activatedSpy.clear()
        wait(20)
    }
    function cleanup() { picker.popup.close() }

    function test_closed_and_popup_are_dark() {
        verify(isDark(picker.background.color), "Closed surface should use the noir palette")
        verify(isDark(picker.palette.window), "Popup palette should be dark")
        picker.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(picker.popup, "opened", true)
        verify(isDark(picker.popup.background.color), "Actual opened popup background should be dark")
        compare(picker.popup.palette.text, ShellCommons.Color.foreground)
        compare(picker.popup.palette.highlightedText, ShellCommons.Color.foreground)
        compare(picker.model.length, 3)
    }
    function test_focus_and_disabled_feedback() {
        picker.forceActiveFocus()
        verify(picker.activeFocus)
        compare(picker.background.border.color, ShellCommons.Color.accent)
        picker.enabled = false
        wait(20)
        verify(picker.contentItem.color.a < 0.5, "Disabled label should use the disabled palette")
        verify(isDark(picker.background.color), "Disabled control should remain dark")
        mouseClick(picker)
        verify(!picker.popup.opened)
        compare(picker.currentIndex, 0)
        compare(activatedSpy.count, 0)
    }
    function test_closed_arrow_keys_activate_native_model() {
        picker.forceActiveFocus()
        keyClick(Qt.Key_Down)
        compare(picker.currentIndex, 1)
        compare(picker.currentText, "Static")
        compare(activatedSpy.count, 1)
        keyClick(Qt.Key_Up)
        compare(picker.currentIndex, 0)
        compare(picker.currentText, "All media")
        compare(activatedSpy.count, 2)
    }
    function test_popup_enter_commits_and_escape_cancels() {
        picker.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(picker.popup, "opened", true)
        keyClick(Qt.Key_Down)
        compare(picker.highlightedIndex, 1)
        compare(picker.currentIndex, 0)
        keyClick(Qt.Key_Return)
        tryCompare(picker.popup, "opened", false)
        compare(picker.currentIndex, 1)
        compare(picker.currentText, "Static")
        compare(activatedSpy.count, 1)
        keyClick(Qt.Key_Space)
        tryCompare(picker.popup, "opened", true)
        keyClick(Qt.Key_Down)
        compare(picker.highlightedIndex, 2)
        keyClick(Qt.Key_Escape)
        tryCompare(picker.popup, "opened", false)
        compare(picker.currentIndex, 1)
        compare(activatedSpy.count, 1)
    }
    function test_native_tab_and_home_end() {
        picker.forceActiveFocus()
        keyClick(Qt.Key_End)
        compare(picker.currentIndex, 2)
        keyClick(Qt.Key_Home)
        compare(picker.currentIndex, 0)
        keyClick(Qt.Key_Tab)
        verify(nextControl.activeFocus, "Tab should reach the next native control")
    }
    function test_control_models_data() {
        return [
            { tag: "media filter", values: ["All media", "Static", "Video"] },
            { tag: "desktop filter", values: ["All desktops", "Omarchy", "DaemonOS"] },
            { tag: "operation target", values: ["Both desktops", "Omarchy", "DaemonOS"] },
            { tag: "group chooser", values: ["Choose existing group…", "One group", "Very long second group name — café"] },
            { tag: "import mode", values: ["Automatic media", "Static image", "Video only"] }
        ]
    }
    function test_control_models(data) {
        picker.model = data.values
        picker.currentIndex = 0
        picker.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(picker.popup, "opened", true)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        tryCompare(picker.popup, "opened", false)
        compare(picker.currentIndex, 1)
        compare(picker.currentText, data.values[1])
        compare(activatedSpy.count, 1)
        compare(picker.model.length, data.values.length)
    }
    function test_theme_changes_recolor_control_and_popup() {
        var oldBackground = ShellCommons.Color.background
        var oldForeground = ShellCommons.Color.foreground
        var oldAccent = ShellCommons.Color.accent
        try {
            ShellCommons.Color.background = "#08090b"
            ShellCommons.Color.foreground = "#c6bca8"
            ShellCommons.Color.accent = "#a8b594"
            picker.forceActiveFocus()
            wait(20)
            compare(picker.background.border.color, ShellCommons.Color.accent)
            compare(picker.palette.text, ShellCommons.Color.foreground)
            picker.popup.open()
            tryCompare(picker.popup, "opened", true)
            verify(isDark(picker.popup.background.color))
            compare(picker.popup.palette.text, ShellCommons.Color.foreground)
        } finally {
            ShellCommons.Color.background = oldBackground
            ShellCommons.Color.foreground = oldForeground
            ShellCommons.Color.accent = oldAccent
        }
    }
}
