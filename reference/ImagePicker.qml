import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "ImagePickerModel.js" as ImagePickerModel

Item {
  id: root

  // Injected by omarchy-shell; defaults to the session OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string stateHome: Quickshell.env("HOME") + "/.local/state"
  property string imageDirs: Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIRS") || Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIR") || Quickshell.env("OMARCHY_STOCK_BACKGROUNDS_DIR") || (stateHome + "/omarchy/current/theme/backgrounds")

  readonly property bool isUnlockGallery: (root.imageDirs && root.imageDirs.indexOf("unlock") !== -1) || (root.imageArray.length > 0 && String(root.imageArray[0].filePath).indexOf("unlock") !== -1)
  readonly property string galleryTitle: {
    if (isUnlockGallery) return "Unlock Screen Gallery"
    if (root.showLabels) return "Theme Gallery"
    return "Wallpaper Gallery"
  }
  readonly property string applyButtonText: {
    if (isUnlockGallery) return "Set Unlock Screen"
    if (root.showLabels) return "Apply Theme"
    return "Set Wallpaper"
  }

  property string imageRows: ""
  property string loadedImageRows: ""
  property string selectionFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTION_FILE") || Quickshell.env("OMARCHY_BACKGROUND_SELECTION_FILE")
  property string selectedImage: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTED")
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool showLabels: false
  property bool filterable: false
  property bool layoutSettled: false
  property bool requestActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property string doneFile: ""
  property string filterText: ""
  property var doneFilesToRelease: []

  // Dynamic Theme & Animation Tracking (Connected to Universal Motion Engine)
  property string activeThemeName: ""
  FileView {
    id: activeThemeWatcher
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var s = String(text()).trim()
      if (s) root.activeThemeName = s
    }
    onFileChanged: reload()
  }

  readonly property string currentAnimationStyle: Motion.activePreset
  readonly property int animDuration: Motion.entryDuration
  readonly property var animEasingType: Motion.easeExpressive
  readonly property real animOvershoot: Motion.springOvershoot
  readonly property string animStyleDisplay: Motion.presetHumanName(Motion.activePreset)

  // Smooth Reveal & Drop-Down Progress
  property bool isPresented: root.opened
  property real entryProgress: 0.0

  onOpenedChanged: {
    if (!opened) {
      layoutSettled = false
    }
  }

  onIsPresentedChanged: {
    if (isPresented) {
      entryProgress = 0.0
      entryAnim.restart()
    } else {
      entryProgress = 0.0
    }
  }

  NumberAnimation {
    id: entryAnim
    target: root
    property: "entryProgress"
    from: 0.0
    to: 1.0
    duration: root.animDuration
    easing.type: root.animEasingType
    easing.overshoot: root.animOvershoot
  }

  // Palette & Dimension Tokens
  property color dimColor: Color.background
  property color foreground: Color.imagePicker.text
  property color scrim: Color.imagePicker.scrim
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder
  property color accentColor: Color.accent || Color.foreground

  property int expandedWidth: Math.min(940, panel.width ? panel.width - Style.space(80) : 940)
  property int expandedHeight: Math.min(528, panel.height ? panel.height - Style.space(160) : 528)
  property int sliceWidth: Math.max(160, Math.round(expandedWidth * 0.20))
  property int sliceHeight: Math.round(expandedHeight * 0.82)
  property int sliceSpacing: Style.space(18)
  property int skewOffset: 0
  property int bottomChromeHeight: showLabels ? (filterable ? 110 : 80) : (filterable ? 75 : 45)

  function scriptPath(name) {
    return omarchyPath + "/shell/plugins/image-picker/" + name
  }

  function focusPicker() {
    if (root.opened && root.imagesLoaded && root.layoutSettled)
      carousel.forceActiveFocus()
  }

  function revealWhenSettled(serial) {
    if (serial === root.requestSerial && root.opened && root.imagesLoaded && root.imageArray.length > 0) {
      root.layoutSettled = true
      root.focusPicker()
    }
  }

  function currentPath() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return ""
    return imageArray[selectedIndex].filePath
  }

  function nameForPath(path) {
    return ImagePickerModel.nameForPath(path)
  }

  function labelForPath(path) {
    return ImagePickerModel.labelForPath(path)
  }

  function currentLabel() {
    var path = currentPath()
    if (!path) return filterText ? "No matches for “" + filterText + "”" : ""
    return labelForPath(path)
  }

  function itemMatches(index) {
    return ImagePickerModel.itemMatches(imageArray, index, filterText)
  }

  function firstMatchingIndex() {
    return ImagePickerModel.firstMatchingIndex(imageArray, filterText)
  }

  function filteredPosition(index) {
    return ImagePickerModel.filteredPosition(imageArray, index, filterText)
  }

  function selectedFilteredPosition() {
    return ImagePickerModel.selectedFilteredPosition(imageArray, selectedIndex, filterText)
  }

  function select(index, immediate) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    else if (index >= imageArray.length) index = imageArray.length - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex && immediate !== true) return

    selectedIndex = index
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0) return

    var index = selectedIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        select(index)
        return
      }
    }
  }

  function updateFilter(nextFilterText) {
    filterText = nextFilterText

    if (!itemMatches(selectedIndex)) {
      var first = ImagePickerModel.nextSelectedIndexForFilter(imageArray, selectedIndex, filterText)
      if (first >= 0) selectedIndex = first
    }
  }

  function releaseNextDoneFile() {
    if (releaseProc.running || doneFilesToRelease.length === 0) return

    var path = doneFilesToRelease.shift()
    releaseProc.command = ["bash", "-c", ": > " + Util.shellQuote(path)]
    releaseProc.running = true
  }

  function finishDoneFile(path) {
    if (!path) return
    doneFilesToRelease.push(path)
    releaseNextDoneFile()
  }

  function applySelected() {
    var path = currentPath()
    if (!path || !selectionFile) {
      cancel()
      return
    }

    var activeSelectionFile = selectionFile
    var activeDoneFile = doneFile
    applySerial = requestSerial
    requestActive = false
    selectionFile = ""
    doneFile = ""

    applyProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(path) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    applyProc.running = true
  }

  function cancel() {
    if (requestActive)
      finishDoneFile(doneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    root.opened = false
  }

  function closeSelector(nextDoneFile) {
    requestSerial += 1

    if (requestActive)
      finishDoneFile(doneFile)

    if (nextDoneFile && nextDoneFile !== doneFile)
      finishDoneFile(nextDoneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    filterText = ""
    root.opened = false
  }

  function loadRows(rows, reveal) {
    var newImages = ImagePickerModel.loadRows(rows)

    root.loadedImageRows = rows
    root.selectedIndex = root.indexForSelectedImage(newImages)
    root.imageArray = newImages
    root.imagesLoaded = true

    if (reveal !== false) {
      root.opened = true
      root.revealWhenSettled(root.requestSerial)
    }
  }

  function openSelector(nextImageDirs, nextImageRows, nextSelectedImage, nextSelectionFile, nextDoneFile, nextShowLabels, nextFilterable) {
    if (requestActive && doneFile && doneFile !== nextDoneFile)
      finishDoneFile(doneFile)

    requestSerial += 1

    imageDirs = nextImageDirs
    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    selectionFile = nextSelectionFile
    doneFile = nextDoneFile
    requestActive = !!doneFile
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      root.select(root.selectedImageIndex(), true)
      imagesLoaded = true
      opened = true
      root.revealWhenSettled(requestSerial)
      return
    }

    if (imageRows) {
      var rowsToLoad = imageRows
      var rowsSerial = requestSerial
      imageArray = []
      selectedIndex = 0
      imagesLoaded = true
      opened = true
      Qt.callLater(function() {
        if (rowsSerial === root.requestSerial)
          root.loadRows(rowsToLoad, true)
      })
      return
    }

    imageArray = []
    selectedIndex = 0
    imagesLoaded = false
    opened = false
    startImageScan(requestSerial, imageDirs)
  }

  property var imageArray: []

  function startImageScan(serial, dirs) {
    if (loadImagesProc.running) {
      loadImagesProc.queuedSerial = serial
      loadImagesProc.queuedDirs = dirs
      return
    }

    loadImagesProc.activeSerial = serial
    loadImagesProc.queuedSerial = 0
    loadImagesProc.queuedDirs = ""
    loadImagesProc.command = [root.scriptPath("list.sh"), dirs]
    loadImagesProc.running = true
  }

  function indexForSelectedImage(images) {
    return ImagePickerModel.indexForSelectedImage(images, selectedImage)
  }

  function selectedImageIndex() {
    return indexForSelectedImage(imageArray)
  }

  Process {
    id: loadImagesProc
    property int activeSerial: 0
    property int queuedSerial: 0
    property string queuedDirs: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (loadImagesProc.activeSerial === root.requestSerial)
          root.loadRows(String(text || ""), true)
      }
    }
    onExited: {
      var serial = queuedSerial
      var dirs = queuedDirs
      activeSerial = 0
      queuedSerial = 0
      queuedDirs = ""
      if (serial > 0 && serial === root.requestSerial)
        root.startImageScan(serial, dirs)
    }
  }

  function open(payload) {
    var args = {}
    if (payload) {
      try { args = JSON.parse(payload) || {} } catch (e) { args = {} }
    }
    var dirs = String(args.imageDirs || imageDirs)
    var rows = String(args.imageRows || "")
    var sel = String(args.selectedImage || selectedImage)
    var selFile = String(args.selectionFile || "")
    var doneF = String(args.doneFile || "")
    var labels = args.showLabels === true || args.showLabels === "true"
    var filter = args.filterable === true || args.filterable === "true"
    openSelector(dirs, rows, sel, selFile, doneF, labels, filter)
  }

  function close() {
    cancel()
  }

  function preloadRows(nextImageRows, nextSelectedImage, nextShowLabels, nextFilterable) {
    if (opened || requestActive) return

    requestSerial += 1
    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      selectedIndex = selectedImageIndex()
      imagesLoaded = true
    } else if (imageRows) {
      loadRows(imageRows, false)
    }
  }

  Process {
    id: applyProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  Process {
    id: releaseProc
    onExited: root.releaseNextDoneFile()
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Luxury Backdrop with Ambient Glow & Scrim
    Rectangle {
      anchors.fill: parent
      visible: root.opened && root.imagesLoaded
      color: Util.alpha(root.scrim, 0.88 * root.entryProgress)

      Behavior on color {
        ColorAnimation { duration: 250 }
      }
    }

    // Soft Radial Ambient Glow centered behind active card
    Rectangle {
      anchors.centerIn: parent
      width: root.expandedWidth + 240
      height: root.expandedHeight + 200
      radius: Math.round(width / 2)
      opacity: root.entryProgress * 0.35
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(root.selectedBorder, 0.45) }
        GradientStop { position: 0.5; color: Util.alpha(root.selectedBorder, 0.12) }
        GradientStop { position: 1.0; color: "transparent" }
      }
      visible: root.opened && root.imagesLoaded
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened && root.imagesLoaded
      onClicked: root.cancel()
    }

    // Main Presentation Container
    Item {
      id: card
      visible: root.isPresented
      width: Math.min(parent.width - 40, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 60)
      height: root.expandedHeight + Style.space(90) + root.bottomChromeHeight
      transformOrigin: (Motion.activePreset === "bloom") ? Item.Center : ((Motion.activePreset === "ignition") ? Item.Bottom : Item.Top)
      y: Math.round((parent.height - height) / 2) + Math.round((1.0 - root.entryProgress) * Motion.entryYOffset)
      opacity: Math.min(1.0, root.entryProgress * 1.3)
      scale: Motion.entryScaleStart + (1.0 - Motion.entryScaleStart) * root.entryProgress

      MouseArea { anchors.fill: parent; onClicked: {} }

      // =======================================================================
      // 1. TOP FLOATING HUD (Header, Filter Pill, Count, Animation Style)
      // =======================================================================
      Rectangle {
        id: topHud
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 60, root.expandedWidth + 80)
        height: Style.space(48)
        radius: Style.space(24)
        color: Util.alpha(Color.background, 0.82)
        border.color: Util.alpha(Color.foreground, 0.16)
        border.width: 1

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          // Gallery Icon & Title
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              text: "󰸌"
              color: root.selectedBorder
              font.pixelSize: Style.font.iconLarge
              font.family: Style.font.menuFamily
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.galleryTitle
              color: root.foreground
              font.pixelSize: Style.font.heading
              font.weight: Font.Bold
              font.family: Style.font.menuFamily
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Total Items Pill Badge
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22)
            width: itemsCountText.width + Style.space(16)
            radius: Style.space(11)
            color: Util.alpha(root.selectedBorder, 0.18)
            border.color: Util.alpha(root.selectedBorder, 0.4)
            border.width: 1

            Text {
              id: itemsCountText
              anchors.centerIn: parent
              text: (root.imageArray.length) + " Total"
              color: root.foreground
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.family: Style.font.menuFamily
            }
          }

          // Dynamic Animation Style Badge
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22)
            width: animStyleText.width + Style.space(16)
            radius: Style.space(11)
            color: Util.alpha(Color.foreground, 0.08)
            border.color: Util.alpha(Color.foreground, 0.14)
            border.width: 1

            Row {
              id: animStyleText
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: "󰑮"
                color: root.selectedBorder
                font.pixelSize: Style.font.caption
                font.family: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.animStyleDisplay
                color: Util.alpha(root.foreground, 0.85)
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                font.family: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        // Right side: Interactive Filter / Search Box
        Rectangle {
          visible: root.filterable
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(32)
          width: Math.min(260, parent.width * 0.35)
          radius: Style.space(16)
          color: root.filterText ? Util.alpha(root.selectedBorder, 0.15) : Util.alpha(Color.foreground, 0.06)
          border.color: root.filterText ? root.selectedBorder : Util.alpha(Color.foreground, 0.15)
          border.width: 1

          Behavior on color { ColorAnimation { duration: 180 } }
          Behavior on border.color { ColorAnimation { duration: 180 } }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              text: "󰍉"
              color: root.filterText ? root.selectedBorder : Util.alpha(root.foreground, 0.5)
              font.pixelSize: Style.font.body
              font.family: Style.font.menuFamily
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.filterText || "Type to filter…"
              color: root.filterText ? root.foreground : Util.alpha(root.foreground, 0.45)
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.menuFamily
              font.weight: root.filterText ? Font.Medium : Font.Normal
              elide: Text.ElideRight
              width: parent.width - Style.space(24)
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      // =======================================================================
      // 2. 3D DYNAMIC ANIMATED CAROUSEL
      // =======================================================================
      Item {
        id: carousel
        anchors.top: topHud.bottom
        anchors.topMargin: Style.space(20)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bottomChromeHeight
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
        clip: false
        focus: true

        readonly property real itemStep: root.sliceWidth + root.sliceSpacing
        readonly property real previewX: (width - root.expandedWidth) / 2

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) {
              root.updateFilter("")
            } else {
              root.cancel()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.applySelected()
            event.accepted = true
          } else if (root.filterable && Util.editsFilter(event, root.filterText)) {
            root.updateFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
            root.selectAdjacent(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.selectAdjacent(1)
            event.accepted = true
          } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.updateFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Component.onCompleted: forceActiveFocus()

        Repeater {
          model: root.imageArray.length

          delegate: Item {
            id: item
            required property int index

            readonly property var imageData: root.imageArray[index]
            readonly property string filePath: imageData ? imageData.filePath : ""
            readonly property string fileName: imageData ? imageData.fileName : ""
            readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""
            readonly property string themeName: ImagePickerModel.nameForPath(filePath)
            readonly property bool isCurrentTheme: root.activeThemeName !== "" && themeName === root.activeThemeName

            readonly property bool matched: root.itemMatches(index)
            readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
            readonly property bool selected: matched && index === root.selectedIndex
            readonly property bool nearby: matched && Math.abs(relativeIndex) <= 16
            property bool sourceActivated: nearby
            onNearbyChanged: if (nearby) sourceActivated = true

            // Hover state on side cards
            property bool isHovered: false

            visible: nearby

            readonly property int cardRadius: selected ? Style.space(26) : Style.space(18)
            readonly property real itemX: selected ? carousel.previewX : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
            readonly property real itemY: selected ? 0 : Math.round((root.expandedHeight - root.sliceHeight) / 2)
            readonly property real itemWidth: selected ? root.expandedWidth : root.sliceWidth
            readonly property real itemHeight: selected ? root.expandedHeight : root.sliceHeight
            readonly property real itemScale: selected ? 1.0 : (isHovered ? 0.98 : Math.max(0.80, 0.92 - Math.abs(relativeIndex) * 0.025))
            readonly property real itemRotation: selected ? 0 : (relativeIndex < 0 ? -2.0 : 2.0)
            readonly property real itemOpacity: selected ? 1.0 : (isHovered ? 0.94 : Math.max(0.20, 0.72 - Math.abs(relativeIndex) * 0.08))

            x: itemX
            y: itemY
            width: itemWidth
            height: itemHeight
            scale: itemScale
            rotation: itemRotation
            opacity: itemOpacity
            z: selected ? 100 : (isHovered ? 80 : 50 - Math.min(Math.abs(relativeIndex), 40))

            Behavior on x {
              NumberAnimation {
                duration: Motion.liquidMoveDuration
                easing.type: Motion.easeExpressive
                easing.overshoot: Motion.springOvershoot
              }
            }
            Behavior on y {
              NumberAnimation {
                duration: Motion.liquidMoveDuration
                easing.type: Motion.easeExpressive
                easing.overshoot: Motion.springOvershoot
              }
            }
            Behavior on width {
              NumberAnimation {
                duration: Motion.liquidMoveDuration
                easing.type: Motion.easeExpressive
                easing.overshoot: Motion.springOvershoot
              }
            }
            Behavior on height {
              NumberAnimation {
                duration: Motion.liquidMoveDuration
                easing.type: Motion.easeExpressive
                easing.overshoot: Motion.springOvershoot
              }
            }
            Behavior on opacity {
              NumberAnimation {
                duration: Math.round(Motion.liquidMoveDuration * 0.75)
                easing.type: Motion.easeMicro
              }
            }
            Behavior on scale {
              NumberAnimation {
                duration: Motion.liquidMoveDuration
                easing.type: Motion.easeExpressive
                easing.overshoot: Motion.springOvershoot
              }
            }
            Behavior on rotation {
              NumberAnimation {
                duration: Motion.liquidMoveDuration
                easing.type: Motion.easeExpressive
              }
            }

            // Smooth Rounded Mask for High-Fidelity Anti-Aliased Clipping
            Rectangle {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: true
              radius: item.cardRadius
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.2
                maskSpreadAtMin: 0.2
              }

              // Fast Multi-Threaded Thumbnail & Preview Texture Loader
              Image {
                id: image
                anchors.fill: parent
                source: item.sourceActivated && item.thumbnailPath ? Util.fileUrl(item.thumbnailPath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: item.selected ? root.expandedWidth : (root.sliceWidth * 2)
                sourceSize.height: item.selected ? root.expandedHeight : (root.sliceHeight * 2)
                cache: true
                smooth: true
              }

              // Ambient Tint / Dimmer for non-selected items
              Rectangle {
                anchors.fill: parent
                color: Util.alpha(root.dimColor, item.selected ? 0 : (item.isHovered ? 0.20 : 0.44))

                Behavior on color {
                  ColorAnimation { duration: 180 }
                }
              }

              // Subtle bottom shadow gradient to elevate the floating info pill
              Rectangle {
                visible: item.selected
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.round(parent.height * 0.40)
                gradient: Gradient {
                  GradientStop { position: 0.0; color: "transparent" }
                  GradientStop { position: 0.6; color: Util.alpha(Color.background, 0.45) }
                  GradientStop { position: 1.0; color: Util.alpha(Color.background, 0.85) }
                }
              }
            }

            // High-Definition Rounded Border
            Rectangle {
              anchors.fill: parent
              color: "transparent"
              radius: item.cardRadius
              border.color: item.selected ? root.selectedBorder : (item.isHovered ? Util.alpha(root.selectedBorder, 0.75) : root.unselectedBorder)
              border.width: item.selected ? 3 : 1
              antialiasing: true

              Behavior on border.color { ColorAnimation { duration: 180 } }
              Behavior on border.width { NumberAnimation { duration: 180 } }
            }

            // Top Status Badges on Hero Card
            Row {
              visible: item.selected
              anchors.top: parent.top
              anchors.topMargin: Style.space(16)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              spacing: Style.space(8)

              // Active Theme Indicator Badge
              Rectangle {
                visible: item.isCurrentTheme
                height: Style.space(28)
                width: activeBadgeText.width + Style.space(20)
                radius: Style.space(14)
                color: Util.alpha("#10B981", 0.90)
                border.color: "#34D399"
                border.width: 1

                Row {
                  id: activeBadgeText
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    text: "󰄬"
                    color: "white"
                    font.pixelSize: Style.font.bodySmall
                    font.family: Style.font.menuFamily
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "ACTIVE THEME"
                    color: "white"
                    font.pixelSize: Style.font.caption
                    font.weight: Font.Bold
                    font.family: Style.font.menuFamily
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }

              // Preview Tag
              Rectangle {
                visible: !item.isCurrentTheme
                height: Style.space(28)
                width: previewBadgeText.width + Style.space(18)
                radius: Style.space(14)
                color: Util.alpha(Color.background, 0.80)
                border.color: Util.alpha(Color.foreground, 0.22)
                border.width: 1

                Text {
                  id: previewBadgeText
                  anchors.centerIn: parent
                  text: "󰸌 PREVIEW"
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  font.family: Style.font.menuFamily
                }
              }
            }

            // Floating Frosted Info Pill inside Hero Card
            Rectangle {
              visible: item.selected
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(16)
              height: Style.space(68)
              radius: Style.space(20)
              color: Util.alpha(Color.background, 0.85)
              border.color: Util.alpha(Color.foreground, 0.16)
              border.width: 1

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(20)
                anchors.rightMargin: Style.space(16)

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)
                  width: parent.width - applyButtonHint.width - Style.space(16)

                  Text {
                    text: ImagePickerModel.labelForPath(item.filePath)
                    color: root.foreground
                    font.pixelSize: Style.font.heading + Style.space(3)
                    font.weight: Font.Bold
                    font.family: Style.font.menuFamily
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    text: root.showLabels ? (item.isCurrentTheme ? "Currently applied desktop theme & palette" : "Press Enter to activate this theme") : "Press Enter to set as desktop wallpaper"
                    color: Util.alpha(root.foreground, 0.7)
                    font.pixelSize: Style.font.bodySmall
                    font.family: Style.font.menuFamily
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }

                // Apply Button Action Pill
                Rectangle {
                  id: applyButtonHint
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(38)
                  width: applyButtonContent.width + Style.space(24)
                  radius: Style.space(19)
                  color: applyMouseArea.containsMouse ? root.selectedBorder : Util.alpha(root.selectedBorder, 0.85)
                  scale: applyMouseArea.pressed ? 0.95 : (applyMouseArea.containsMouse ? 1.04 : 1.0)

                  Behavior on scale { NumberAnimation { duration: 120 } }
                  Behavior on color { ColorAnimation { duration: 150 } }

                  Row {
                    id: applyButtonContent
                    anchors.centerIn: parent
                    spacing: Style.space(6)

                    Text {
                      text: "󰌑"
                      color: Color.background
                      font.pixelSize: Style.font.body
                      font.family: Style.font.menuFamily
                      font.weight: Font.Bold
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      text: root.applyButtonText
                      color: Color.background
                      font.pixelSize: Style.font.body
                      font.weight: Font.Bold
                      font.family: Style.font.menuFamily
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  MouseArea {
                    id: applyMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applySelected()
                  }
                }
              }
            }

            // Mouse Interactive Area for Carousel Item
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: item.isHovered = true
              onExited: item.isHovered = false
              onClicked: item.selected ? root.applySelected() : root.select(index)
            }
          }
        }
      }

      // =======================================================================
      // 3. BOTTOM FLOATING NAVIGATION HUD (Keyboard Cheatsheet / Status Bar)
      // =======================================================================
      Rectangle {
        id: bottomHud
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(12)
        anchors.horizontalCenter: parent.horizontalCenter
        height: Style.space(36)
        width: bottomRow.width + Style.space(32)
        radius: Style.space(18)
        color: Util.alpha(Color.background, 0.85)
        border.color: Util.alpha(Color.foreground, 0.14)
        border.width: 1

        Row {
          id: bottomRow
          anchors.centerIn: parent
          spacing: Style.space(16)

          Row {
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(18)
              width: Style.space(34)
              radius: Style.space(4)
              color: Util.alpha(Color.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "◄ ►"; color: root.foreground; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Navigate"; color: Util.alpha(root.foreground, 0.7); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(18)
              width: Style.space(44)
              radius: Style.space(4)
              color: Util.alpha(root.selectedBorder, 0.25)
              Text { anchors.centerIn: parent; text: "Enter"; color: root.selectedBorder; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Select Theme"; color: Util.alpha(root.foreground, 0.7); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(18)
              width: Style.space(32)
              radius: Style.space(4)
              color: Util.alpha(Color.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "Esc"; color: root.foreground; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Close"; color: Util.alpha(root.foreground, 0.7); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }
        }
      }
    }
  }
}
