import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as ShellCommons
import "ImagePickerModel.js" as ImagePickerModel

Item {
  id: root

  // Injected by omarchy-shell; defaults to the session OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string stateHome: Quickshell.env("HOME") + "/.local/state"
  property string imageDirs: Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIRS") || Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIR") || Quickshell.env("OMARCHY_STOCK_BACKGROUNDS_DIR") || (stateHome + "/omarchy/current/theme/backgrounds")
  
  readonly property bool isUnlockGallery: (root.imageDirs && root.imageDirs.indexOf("unlock") !== -1) || (root.imageArray.length > 0 && String(root.imageArray[0].filePath).indexOf("unlock") !== -1)
  readonly property string galleryTitle: {
    if (isUnlockGallery) return "Unlock Screen Deck"
    if (root.showLabels) return "Theme Deck"
    return "Wallpaper Deck"
  }
  readonly property string applyButtonText: {
    if (isUnlockGallery) return "Set Unlock Screen"
    if (root.showLabels) return "Apply Theme"
    return "Set Wallpaper"
  }

  property var themeSummary: ({})
  readonly property int totalWallpaperCount: showLabels && Number(themeSummary.total_wallpapers) > 0 ? Number(themeSummary.total_wallpapers) : imageArray.length
  readonly property string countLabel: totalWallpaperCount + (totalWallpaperCount === 1 ? " wallpaper" : " wallpapers")
  readonly property string countScope: filterText ? filterPositions.filter(function(p) { return p >= 0 }).length + " matches" : themeSummary.mode === "groups" ? themeSummary.group_count + " groups" : themeSummary.mode === "themes" ? imageArray.length + " in this group" : "All themes"
  FileView {
    id: countMetadata
    path: root.showLabels && root.imageArray.length ? String(root.imageArray[0].filePath).replace(/\/[^/]*$/, "/.selector-info.json") : ""
    watchChanges: true
    printErrors: false
    onLoaded: { try { root.themeSummary = JSON.parse(text()) } catch (e) { root.themeSummary = ({}) } }
    onLoadFailed: root.themeSummary = ({})
    onFileChanged: reload()
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

  // Interactive Features: Favorites & Sound Engine
  property var favorites: []
  property bool showOnlyFavorites: false
  property bool soundEnabled: true
  property bool peekMode: false

  FileView {
    id: favoritesWatcher
    path: root.stateHome + "/omarchy/favorite-themes.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (Array.isArray(data)) root.favorites = data
      } catch (e) { root.favorites = [] }
    }
    onLoadFailed: root.favorites = []
    onFileChanged: reload()
  }

  Process {
    id: saveFavoritesProc
  }

  Process {
    id: soundProc
  }

  function playTick() {
    if (!root.soundEnabled) return
    soundProc.running = false
    soundProc.command = ["canberra-gtk-play", "-i", "audio-volume-change"]
    soundProc.running = true
  }

  function isFavorite(themeSlug) {
    if (!themeSlug) return false
    var clean = String(themeSlug).replace(/\s*\(\d+\)$/, "").trim()
    for (var i = 0; i < root.favorites.length; i++) {
      var fav = root.favorites[i]
      if (fav === themeSlug || fav === clean) return true
    }
    return false
  }

  function toggleFavorite(themeSlug) {
    if (!themeSlug) return
    var clean = String(themeSlug).replace(/\s*\(\d+\)$/, "").trim() || themeSlug
    var list = root.favorites.slice()
    var idx = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i] === themeSlug || list[i] === clean) {
        idx = i
        break
      }
    }
    if (idx !== -1) {
      list.splice(idx, 1)
    } else {
      list.push(clean)
    }
    root.favorites = list
    saveFavoritesProc.running = false
    saveFavoritesProc.command = ["bash", "-c", "mkdir -p " + Util.shellQuote(root.stateHome + "/omarchy") + "; printf '%s\\n' " + Util.shellQuote(JSON.stringify(list)) + " > " + Util.shellQuote(root.stateHome + "/omarchy/favorite-themes.json")]
    saveFavoritesProc.running = true
    playTick()
  }

  function surpriseMe() {
    var count = root.imageArray.length
    if (count <= 1) return
    var matches = []
    for (var i = 0; i < count; i++) {
      if (root.itemMatches(i) && i !== root.selectedIndex) matches.push(i)
    }
    if (matches.length === 0) return
    var pick = matches[Math.floor(Math.random() * matches.length)]
    root.select(pick)
    playTick()
  }

  function togglePeek() {
    peekMode = !peekMode
    playTick()
  }

  function toggleFavoritesFilter() {
    showOnlyFavorites = !showOnlyFavorites
    if (!itemMatches(selectedIndex)) {
      var first = ImagePickerModel.nextSelectedIndexForFilter(imageArray, selectedIndex, filterText, showOnlyFavorites ? favorites : null)
      if (first >= 0) selectedIndex = first
    }
    playTick()
  }

  readonly property string currentAnimationStyle: Motion.activePreset
  readonly property int animDuration: Motion.reducedMotion ? 1 : Math.min(220, Motion.entryDuration)
  readonly property int moveDuration: Motion.reducedMotion ? 1 : Math.min(220, Math.round(Motion.liquidMoveDuration * 0.75))
  readonly property var filterPositions: ImagePickerModel.positions(root.imageArray, root.filterText, root.showOnlyFavorites ? root.favorites : null)
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

  // Read-only diagnostics let maintenance verify the loaded version without opening it.
  IpcHandler {
    target: "daemon0-gallery-performance"
    function status(): string {
      return JSON.stringify({revision: 7, wallpaperCount: root.totalWallpaperCount, countLabel: root.countLabel, scope: root.countScope, cards: root.imageArray.length, layout: "card-stack-deck", opened: root.opened,
        preset: Motion.activePreset, reducedMotion: Motion.reducedMotion,
        entranceMs: root.animDuration, movementMs: root.moveDuration,
        previewLimit: 7, boundedLayers: true, hiddenCardAnimations: false,
        selectedPath: root.currentPath(), selectedLabel: root.currentLabel(), previewState: root.currentPreviewState(),
        directBackdrop: true, originalSources: true, boundedDecode: true, progressivePreviews: true, cardStack: true, pixelRatio: root.previewPixelRatio})
    }
  }

  // Palette & Dimension Tokens
  property color dimColor: ShellCommons.Color.background
  property color foreground: ShellCommons.Color.imagePicker.text
  property color scrim: ShellCommons.Color.imagePicker.scrim
  property color selectedBorder: ShellCommons.Color.imagePicker.selectedBorder
  property color unselectedBorder: ShellCommons.Color.imagePicker.unselectedBorder
  property color accentColor: ShellCommons.Color.accent || ShellCommons.Color.foreground

  readonly property real previewPixelRatio: Math.max(1, panel.Screen.devicePixelRatio)

  // Hero Card Dimensions (Generous, full, immersive 16:9 preview)
  property int heroWidth: Math.min(880, panel.width ? Math.round(panel.width * 0.68) : 880)
  property int heroHeight: Math.round(heroWidth * 9 / 16)
  property int bottomChromeHeight: showLabels ? 66 : 58

  function scriptPath(name) {
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/daemon0.image-picker/" + name
  }

  function focusPicker() {
    if (root.opened && root.imagesLoaded && root.layoutSettled)
      deckContainer.forceActiveFocus()
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

  function currentPreviewState() {
    if (!currentPath()) return "empty"
    var card = cardRepeater.itemAt(root.selectedIndex)
    return card ? card.previewState : "loading"
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
    return index >= 0 && index < filterPositions.length && filterPositions[index] >= 0
  }

  function firstMatchingIndex() {
    return ImagePickerModel.firstMatchingIndex(imageArray, filterText, showOnlyFavorites ? favorites : null)
  }

  function filteredPosition(index) {
    return index >= 0 && index < filterPositions.length ? filterPositions[index] : -1
  }

  function selectedFilteredPosition() {
    return itemMatches(selectedIndex) ? filteredPosition(selectedIndex) : 0
  }

  function select(index, immediate) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    else if (index >= imageArray.length) index = imageArray.length - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex && immediate !== true) return

    selectedIndex = index
    playTick()
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

  function jumpAdjacent(steps) {
    var count = imageArray.length
    if (count === 0) return
    var target = selectedIndex
    var dir = steps > 0 ? 1 : -1
    var remaining = Math.abs(steps)
    for (var i = 0; i < count && remaining > 0; i++) {
      target = (target + dir + count) % count
      if (itemMatches(target)) {
        remaining--
      }
    }
    if (itemMatches(target)) {
      select(target)
    }
  }

  function jumpToEdge(first) {
    if (imageArray.length === 0) return
    if (first) {
      var idx = firstMatchingIndex()
      if (idx >= 0) select(idx)
    } else {
      var last = -1
      for (var i = imageArray.length - 1; i >= 0; i--) {
        if (itemMatches(i)) {
          last = i
          break
        }
      }
      if (last >= 0) select(last)
    }
  }

  function updateFilter(nextFilterText) {
    filterText = nextFilterText

    if (!itemMatches(selectedIndex)) {
      var first = ImagePickerModel.nextSelectedIndexForFilter(imageArray, selectedIndex, filterText, showOnlyFavorites ? favorites : null)
      if (first >= 0) selectedIndex = first
    }
  }

  function releaseNextDoneFile() {
    if (doneFilesToRelease.length === 0) return
    var paths = doneFilesToRelease.splice(0, doneFilesToRelease.length)
    var cmd = paths.map(function(p) { return ": > " + Util.shellQuote(p) }).join("; ")
    releaseProc.running = false
    releaseProc.command = ["bash", "-c", cmd]
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

    themeSummary = ({})
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
    if (countMetadata.path) countMetadata.reload()

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

    // Deep Luxury Scrim Backdrop
    // Deep Cinematic Base Underlay
    Rectangle {
      anchors.fill: parent
      visible: root.opened && root.imagesLoaded
      color: "#0a0b0e"
    }

    // Dynamic Ambient Horizon Stage (Silky blurred atmospheric wallpaper aura)
    Image {
      anchors.fill: parent
      visible: root.opened && root.imagesLoaded && !!root.currentPath()
      source: root.currentPath() ? Util.fileUrl(root.currentPath()) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: 480
      opacity: Math.max(0.0, Math.min(0.38, 0.38 * root.entryProgress))
      smooth: true
      cache: true

      // Vignette Gradient over ambient image
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha("#0a0b0e", 0.60) }
          GradientStop { position: 0.50; color: Util.alpha("#0a0b0e", 0.78) }
          GradientStop { position: 1.0; color: Util.alpha("#0a0b0e", 0.94) }
        }
      }
    }

    // Dynamic Radial Halo Glow matching Theme Accent
    Rectangle {
      anchors.centerIn: parent
      width: root.heroWidth + Style.space(420)
      height: root.heroHeight + Style.space(280)
      radius: Math.round(height / 2)
      opacity: root.entryProgress * 0.45
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(root.selectedBorder, 0.48) }
        GradientStop { position: 0.55; color: Util.alpha(root.selectedBorder, 0.12) }
        GradientStop { position: 1.0; color: "transparent" }
      }
      visible: root.opened && root.imagesLoaded
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened && root.imagesLoaded
      onClicked: {
        if (root.peekMode) {
          root.togglePeek()
        } else {
          root.cancel()
        }
      }
    }

    // Main Presentation Container
    Item {
      id: mainContainer
      visible: root.isPresented
      width: Math.min(parent.width - 40, root.heroWidth + Style.space(520))
      height: root.heroHeight + Style.space(170)
      anchors.centerIn: parent
      transformOrigin: Item.Center
      y: Math.round((parent.height - height) / 2) + Math.round((1.0 - root.entryProgress) * Motion.entryYOffset)
      opacity: Math.min(1.0, root.entryProgress * 1.3)
      scale: Motion.entryScaleStart + (1.0 - Motion.entryScaleStart) * root.entryProgress

      MouseArea { anchors.fill: parent; onClicked: {} }

      // =======================================================================
      // 1. TOP FLOATING ISLAND (Header, Badges, Search)
      // =======================================================================
      Rectangle {
        id: topHud
        opacity: root.peekMode ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 40, root.heroWidth + Style.space(140))
        height: Style.space(52)
        radius: Style.space(26)
        color: Util.alpha(ShellCommons.Color.background, 0.88)
        border.color: Util.alpha(ShellCommons.Color.foreground, 0.16)
        border.width: 1

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(18)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          // Deck Icon & Title
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Rectangle {
              width: Style.space(34)
              height: Style.space(34)
              radius: Style.space(17)
              color: Util.alpha(root.selectedBorder, 0.22)
              border.color: Util.alpha(root.selectedBorder, 0.55)
              border.width: 1.5
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: "󰓩"
                color: root.selectedBorder
                font.pixelSize: Style.font.heading || Style.font.body
                font.family: Style.font.menuFamily
              }
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
            height: Style.space(26)
            width: itemsCountText.width + Style.space(20)
            radius: Style.space(13)
            color: Util.alpha(root.selectedBorder, 0.18)
            border.color: Util.alpha(root.selectedBorder, 0.45)
            border.width: 1

            Text {
              id: itemsCountText
              anchors.centerIn: parent
              text: root.countLabel
              color: root.foreground
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
              font.family: Style.font.menuFamily
            }
          }

          // Scope Badge
          Rectangle {
            visible: topHud.width >= Style.space(820) || !root.filterable
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(26)
            width: scopeRow.width + Style.space(20)
            radius: Style.space(13)
            color: Util.alpha(ShellCommons.Color.foreground, 0.08)
            border.color: Util.alpha(ShellCommons.Color.foreground, 0.15)
            border.width: 1

            Row {
              id: scopeRow
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                text: "󰉋"
                color: root.selectedBorder
                font.pixelSize: Style.font.caption
                font.family: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.showLabels || root.filterText ? root.countScope : root.animStyleDisplay
                color: Util.alpha(root.foreground, 0.85)
                font.pixelSize: Style.font.caption
                font.weight: Font.Medium
                font.family: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        // Right side: Interactive Actions & Filter Box
        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          // Favorites Filter Toggle Button
          Rectangle {
            height: Style.space(34)
            width: favBtnRow.width + Style.space(18)
            radius: Style.space(17)
            color: root.showOnlyFavorites ? Util.alpha("#F59E0B", 0.28) : (favBtnMouse.containsMouse ? Util.alpha(ShellCommons.Color.foreground, 0.14) : Util.alpha(ShellCommons.Color.foreground, 0.06))
            border.color: root.showOnlyFavorites ? "#F59E0B" : Util.alpha(ShellCommons.Color.foreground, 0.20)
            border.width: 1.5
            anchors.verticalCenter: parent.verticalCenter

            Row {
              id: favBtnRow
              anchors.centerIn: parent
              spacing: Style.space(5)
              Text {
                text: "★"
                color: root.showOnlyFavorites ? "#F59E0B" : (favBtnMouse.containsMouse ? "#F59E0B" : root.foreground)
                font.pixelSize: Style.font.bodySmall
                font.family: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: "Favorites" + (root.favorites.length > 0 ? " (" + root.favorites.length + ")" : "")
                color: root.showOnlyFavorites ? "#F59E0B" : root.foreground
                font.pixelSize: Style.font.caption
                font.weight: Font.DemiBold
                font.family: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: favBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleFavoritesFilter()
            }
          }

          // Surprise Me (Shuffle) Button
          Rectangle {
            height: Style.space(34)
            width: Style.space(34)
            radius: Style.space(17)
            color: surpriseMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.25) : Util.alpha(ShellCommons.Color.foreground, 0.06)
            border.color: surpriseMouse.containsMouse ? root.selectedBorder : Util.alpha(ShellCommons.Color.foreground, 0.20)
            border.width: 1
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: "󰒝"
              color: surpriseMouse.containsMouse ? root.selectedBorder : root.foreground
              font.pixelSize: Style.font.body
              font.family: Style.font.menuFamily
            }

            MouseArea {
              id: surpriseMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.surpriseMe()
            }
          }

          // Fullscreen Peek Button
          Rectangle {
            height: Style.space(34)
            width: Style.space(34)
            radius: Style.space(17)
            color: peekBtnMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.25) : Util.alpha(ShellCommons.Color.foreground, 0.06)
            border.color: peekBtnMouse.containsMouse ? root.selectedBorder : Util.alpha(ShellCommons.Color.foreground, 0.20)
            border.width: 1
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: "󰍹"
              color: peekBtnMouse.containsMouse ? root.selectedBorder : root.foreground
              font.pixelSize: Style.font.body
              font.family: Style.font.menuFamily
            }

            MouseArea {
              id: peekBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePeek()
            }
          }

          // Sound Toggle Button
          Rectangle {
            height: Style.space(34)
            width: Style.space(34)
            radius: Style.space(17)
            color: soundBtnMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.25) : Util.alpha(ShellCommons.Color.foreground, 0.06)
            border.color: soundBtnMouse.containsMouse ? root.selectedBorder : Util.alpha(ShellCommons.Color.foreground, 0.20)
            border.width: 1
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: root.soundEnabled ? "󰕾" : "󰖁"
              color: root.soundEnabled ? root.foreground : Util.alpha(root.foreground, 0.40)
              font.pixelSize: Style.font.body
              font.family: Style.font.menuFamily
            }

            MouseArea {
              id: soundBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.soundEnabled = !root.soundEnabled
                root.playTick()
              }
            }
          }

          // Interactive Search Box with Clear Button
          Rectangle {
            visible: root.filterable
            height: Style.space(34)
            width: Math.min(220, parent.width * 0.28)
            radius: Style.space(17)
            color: root.filterText ? Util.alpha(root.selectedBorder, 0.18) : Util.alpha(ShellCommons.Color.foreground, 0.07)
            border.color: root.filterText ? root.selectedBorder : Util.alpha(ShellCommons.Color.foreground, 0.16)
            border.width: 1.5
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on border.color { ColorAnimation { duration: 180 } }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Text {
                text: "󰍉"
                color: root.filterText ? root.selectedBorder : Util.alpha(root.foreground, 0.55)
                font.pixelSize: Style.font.bodySmall
                font.family: Style.font.menuFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.filterText || "Filter themes…"
                color: root.filterText ? root.foreground : Util.alpha(root.foreground, 0.45)
                font.pixelSize: Style.font.caption
                font.family: Style.font.menuFamily
                font.weight: root.filterText ? Font.Medium : Font.Normal
                elide: Text.ElideRight
                width: parent.width - Style.space(48)
                anchors.verticalCenter: parent.verticalCenter
              }

              Rectangle {
                visible: !!root.filterText
                width: Style.space(18)
                height: Style.space(18)
                radius: Style.space(9)
                color: clearMouse.containsMouse ? Util.alpha(root.selectedBorder, 0.35) : Util.alpha(ShellCommons.Color.foreground, 0.15)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.menuFamily
                }

                MouseArea {
                  id: clearMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.updateFilter("")
                }
              }
            }
          }
        }
      }

      // =======================================================================
      // 2. PRISMATIC 3D ARC DECK (Holographic Fanned Perspective Stack)
      // =======================================================================
      Item {
        id: deckContainer
        anchors.top: topHud.bottom
        anchors.topMargin: Style.space(16)
        anchors.bottom: scrubBar.top
        anchors.bottomMargin: Style.space(14)
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.heroWidth + Style.space(520)
        clip: false
        focus: true

        readonly property real centerX: (width - root.heroWidth) / 2
        readonly property real centerY: (height - root.heroHeight) / 2

        // Touchpad Two-Finger Swipe & Smooth Mouse-Wheel Navigation
        WheelHandler {
          id: deckWheelHandler
          property real accumulatedDelta: 0
          onWheel: function(event) {
            var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
            accumulatedDelta += delta
            if (accumulatedDelta >= 40) {
              accumulatedDelta = 0
              root.selectAdjacent(-1)
            } else if (accumulatedDelta <= -40) {
              accumulatedDelta = 0
              root.selectAdjacent(1)
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          z: -1
          property real accumulatedWheel: 0
          onWheel: function(wheel) {
            var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x
            accumulatedWheel += delta
            if (accumulatedWheel >= 40) {
              accumulatedWheel = 0
              root.selectAdjacent(-1)
            } else if (accumulatedWheel <= -40) {
              accumulatedWheel = 0
              root.selectAdjacent(1)
            }
          }
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.peekMode) {
            root.peekMode = false
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) {
              root.updateFilter("")
            } else if (root.showOnlyFavorites) {
              root.showOnlyFavorites = false
            } else {
              root.cancel()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Space || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier || !root.filterable))) {
            root.togglePeek()
            event.accepted = true
          } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier || !root.filterable)) {
            root.surpriseMe()
            event.accepted = true
          } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier || !root.filterable)) {
            var curItem = root.imageArray[root.selectedIndex]
            if (curItem) root.toggleFavorite(curItem.name || ImagePickerModel.nameForPath(curItem.filePath))
            event.accepted = true
          } else if (event.key === Qt.Key_M && (event.modifiers & Qt.ControlModifier || !root.filterable)) {
            root.soundEnabled = !root.soundEnabled
            root.playTick()
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
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) {
            root.jumpAdjacent(-5)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown) {
            root.jumpAdjacent(5)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.jumpToEdge(true)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.jumpToEdge(false)
            event.accepted = true
          } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.updateFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Component.onCompleted: forceActiveFocus()

        // The Prismatic Fanned Arc Repeater
        Repeater {
          id: cardRepeater
          model: root.imageArray.length

          delegate: Item {
            id: stackCard
            required property int index

            readonly property var imageData: root.imageArray[index]
            readonly property string filePath: imageData ? imageData.filePath : ""
            readonly property string fileName: imageData ? imageData.fileName : ""
            readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""
            readonly property string themeName: (imageData && imageData.name) ? imageData.name : (inStack ? ImagePickerModel.nameForPath(filePath) : "")
            readonly property string displayTitle: (imageData && imageData.label) ? imageData.label : (inStack ? ImagePickerModel.labelForPath(filePath) : "")
            readonly property bool isCurrentTheme: inStack && root.activeThemeName !== "" && themeName === root.activeThemeName

            // Dynamic Palette Colors from Theme Metadata
            readonly property string accentColorHex: (imageData && imageData.accent) ? imageData.accent : root.selectedBorder
            readonly property string fgColorHex: (imageData && imageData.fg) ? imageData.fg : root.foreground
            readonly property string bgColorHex: (imageData && imageData.bg) ? imageData.bg : ShellCommons.Color.background

            // 3D Parallax Tilt & Specular Sheen Properties
            property real tiltAngleX: 0.0
            property real tiltAngleY: 0.0
            property real sheenNormX: 0.5

            transform: [
              Rotation {
                origin.x: stackCard.width / 2
                origin.y: stackCard.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: stackCard.tiltAngleX
                Behavior on angle { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
              },
              Rotation {
                origin.x: stackCard.width / 2
                origin.y: stackCard.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: stackCard.tiltAngleY
                Behavior on angle { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
              }
            ]

            readonly property bool matched: root.itemMatches(index)
            readonly property int totalMatches: root.filterText ? root.filterPositions.filter(function(p) { return p >= 0 }).length : root.imageArray.length
            readonly property int rawRelative: root.filteredPosition(index) - root.selectedFilteredPosition()
            readonly property int relativeIndex: {
              if (totalMatches <= 1) return 0
              var r = rawRelative
              if (r > Math.floor(totalMatches / 2)) r -= totalMatches
              else if (r < -Math.floor(totalMatches / 2)) r += totalMatches
              return r
            }
            readonly property bool isHero: matched && index === root.selectedIndex
            readonly property bool inStack: matched && relativeIndex >= -3 && relativeIndex <= 3
            readonly property bool sourceActivated: root.opened && inStack
            // Readiness belongs to this item: never borrow artwork from a prior selection.
            readonly property bool previewReady: thumbImage.status === Image.Ready || heroMasterImage.status === Image.Ready
            readonly property string previewState: {
              if (!sourceActivated) return "inactive"
              if (previewReady) return "ready"
              if (thumbImage.status === Image.Error && (String(heroMasterImage.source) === "" || heroMasterImage.status === Image.Error)) return "error"
              return "loading"
            }

            property bool isHovered: false

            visible: inStack

            readonly property string cleanTitle: {
              var t = stackCard.displayTitle
              return t.replace(/\s*\(\d+\)$/, "").trim() || t
            }
            readonly property string countInTitle: {
              var m = String(stackCard.displayTitle).match(/\((\d+)\)$/)
              return m ? m[1] : ""
            }

            // -------------------------------------------------------------
            // Prismatic 3D Fanned Arc Geometry & Layout Math
            // -------------------------------------------------------------
            readonly property real cardX: {
              if (isHero) return deckContainer.centerX
              if (relativeIndex > 0) {
                var r = Math.min(relativeIndex, 3)
                return deckContainer.centerX + r * Style.space(155)
              } else {
                var l = Math.min(Math.abs(relativeIndex), 3)
                return deckContainer.centerX - l * Style.space(155)
              }
            }

            readonly property real cardY: {
              if (isHero) return deckContainer.centerY
              if (relativeIndex > 0) {
                var r = Math.min(relativeIndex, 3)
                return deckContainer.centerY + (isHovered ? -Style.space(14) : 0) + Style.space(34) + (r - 1) * Style.space(26)
              } else {
                var l = Math.min(Math.abs(relativeIndex), 3)
                return deckContainer.centerY + (isHovered ? -Style.space(14) : 0) + Style.space(34) + (l - 1) * Style.space(26)
              }
            }

            readonly property real cardScale: {
              if (root.peekMode) return isHero ? Math.min(panel.width / root.heroWidth, panel.height / root.heroHeight) : 0.0
              if (isHero) return 1.0
              if (relativeIndex > 0) {
                var r = Math.min(relativeIndex, 3)
                return (isHovered ? 1.03 : 1.0) * Math.max(0.70, 1.0 - r * 0.09)
              } else {
                var l = Math.min(Math.abs(relativeIndex), 3)
                return (isHovered ? 1.03 : 1.0) * Math.max(0.70, 1.0 - l * 0.09)
              }
            }

            readonly property real cardRotation: {
              if (isHero) return 0.0
              if (relativeIndex > 0) {
                var r = Math.min(relativeIndex, 3)
                return r * 3.4
              } else {
                var l = Math.min(Math.abs(relativeIndex), 3)
                return -l * 3.4
              }
            }

            readonly property real cardOpacity: {
              if (root.peekMode) return isHero ? 1.0 : 0.0
              if (isHero) return 1.0
              if (relativeIndex > 0) {
                var r = Math.min(relativeIndex, 3)
                return isHovered ? 0.98 : Math.max(0.25, 0.94 - r * 0.20)
              } else {
                var l = Math.min(Math.abs(relativeIndex), 3)
                return isHovered ? 0.98 : Math.max(0.25, 0.94 - l * 0.20)
              }
            }

            readonly property int cardZ: {
              if (isHero) return 300
              if (relativeIndex > 0) return 260 - relativeIndex * 20
              return 260 - Math.abs(relativeIndex) * 20
            }

            x: cardX
            y: cardY
            width: root.heroWidth
            height: root.heroHeight
            scale: cardScale
            rotation: cardRotation
            opacity: cardOpacity
            z: cardZ

            Behavior on x { enabled: root.opened && root.layoutSettled && stackCard.inStack;
              NumberAnimation { duration: root.moveDuration; easing.type: Motion.easeExpressive; easing.overshoot: Motion.springOvershoot }
            }
            Behavior on y { enabled: root.opened && root.layoutSettled && stackCard.inStack;
              NumberAnimation { duration: root.moveDuration; easing.type: Motion.easeExpressive; easing.overshoot: Motion.springOvershoot }
            }
            Behavior on scale { enabled: root.opened && root.layoutSettled && stackCard.inStack;
              NumberAnimation { duration: root.moveDuration; easing.type: Motion.easeExpressive; easing.overshoot: Motion.springOvershoot }
            }
            Behavior on rotation { enabled: root.opened && root.layoutSettled && stackCard.inStack;
              NumberAnimation { duration: root.moveDuration; easing.type: Motion.easeExpressive }
            }
            Behavior on opacity { enabled: root.opened && root.layoutSettled && stackCard.inStack;
              NumberAnimation { duration: Math.round(root.moveDuration * 0.75); easing.type: Motion.easeMicro }
            }

            // Click interaction for flanking cards in the deck
            MouseArea {
              anchors.fill: parent
              enabled: !stackCard.isHero
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: stackCard.isHovered = true
              onExited: stackCard.isHovered = false
              onClicked: root.select(index)
            }

            // Hero Card Mouse Tracking for Dynamic 3D Parallax Tilt
            MouseArea {
              anchors.fill: parent
              enabled: stackCard.isHero && !root.peekMode
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              z: 280
              onPositionChanged: function(mouse) {
                stackCard.tiltAngleX = Math.max(-3.5, Math.min(3.5, ((mouse.y / stackCard.height) - 0.5) * -5.5))
                stackCard.tiltAngleY = Math.max(-3.5, Math.min(3.5, ((mouse.x / stackCard.width) - 0.5) * 5.5))
                stackCard.sheenNormX = Math.max(0.0, Math.min(1.0, mouse.x / stackCard.width))
              }
              onEntered: stackCard.isHovered = true
              onExited: {
                stackCard.isHovered = false
                stackCard.tiltAngleX = 0.0
                stackCard.tiltAngleY = 0.0
                stackCard.sheenNormX = 0.5
              }
              onDoubleClicked: root.togglePeek()
            }

            // -------------------------------------------------------------
            // Solid Hardware-Accelerated Masked Card Body (Anti-Aliased Rounded Clipping)
            // -------------------------------------------------------------
            Rectangle {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: stackCard.inStack
              radius: Style.space(24)
            }

            Item {
              id: cardSurface
              anchors.fill: parent
              layer.enabled: stackCard.inStack
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.2
                maskSpreadAtMin: 0.2
              }

              Rectangle {
                anchors.fill: parent
                radius: Style.space(24)
                color: ShellCommons.Color.background
              }

              // 1. Instant Fast Preview Thumbnail
              Image {
                id: thumbImage
                anchors.fill: parent
                visible: status === Image.Ready
                retainWhileLoading: false
                source: (stackCard.sourceActivated && (stackCard.thumbnailPath || stackCard.filePath)) ? Util.fileUrl(stackCard.thumbnailPath || stackCard.filePath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: stackCard.isHero ? Math.ceil(root.heroWidth * root.previewPixelRatio) : Math.ceil(root.heroWidth * 0.45 * root.previewPixelRatio)
                cache: true
                smooth: true
                mipmap: true
              }

              // 2. Crystal-Clear Full-Res Master Wallpaper (Direct rendering on hero card)
              Image {
                id: heroMasterImage
                anchors.fill: parent
                visible: stackCard.isHero && status === Image.Ready && stackCard.filePath && (stackCard.filePath !== stackCard.thumbnailPath)
                retainWhileLoading: false
                source: (stackCard.isHero && stackCard.sourceActivated && stackCard.filePath && (stackCard.filePath !== stackCard.thumbnailPath)) ? Util.fileUrl(stackCard.filePath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: Math.ceil(root.heroWidth * root.previewPixelRatio)
                cache: true
                smooth: true
                mipmap: true
                opacity: (status === Image.Ready) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 180 } }
              }

              // Pending/error feedback keeps the selected item's title and artwork coherent.
              Text {
                anchors.centerIn: parent
                width: parent.width - Style.space(96)
                visible: stackCard.isHero && (stackCard.previewState === "loading" || stackCard.previewState === "error")
                text: stackCard.previewState === "error" ? "Preview unavailable" : "Loading preview…"
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                color: Util.alpha(root.foreground, 0.82)
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }

              // 3. Cinematic Dark Vignette for Contrast & Text Legibility
              Rectangle {
                visible: stackCard.isHero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.round(parent.height * 0.48)
                gradient: Gradient {
                  GradientStop { position: 0.0; color: "transparent" }
                  GradientStop { position: 0.55; color: Util.alpha(ShellCommons.Color.background, 0.45) }
                  GradientStop { position: 1.0; color: Util.alpha(ShellCommons.Color.background, 0.92) }
                }
              }

              // 4. Subtle Ambient Dimmer for Flanking Cards
              Rectangle {
                anchors.fill: parent
                visible: !stackCard.isHero
                color: Util.alpha(root.dimColor, stackCard.isHovered ? 0.15 : Math.min(0.60, 0.24 + Math.abs(stackCard.relativeIndex) * 0.12))
                Behavior on color { ColorAnimation { duration: 140 } }
              }

              // 5. Glass Top Sheen on Hero Card
              Rectangle {
                visible: stackCard.isHero
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Style.space(48)
                radius: Style.space(24)
                gradient: Gradient {
                  GradientStop { position: 0.0; color: Util.alpha("#ffffff", 0.16) }
                  GradientStop { position: 1.0; color: "transparent" }
                }
              }

              // Dynamic Specular Light Sheen tracking cursor
              Rectangle {
                visible: stackCard.isHero
                anchors.fill: parent
                radius: Style.space(24)
                opacity: stackCard.isHovered ? 0.32 : 0.0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: Math.max(0.0, stackCard.sheenNormX - 0.28); color: "transparent" }
                  GradientStop { position: stackCard.sheenNormX; color: Util.alpha("#ffffff", 0.18) }
                  GradientStop { position: Math.min(1.0, stackCard.sheenNormX + 0.28); color: "transparent" }
                }
              }
            }

            // Floating Left Nav Arrow (Docked inside Hero Card)
            Rectangle {
              visible: stackCard.isHero && root.imageArray.length > 1
              opacity: root.peekMode ? 0.0 : 1.0
              Behavior on opacity { NumberAnimation { duration: 180 } }
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(44)
              height: Style.space(44)
              radius: Style.space(22)
              z: 350
              color: leftArrowMouse.containsMouse ? Util.alpha(ShellCommons.Color.background, 0.95) : Util.alpha(ShellCommons.Color.background, 0.65)
              border.color: leftArrowMouse.containsMouse ? root.selectedBorder : Util.alpha(ShellCommons.Color.foreground, 0.25)
              border.width: 1.5
              scale: leftArrowMouse.pressed ? 0.90 : (leftArrowMouse.containsMouse ? 1.10 : 1.0)

              Behavior on scale { NumberAnimation { duration: 120 } }
              Behavior on color { ColorAnimation { duration: 150 } }
              Behavior on border.color { ColorAnimation { duration: 150 } }

              Text {
                anchors.centerIn: parent
                text: "󰅁"
                color: leftArrowMouse.containsMouse ? root.selectedBorder : root.foreground
                font.pixelSize: Style.font.heading || Style.font.body
                font.family: Style.font.menuFamily
              }

              MouseArea {
                id: leftArrowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectAdjacent(-1)
              }
            }

            // Floating Right Nav Arrow (Docked inside Hero Card)
            Rectangle {
              visible: stackCard.isHero && root.imageArray.length > 1
              opacity: root.peekMode ? 0.0 : 1.0
              Behavior on opacity { NumberAnimation { duration: 180 } }
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(44)
              height: Style.space(44)
              radius: Style.space(22)
              z: 350
              color: rightArrowMouse.containsMouse ? Util.alpha(ShellCommons.Color.background, 0.95) : Util.alpha(ShellCommons.Color.background, 0.65)
              border.color: rightArrowMouse.containsMouse ? root.selectedBorder : Util.alpha(ShellCommons.Color.foreground, 0.25)
              border.width: 1.5
              scale: rightArrowMouse.pressed ? 0.90 : (rightArrowMouse.containsMouse ? 1.10 : 1.0)

              Behavior on scale { NumberAnimation { duration: 120 } }
              Behavior on color { ColorAnimation { duration: 150 } }
              Behavior on border.color { ColorAnimation { duration: 150 } }

              Text {
                anchors.centerIn: parent
                text: "󰅂"
                color: rightArrowMouse.containsMouse ? root.selectedBorder : root.foreground
                font.pixelSize: Style.font.heading || Style.font.body
                font.family: Style.font.menuFamily
              }

              MouseArea {
                id: rightArrowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectAdjacent(1)
              }
            }

            // Floating Ground Shadow beneath Hero Card
            Rectangle {
              visible: stackCard.isHero && !root.peekMode
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.bottom
              anchors.topMargin: Style.space(10)
              width: Math.round(parent.width * 0.84)
              height: Style.space(20)
              radius: Style.space(10)
              color: "black"
              opacity: 0.45
            }

            // Glowing Ambient Rim on Hero Card
            Rectangle {
              visible: stackCard.isHero && !root.peekMode
              opacity: root.peekMode ? 0.0 : 1.0
              Behavior on opacity { NumberAnimation { duration: 180 } }
              anchors.fill: parent
              anchors.margins: -Style.space(3)
              radius: Style.space(27)
              color: "transparent"
              border.color: Util.alpha(root.selectedBorder, 0.40)
              border.width: 2
              antialiasing: true
            }

            // High-Precision Specular Border
            Rectangle {
              anchors.fill: parent
              opacity: root.peekMode ? 0.0 : 1.0
              Behavior on opacity { NumberAnimation { duration: 180 } }
              radius: Style.space(24)
              color: "transparent"
              border.color: stackCard.isHero ? root.selectedBorder : (stackCard.isHovered ? Util.alpha(root.selectedBorder, 0.85) : Util.alpha(ShellCommons.Color.foreground, 0.20))
              border.width: stackCard.isHero ? 2.5 : 1
              antialiasing: true

              Behavior on border.color { ColorAnimation { duration: 150 } }
              Behavior on border.width { NumberAnimation { duration: 150 } }
            }

            Rectangle {
              anchors.fill: parent
              anchors.margins: 1
              opacity: root.peekMode ? 0.0 : 1.0
              Behavior on opacity { NumberAnimation { duration: 180 } }
              radius: Style.space(23)
              color: "transparent"
              border.color: stackCard.isHero ? Util.alpha("#ffffff", 0.22) : Util.alpha("#ffffff", 0.05)
              border.width: 1
              antialiasing: true
            }

            // Top Status Badges on Hero Card
            Row {
              visible: stackCard.isHero
              z: 350
              opacity: root.peekMode ? 0.0 : 1.0
              Behavior on opacity { NumberAnimation { duration: 180 } }
              anchors.top: parent.top
              anchors.topMargin: Style.space(18)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(18)
              spacing: Style.space(8)

              // Active Theme Indicator Badge
              Rectangle {
                visible: stackCard.isCurrentTheme
                height: Style.space(28)
                width: activeBadgeText.width + Style.space(22)
                radius: Style.space(14)
                color: Util.alpha("#10B981", 0.92)
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

              // Deck Position Pill
              Rectangle {
                height: Style.space(28)
                width: posBadgeText.width + Style.space(20)
                radius: Style.space(14)
                color: Util.alpha(ShellCommons.Color.background, 0.86)
                border.color: Util.alpha(ShellCommons.Color.foreground, 0.22)
                border.width: 1

                Row {
                  id: posBadgeText
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    text: "󰓩"
                    color: root.selectedBorder
                    font.pixelSize: Style.font.caption
                    font.family: Style.font.menuFamily
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: (root.selectedFilteredPosition() + 1) + " / " + (root.filterText ? root.filterPositions.filter(function(p) { return p >= 0 }).length : root.imageArray.length)
                    color: root.foreground
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                    font.family: Style.font.menuFamily
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }

            // Top Left Stack Relative Index Indicator (On flanking cards)
            Rectangle {
              visible: !stackCard.isHero && stackCard.inStack
              anchors.top: parent.top
              anchors.topMargin: Style.space(14)
              anchors.left: stackCard.relativeIndex > 0 ? undefined : parent.left
              anchors.right: stackCard.relativeIndex > 0 ? parent.right : undefined
              anchors.margins: Style.space(14)
              height: Style.space(24)
              width: Style.space(24)
              radius: Style.space(12)
              color: Util.alpha(ShellCommons.Color.background, 0.85)
              border.color: Util.alpha(ShellCommons.Color.foreground, 0.25)
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: stackCard.relativeIndex > 0 ? "+" + stackCard.relativeIndex : stackCard.relativeIndex
                color: root.selectedBorder
                font.pixelSize: Style.font.caption
                font.weight: Font.Bold
                font.family: Style.font.menuFamily
              }
            }

            // Floating Frosted Info Dock inside Hero Card
            Rectangle {
              visible: stackCard.isHero
              z: 350
              opacity: root.peekMode ? 0.0 : 1.0
              Behavior on opacity { NumberAnimation { duration: 180 } }
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(16)
              height: Style.space(76)
              radius: Style.space(22)
              color: Util.alpha(ShellCommons.Color.background, 0.92)
              border.color: Util.alpha(ShellCommons.Color.foreground, 0.20)
              border.width: 1.5

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(20)
                anchors.rightMargin: Style.space(16)

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(14)
                  width: parent.width - applyButtonHint.width - Style.space(16)

                  Rectangle {
                    width: Style.space(44)
                    height: Style.space(44)
                    radius: Style.space(22)
                    color: stackCard.isCurrentTheme ? Util.alpha("#10B981", 0.22) : Util.alpha(root.selectedBorder, 0.20)
                    border.color: stackCard.isCurrentTheme ? "#34D399" : Util.alpha(root.selectedBorder, 0.50)
                    border.width: 1.5
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      text: stackCard.isCurrentTheme ? "󰄬" : "󰸌"
                      color: stackCard.isCurrentTheme ? "#10B981" : root.selectedBorder
                      font.pixelSize: Style.font.heading || Style.font.body
                      font.family: Style.font.menuFamily
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(3)
                    width: parent.width - Style.space(58)

                    Row {
                      spacing: Style.space(10)
                      anchors.left: parent.left
                      anchors.right: parent.right

                      Text {
                        text: stackCard.cleanTitle
                        color: root.foreground
                        font.pixelSize: Style.font.headingLarge || Style.font.heading
                        font.weight: Font.Bold
                        font.family: Style.font.menuFamily
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Rectangle {
                        visible: !!stackCard.countInTitle
                        height: Style.space(22)
                        width: countBadgeContent.width + Style.space(14)
                        radius: Style.space(11)
                        color: Util.alpha(root.selectedBorder, 0.18)
                        border.color: Util.alpha(root.selectedBorder, 0.40)
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                          id: countBadgeContent
                          anchors.centerIn: parent
                          spacing: Style.space(4)

                          Text {
                            text: "󰉋"
                            color: root.selectedBorder
                            font.pixelSize: Style.font.caption
                            font.family: Style.font.menuFamily
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Text {
                            text: stackCard.countInTitle + " in group"
                            color: root.foreground
                            font.pixelSize: Style.font.caption
                            font.weight: Font.Medium
                            font.family: Style.font.menuFamily
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }
                      }

                      // Dynamic Theme Color Harmony Swatches
                      Rectangle {
                        visible: !!stackCard.accentColorHex
                        height: Style.space(22)
                        width: swatchRow.width + Style.space(14)
                        radius: Style.space(11)
                        color: Util.alpha(ShellCommons.Color.background, 0.75)
                        border.color: Util.alpha(ShellCommons.Color.foreground, 0.20)
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                          id: swatchRow
                          anchors.centerIn: parent
                          spacing: Style.space(5)

                          // Accent Dot
                          Rectangle {
                            width: Style.space(10)
                            height: Style.space(10)
                            radius: Style.space(5)
                            color: stackCard.accentColorHex || root.selectedBorder
                            border.color: Util.alpha("#ffffff", 0.40)
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          // BG Dot
                          Rectangle {
                            visible: !!stackCard.bgColorHex
                            width: Style.space(10)
                            height: Style.space(10)
                            radius: Style.space(5)
                            color: stackCard.bgColorHex || ShellCommons.Color.background
                            border.color: Util.alpha("#ffffff", 0.30)
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          // FG Dot
                          Rectangle {
                            visible: !!stackCard.fgColorHex
                            width: Style.space(10)
                            height: Style.space(10)
                            radius: Style.space(5)
                            color: stackCard.fgColorHex || root.foreground
                            border.color: Util.alpha("#ffffff", 0.30)
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }
                      }

                      // Star / Favorite Toggle Button
                      Rectangle {
                        readonly property bool isFav: stackCard.themeName ? root.isFavorite(stackCard.themeName) : false
                        height: Style.space(22)
                        width: Style.space(22)
                        radius: Style.space(11)
                        color: isFav ? Util.alpha("#F59E0B", 0.25) : (starMouse.containsMouse ? Util.alpha(ShellCommons.Color.foreground, 0.15) : "transparent")
                        border.color: isFav ? "#F59E0B" : (starMouse.containsMouse ? Util.alpha(ShellCommons.Color.foreground, 0.35) : Util.alpha(ShellCommons.Color.foreground, 0.20))
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        scale: starMouse.pressed ? 0.88 : (starMouse.containsMouse ? 1.15 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        Text {
                          anchors.centerIn: parent
                          text: parent.isFav ? "★" : "☆"
                          color: parent.isFav ? "#F59E0B" : (starMouse.containsMouse ? "#F59E0B" : Util.alpha(root.foreground, 0.50))
                          font.pixelSize: Style.font.caption
                          font.weight: Font.Bold
                          font.family: Style.font.menuFamily
                        }

                        MouseArea {
                          id: starMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (stackCard.themeName)
                              root.toggleFavorite(stackCard.themeName)
                          }
                        }
                      }
                    }

                    Text {
                      text: root.showLabels ? (stackCard.isCurrentTheme ? "Currently active system theme • Ready to switch" : "Press Enter or click Apply to activate desktop theme") : "Press Enter or click Apply to set desktop wallpaper"
                      color: Util.alpha(root.foreground, 0.70)
                      font.pixelSize: Style.font.bodySmall
                      font.family: Style.font.menuFamily
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }
                }

                // Apply Button Action Pill
                Rectangle {
                  id: applyButtonHint
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(44)
                  width: applyButtonContent.width + Style.space(32)
                  radius: Style.space(22)
                  gradient: Gradient {
                    GradientStop { position: 0.0; color: applyMouseArea.containsMouse ? root.selectedBorder : Util.alpha(root.selectedBorder, 0.95) }
                    GradientStop { position: 1.0; color: applyMouseArea.containsMouse ? root.selectedBorder : Util.alpha(root.selectedBorder, 0.80) }
                  }
                  border.color: Util.alpha("#ffffff", 0.25)
                  border.width: 1
                  scale: applyMouseArea.pressed ? 0.93 : (applyMouseArea.containsMouse ? 1.05 : 1.0)

                  Behavior on scale { enabled: root.opened && root.layoutSettled && stackCard.inStack; NumberAnimation { duration: 120 } }

                  Row {
                    id: applyButtonContent
                    anchors.centerIn: parent
                    spacing: Style.space(8)

                    Text {
                      text: "󰌑"
                      color: ShellCommons.Color.background
                      font.pixelSize: Style.font.body
                      font.family: Style.font.menuFamily
                      font.weight: Font.Bold
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      text: root.applyButtonText
                      color: ShellCommons.Color.background
                      font.pixelSize: Style.font.bodySmall
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
          }
        }
      }

      // =======================================================================
      // 3. INTERACTIVE DECK SCRUBBER (Tactile Timeline Ribbon)
      // =======================================================================
      Item {
        id: scrubBar
        opacity: root.peekMode ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.bottom: bottomHud.top
        anchors.bottomMargin: Style.space(14)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(Style.space(480), parent.width - Style.space(80))
        height: Style.space(16)
        visible: root.imageArray.length > 1

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: Style.space(4)
          radius: Style.space(2)
          color: Util.alpha(ShellCommons.Color.foreground, 0.16)

          Rectangle {
            id: scrubFill
            height: parent.height
            radius: parent.radius
            color: root.selectedBorder
            width: {
              var count = root.filterText ? root.filterPositions.filter(function(p) { return p >= 0 }).length : root.imageArray.length
              if (count <= 1) return parent.width
              return Math.max(Style.space(16), Math.round(parent.width * ((root.selectedFilteredPosition() + 1) / count)))
            }
            Behavior on width { NumberAnimation { duration: 120 } }
          }
        }

        // Glowing Scrub Handle
        Rectangle {
          x: Math.max(0, Math.min(parent.width - width, scrubFill.width - width / 2))
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(14)
          height: Style.space(14)
          radius: Style.space(7)
          color: root.selectedBorder
          border.color: "#ffffff"
          border.width: 1.5

          Behavior on x { NumberAnimation { duration: 120 } }
        }

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(8)
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            var count = root.imageArray.length
            if (count === 0) return
            var ratio = Math.max(0, Math.min(1, mouse.x / scrubBar.width))
            var targetIdx = Math.floor(ratio * (count - 1))
            root.select(targetIdx)
          }
        }
      }

      // =======================================================================
      // 4. BOTTOM FLOATING CONTROLS HUD (Shortcuts & Quick Guidance)
      // =======================================================================
      Rectangle {
        id: bottomHud
        opacity: root.peekMode ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(12)
        anchors.horizontalCenter: parent.horizontalCenter
        height: Style.space(40)
        width: bottomRow.width + Style.space(34)
        radius: Style.space(20)
        color: Util.alpha(ShellCommons.Color.background, 0.90)
        border.color: Util.alpha(ShellCommons.Color.foreground, 0.16)
        border.width: 1

        Row {
          id: bottomRow
          anchors.centerIn: parent
          spacing: Style.space(10)

          Row {
            spacing: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(22)
              width: Style.space(42)
              radius: Style.space(5)
              color: Util.alpha(ShellCommons.Color.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "◄ ►"; color: root.foreground; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Deck"; color: Util.alpha(root.foreground, 0.75); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(ShellCommons.Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(22)
              width: Style.space(48)
              radius: Style.space(5)
              color: Util.alpha(root.selectedBorder, 0.25)
              Text { anchors.centerIn: parent; text: "Enter"; color: root.selectedBorder; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Apply"; color: Util.alpha(root.foreground, 0.75); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(ShellCommons.Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(22)
              width: Style.space(48)
              radius: Style.space(5)
              color: Util.alpha(ShellCommons.Color.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "Space"; color: root.foreground; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Peek"; color: Util.alpha(root.foreground, 0.75); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(ShellCommons.Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(22)
              width: Style.space(46)
              radius: Style.space(5)
              color: Util.alpha(ShellCommons.Color.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "Ctrl+R"; color: root.foreground; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Shuffle"; color: Util.alpha(root.foreground, 0.75); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(ShellCommons.Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(22)
              width: Style.space(46)
              radius: Style.space(5)
              color: Util.alpha("#F59E0B", 0.22)
              Text { anchors.centerIn: parent; text: "Ctrl+S"; color: "#F59E0B"; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Star"; color: Util.alpha(root.foreground, 0.75); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(ShellCommons.Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(22)
              width: Style.space(46)
              radius: Style.space(5)
              color: Util.alpha(ShellCommons.Color.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "Ctrl+M"; color: root.foreground; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Sound"; color: Util.alpha(root.foreground, 0.75); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }

          Rectangle { width: 1; height: Style.space(12); color: Util.alpha(ShellCommons.Color.foreground, 0.15); anchors.verticalCenter: parent.verticalCenter }

          Row {
            spacing: Style.space(5)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              height: Style.space(22)
              width: Style.space(36)
              radius: Style.space(5)
              color: Util.alpha(ShellCommons.Color.foreground, 0.12)
              Text { anchors.centerIn: parent; text: "Esc"; color: root.foreground; font.pixelSize: Style.font.caption; font.weight: Font.Bold; font.family: Style.font.menuFamily }
            }
            Text { text: "Close"; color: Util.alpha(root.foreground, 0.75); font.pixelSize: Style.font.caption; font.family: Style.font.menuFamily; anchors.verticalCenter: parent.verticalCenter }
          }
        }
      }

      // =======================================================================
      // 5. FLOATING FULLSCREEN PEEK EXIT PILL
      // =======================================================================
      Rectangle {
        id: peekExitPill
        visible: root.peekMode
        opacity: root.peekMode ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        height: Style.space(40)
        width: peekExitRow.width + Style.space(36)
        radius: Style.space(20)
        color: Util.alpha(ShellCommons.Color.background, 0.92)
        border.color: Util.alpha(ShellCommons.Color.foreground, 0.25)
        border.width: 1.5
        z: 9999

        Row {
          id: peekExitRow
          anchors.centerIn: parent
          spacing: Style.space(10)

          Rectangle {
            height: Style.space(22)
            width: Style.space(50)
            radius: Style.space(6)
            color: Util.alpha(root.selectedBorder, 0.25)
            border.color: Util.alpha(root.selectedBorder, 0.50)
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Space"
              color: root.selectedBorder
              font.pixelSize: Style.font.caption
              font.weight: Font.Bold
              font.family: Style.font.menuFamily
            }
          }

          Text {
            text: "Fullscreen Preview • Press Space, Esc or click to exit"
            color: root.foreground
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.family: Style.font.menuFamily
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePeek()
        }
      }
    }
  }
}
