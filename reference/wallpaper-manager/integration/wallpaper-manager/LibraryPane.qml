import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Selection.js" as Selection

RowLayout {
    id: pane
    property var manager
    property string anchor: ""
    readonly property var groupCounts: {
        var counts = Object.create(null)
        counts["Ungrouped"] = 0
        manager.items.forEach(function(item) { var group = item.group || "Ungrouped"; counts[group] = (counts[group] || 0) + 1 })
        return counts
    }
    readonly property var selectedItem: manager.selectedSlugs.length === 1
        ? manager.items.find(function(item) { return item.slug === manager.selectedSlugs[0] }) || null : null
    readonly property string selectionTitle: manager.selectedSlugs.length === 0 ? "Select a wallpaper"
        : manager.selectedSlugs.length === 1 ? (selectedItem ? selectedItem.title : "Selection unavailable")
        : manager.selectedSlugs.length + " wallpapers selected"
    ManagerMotion { id: motion }

    function revealInspectorControl(control) {
        var viewport = actionScroll.contentItem
        if (!viewport || !viewport.contentItem) return
        var point = control.mapToItem(viewport.contentItem, 0, 0)
        var next = viewport.contentY
        if (point.y < next + 6) next = point.y - 6
        else if (point.y + control.height > next + actionScroll.availableHeight - 6)
            next = point.y + control.height - actionScroll.availableHeight + 6
        viewport.contentY = Math.max(0, Math.min(Math.max(0, viewport.contentHeight - actionScroll.availableHeight), next))
    }

    function selectRow(index, modifiers, toggle) {
        var keys = manager.visibleItems.map(function(item) { return item.slug })
        var result = Selection.select(keys, manager.selected, keys[index], modifiers, anchor, toggle)
        manager.selected = result.selected; anchor = result.anchor
        grid.currentIndex = index; grid.forceActiveFocus()
    }
    visible: manager.page === "library"
    Layout.fillWidth: true; Layout.fillHeight: true
    spacing: 14

    Rectangle {
        Layout.preferredWidth: Math.max(148, Math.min(172, pane.width * 0.16))
        Layout.fillHeight: true
        color: Qt.tint(manager.bg, Qt.alpha(manager.fg, 0.028))
        radius: 12
        border.color: Qt.alpha(manager.fg, 0.065)
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 12
            Caption { text: "COLLECTIONS"; opacity: 0.64; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.3 }
            ListView {
                id: groupList
                objectName: "library-groups"
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                spacing: 4
                model: ["All themes", "Ungrouped"].concat(manager.groups)
                ScrollBar.vertical: ScrollBar { }
                delegate: ItemDelegate {
                    id: groupRow
                    required property string modelData
                    width: ListView.view.width; height: 40
                    highlighted: manager.groupFilter === modelData
                    leftPadding: 10; rightPadding: 10
                    contentItem: RowLayout {
                        spacing: 6
                        Text { Layout.fillWidth: true; text: groupRow.modelData; elide: Text.ElideRight; color: manager.fg; font.pixelSize: 12; font.weight: groupRow.highlighted ? Font.DemiBold : Font.Normal; verticalAlignment: Text.AlignVCenter }
                        Text { text: groupRow.modelData === "All themes" ? manager.items.length : pane.groupCounts[groupRow.modelData] || 0; color: Qt.alpha(manager.fg, groupRow.highlighted ? 0.82 : 0.46); font.pixelSize: 10 }
                    }
                    background: Rectangle {
                        radius: 8
                        color: groupRow.highlighted ? Qt.alpha(manager.accent, 0.13) : groupRow.hovered ? Qt.alpha(manager.fg, 0.04) : "transparent"
                        border.color: groupRow.activeFocus ? manager.accent : groupRow.highlighted ? Qt.alpha(manager.accent, 0.22) : "transparent"
                        Behavior on color { enabled: !motion.reducedMotion; ColorAnimation { duration: motion.micro } }
                    }
                    onClicked: { manager.groupFilter = modelData; manager.selected = ({}); pane.anchor = "" }
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.alpha(manager.fg, 0.08) }
            Caption { Layout.fillWidth: true; text: "Ungrouped themes stay individual in Theme Deck."; opacity: 0.55; font.pixelSize: 11 }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 8
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true; spacing: 3
                Caption { text: manager.visibleItems.length + " themes in view · " + manager.selectedSlugs.length + " selected"; opacity: 0.6; font.pixelSize: 11 }
            }
            ActionButton { objectName: "select-visible"; text: "Select visible"; quiet: true; onClicked: manager.chooseAll(false) }
            ActionButton { objectName: "clear-selection"; text: "Clear"; quiet: true; onClicked: { manager.selected = ({}); pane.anchor = "" } }
        }
        GridView {
            id: grid
            objectName: "library-grid"
            activeFocusOnTab: true
            keyNavigationEnabled: true
            Keys.onSpacePressed: if (currentItem) pane.selectRow(currentIndex, 0, true)
            Keys.onPressed: function(event) {
                var columns = Math.max(1, Math.floor(width / 210))
                var delta = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Up ? -columns : event.key === Qt.Key_Down ? columns : 0
                if (delta && count) {
                    var next = Math.max(0, Math.min(count - 1, currentIndex + delta))
                    if (event.modifiers & Qt.ControlModifier) currentIndex = next
                    else pane.selectRow(next, event.modifiers, false)
                    positionViewAtIndex(next, GridView.Contain); event.accepted = true
                }
            }
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            cellWidth: width / Math.max(1, Math.floor(width / 210)); cellHeight: 202
            model: manager.visibleItems
            ScrollBar.vertical: ScrollBar { }
            delegate: ThemeCard {
                required property var modelData
                required property int index
                theme: modelData
                manager: pane.manager
                keyboardFocused: grid.activeFocus && grid.currentIndex === index
                width: grid.cellWidth; height: grid.cellHeight
                onSelectionRequested: modifiers => pane.selectRow(index, modifiers, false)
                onToggleRequested: pane.selectRow(index, 0, true)
                onApplyRequested: if (!manager.busy) manager.request({action: "apply", slug: theme.slug})
            }
            Column {
                anchors.centerIn: parent; width: Math.max(0, parent.width - 32); spacing: 8
                visible: !manager.visibleItems.length
                Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: manager.items.length ? "No matching wallpapers" : "Your collection starts here"; color: Qt.alpha(manager.fg, 0.82); font.pixelSize: 16; font.weight: Font.Medium }
                Caption { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: manager.items.length ? "Try another search, filter or collection." : "Choose Add wallpapers to bring in your first collection."; opacity: 0.55 }
            }
        }
    }

    ScrollView {
        id: actionScroll
        objectName: "selection-inspector"
        Layout.preferredWidth: Math.max(220, Math.min(256, pane.width * 0.25))
        Layout.fillHeight: true; clip: true
        padding: 14
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; active: true }
        contentWidth: availableWidth
        background: Rectangle { color: Qt.tint(manager.bg, Qt.alpha(manager.fg, 0.034)); radius: 12; border.color: Qt.alpha(manager.fg, 0.08) }
        ColumnLayout {
            id: actions
            width: actionScroll.availableWidth; spacing: 8
            Caption { text: "SELECTION"; font.weight: Font.DemiBold; font.pixelSize: 10; font.letterSpacing: 1.3; opacity: 0.6 }
            Label { objectName: "selection-title"; Layout.fillWidth: true; text: pane.selectionTitle; color: manager.fg; font.pixelSize: 16; font.weight: Font.DemiBold; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
            Caption { Layout.fillWidth: true; text: manager.selectedSlugs.length === 0 ? "Select a wallpaper to apply it. Ctrl adds items; Shift selects a range."
                    : pane.selectedItem ? (pane.selectedItem.group || "Ungrouped") + " · " + (pane.selectedItem.type === "video" ? "Video" : "Static image")
                    : manager.selectedSlugs.length === 1 ? "Refresh the library before applying changes." : "Move, organize or remove this selection together."; opacity: 0.6; font.pixelSize: 11 }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "apply-selected"; text: "Apply selected theme"; primary: true; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length === 1; onClicked: manager.request({action: "apply", slug: manager.oneSelected()}) }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.topMargin: 6; Layout.bottomMargin: 6; color: Qt.alpha(manager.fg, 0.09) }
            Caption { text: "ORGANIZE"; font.weight: Font.DemiBold; font.pixelSize: 10; font.letterSpacing: 1.1; opacity: 0.58 }
            Field { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); id: groupName; objectName: "selection-group-name"; Layout.fillWidth: true; placeholderText: "New or existing group name" }
            ThemedComboBox { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "selection-existing-group"; Layout.fillWidth: true; Layout.minimumWidth: 0; model: ["Choose existing group…"].concat(manager.groups); onActivated: if (currentIndex > 0) groupName.text = currentText }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "move-group"; text: "Create / move to group"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length > 0 && groupName.text.trim().length > 0; onClicked: manager.request({action: "group", slugs: manager.selectedSlugs, group: groupName.text}) }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "leave-ungrouped"; text: "Leave ungrouped"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length > 0; onClicked: manager.request({action: "group", slugs: manager.selectedSlugs, group: ""}) }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "use-group-cover"; text: "Use as cover / first"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length === 1; onClicked: manager.request({action: "first", slugs: manager.selectedSlugs}) }
            Caption { Layout.fillWidth: true; Layout.topMargin: 4; text: "Select a collection on the left to rename or dissolve its group. Its wallpapers are kept."; opacity: 0.55; font.pixelSize: 11 }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "rename-group"; text: "Rename selected group"; Layout.fillWidth: true; enabled: !manager.busy && manager.groups.indexOf(manager.groupFilter) >= 0 && groupName.text.trim().length > 0; onClicked: { var old = manager.groupFilter; manager.groupFilter = "All themes"; manager.request({action: "rename-group", old: old, group: groupName.text}) } }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "dissolve-group"; text: "Dissolve selected group"; Layout.fillWidth: true; enabled: !manager.busy && manager.groups.indexOf(manager.groupFilter) >= 0; onClicked: { manager.confirmOperation({action: "delete-group", old: manager.groupFilter}); manager.groupFilter = "All themes" } }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.topMargin: 6; Layout.bottomMargin: 6; color: Qt.alpha(manager.fg, 0.09) }
            Caption { text: "NAME & REMOVE"; font.weight: Font.DemiBold; font.pixelSize: 10; font.letterSpacing: 1.1; opacity: 0.58 }
            Field { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); id: themeName; objectName: "selection-theme-name"; Layout.fillWidth: true; placeholderText: "New display name" }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "rename-theme"; text: "Rename theme"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length === 1 && themeName.text.trim().length > 0; onClicked: manager.request({action: "rename-theme", slugs: manager.selectedSlugs, title: themeName.text}) }
            ActionButton { onActiveFocusChanged: if (activeFocus) pane.revealInspectorControl(this); objectName: "remove-selected"; text: "Remove selected…"; destructive: true; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length > 0; onClicked: manager.confirmOperation({action: "remove", items: manager.selectedSlugs.map(function(s) { return {slug: s} }), target: manager.target()}) }
        }
    }
}
