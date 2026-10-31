import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Selection.js" as Selection
RowLayout {
                    property var manager
                    id: pane
                    property string anchor: ""
                    function selectRow(index, modifiers, toggle) {
                        var keys = manager.visibleItems.map(function(item) { return item.slug })
                        var result = Selection.select(keys, manager.selected, keys[index], modifiers, anchor, toggle)
                        manager.selected = result.selected; anchor = result.anchor
                        grid.currentIndex = index; grid.forceActiveFocus()
                    }
                    visible: manager.page === "library"
                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 170; Layout.fillHeight: true; color: manager.surface; radius: 8
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 8
                            Caption { text: "GROUPS"; opacity: 0.6; font.bold: true }
                            ListView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                model: ["All themes", "Ungrouped"].concat(manager.groups)
                                delegate: ItemDelegate {
                                    required property string modelData
                                    width: ListView.view.width; height: 38
                                    highlighted: manager.groupFilter === modelData
                                    contentItem: Text { text: modelData; elide: Text.ElideRight; color: manager.fg; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
                                    background: Rectangle { radius: 6; color: parent.highlighted ? Qt.alpha(manager.accent, 0.25) : "transparent" }
                                    onClicked: { manager.groupFilter = modelData; manager.selected = ({}); pane.anchor = "" }
                                }
                            }
                            Caption { Layout.fillWidth: true; text: "Ungrouped themes appear individually in the main picker."; opacity: 0.65 }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        RowLayout {
                            Caption { text: manager.visibleItems.length + " themes · " + manager.selectedSlugs.length + " selected"; Layout.fillWidth: true }
                            ActionButton { objectName: "select-visible"; text: "Select visible"; onClicked: manager.chooseAll(false) }
                            ActionButton { objectName: "clear-selection"; text: "Clear"; onClicked: { manager.selected = ({}); pane.anchor = "" } }
                        }
                        GridView {
                            id: grid
                            activeFocusOnTab: true
                            keyNavigationEnabled: true
                            Keys.onSpacePressed: if (currentItem) pane.selectRow(currentIndex, 0, true)
                            Keys.onPressed: function(event) {
                                var columns = Math.max(1, Math.floor(width / 190))
                                var delta = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Up ? -columns : event.key === Qt.Key_Down ? columns : 0
                                if (delta && count) {
                                    var next = Math.max(0, Math.min(count - 1, currentIndex + delta))
                                    if (event.modifiers & Qt.ControlModifier) currentIndex = next
                                    else pane.selectRow(next, event.modifiers, false)
                                    positionViewAtIndex(next, GridView.Contain); event.accepted = true
                                }
                            }
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            cellWidth: width / Math.max(1, Math.floor(width / 190)); cellHeight: 172
                            model: manager.visibleItems
                            ScrollBar.vertical: ScrollBar {}
                            delegate: ThemeCard {
                                required property var modelData
                                required property int index
                                theme: modelData
                                manager: pane.manager
                                width: grid.cellWidth; height: grid.cellHeight
                                onSelectionRequested: modifiers => pane.selectRow(index, modifiers, false)
                                onToggleRequested: pane.selectRow(index, 0, true)
                                onApplyRequested: if (!manager.busy) manager.request({action: "apply", slug: theme.slug})
                            }
                            Label { anchors.centerIn: parent; visible: !manager.visibleItems.length; text: "No themes here yet"; color: Qt.alpha(manager.fg, 0.5) }
                        }
                    }
                    ScrollView {
                        id: actionScroll
                        Layout.preferredWidth: 218; Layout.fillHeight: true; clip: true
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: actionScroll.availableWidth; spacing: 8
                            Caption { Layout.fillWidth: true; text: "Click · Ctrl-click · Shift-click"; opacity: 0.65 }
                            Caption { text: "MANAGE SELECTION"; font.bold: true; opacity: 0.65 }
                            Field { id: groupName; Layout.fillWidth: true; placeholderText: "Anime / type group name" }
                            ComboBox { Layout.fillWidth: true; Layout.minimumWidth: 0; model: ["Choose existing group…"].concat(manager.groups); onActivated: if (currentIndex > 0) groupName.text = currentText }
                            ActionButton { objectName: "move-group"; text: "Create / move to group"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length > 0 && groupName.text.trim().length > 0; onClicked: manager.request({action: "group", slugs: manager.selectedSlugs, group: groupName.text}) }
                            ActionButton { text: "Leave ungrouped"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length > 0; onClicked: manager.request({action: "group", slugs: manager.selectedSlugs, group: ""}) }
                            ActionButton { text: "Use as cover / first"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length === 1; onClicked: manager.request({action: "first", slugs: manager.selectedSlugs}) }
                            Caption { Layout.fillWidth: true; text: "Select a group on the left to rename or dissolve it. Dissolving keeps its themes."; opacity: 0.6 }
                            ActionButton { text: "Rename selected group"; Layout.fillWidth: true; enabled: !manager.busy && manager.groups.indexOf(manager.groupFilter) >= 0 && groupName.text.trim().length > 0; onClicked: { var old = manager.groupFilter; manager.groupFilter = "All themes"; manager.request({action: "rename-group", old: old, group: groupName.text}) } }
                            ActionButton { text: "Dissolve selected group"; Layout.fillWidth: true; enabled: !manager.busy && manager.groups.indexOf(manager.groupFilter) >= 0; onClicked: { manager.confirmOperation({action: "delete-group", old: manager.groupFilter}); manager.groupFilter = "All themes" } }
                            Field { id: themeName; Layout.fillWidth: true; placeholderText: "New display name" }
                            ActionButton { text: "Rename theme"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length === 1 && themeName.text.trim().length > 0; onClicked: manager.request({action: "rename-theme", slugs: manager.selectedSlugs, title: themeName.text}) }
                            ActionButton { text: "Apply selected theme"; primary: true; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length === 1; onClicked: manager.request({action: "apply", slug: manager.oneSelected()}) }
                            ActionButton { text: "Remove selected…"; Layout.fillWidth: true; enabled: !manager.busy && manager.selectedSlugs.length > 0; onClicked: manager.confirmOperation({action: "remove", items: manager.selectedSlugs.map(function(s) { return {slug: s} }), target: manager.target()}) }
                        }
                    }
                }
