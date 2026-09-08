import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property string currentBackground: ""
  property string targetBackground: ""
  property string incomingBackground: ""
  property int activeSlot: 0
  property string slotASource: ""
  property string slotBSource: ""
  property bool transitioning: false
  property real revealProgress: 1.0
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""

  readonly property var modeIndices: ({
    "color-morph": 0,
    "aurora-flow": 1,
    "ink-spread": 2,
    "prism-shift": 3,
    "liquid-transform": 4,
    "atmospheric-fade": 5,
    "material-repaint": 6,
    "reality-shift": 7
  })

  readonly property int transitionModeInt: {
    var idx = modeIndices[ThemeTransition.currentMode]
    return (idx !== undefined) ? idx : 0
  }

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running && !transitioning) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, true)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    var targetImg = finalPath || path
    if (!targetImg || (!force && targetImg === currentBackground)) return
    currentBackground = targetImg
    backgroundVersion += 1
    revealStartedVersion = -1

    if (revealAnimation.running) {
      revealAnimation.stop()
      activeSlot = (activeSlot === 0 ? 1 : 0)
    }

    if (instant || (!slotASource && !slotBSource)) {
      activeSlot = 0
      slotASource = imageUrl(targetImg)
      slotBSource = ""
      targetBackground = targetImg
      incomingBackground = ""
      transitioning = false
      revealProgress = 1.0
      transitionSafetyTimer.stop()
      return
    }

    targetBackground = targetImg
    incomingBackground = targetImg
    transitioning = true
    revealProgress = 0.0
    transitionSafetyTimer.restart()

    // Assign new image to the inactive slot
    if (activeSlot === 0) {
      slotBSource = imageUrl(targetImg)
    } else {
      slotASource = imageUrl(targetImg)
    }
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    ThemeTransition.startTransition(pendingColorsRaw, pendingShellRaw)
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!transitioning || revealProgress >= 1.0) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!transitioning) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.duration = ThemeTransition.getDuration(ThemeTransition.currentMode)
    revealAnimation.easing.type = ThemeTransition.getEasing(ThemeTransition.currentMode)
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p && !root.transitioning) root.setBackground(p, false)
      }
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  Timer {
    id: transitionSafetyTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.transitioning) {
        revealAnimation.stop()
        root.activeSlot = (root.activeSlot === 0 ? 1 : 0)
        if (root.activeSlot === 0) {
          root.slotASource = root.imageUrl(root.targetBackground)
        } else {
          root.slotBSource = root.imageUrl(root.targetBackground)
        }
        root.displayedBackground = root.targetBackground
        root.transitioning = false
        root.revealProgress = 1.0
        root.incomingBackground = ""
        root.applyPendingTheme()
        ThemeTransition.finishTransition()
      }
    }
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0.0
    to: 1.0
    duration: ThemeTransition.getDuration(ThemeTransition.currentMode)
    easing.type: ThemeTransition.getEasing(ThemeTransition.currentMode)
    onFinished: {
      transitionSafetyTimer.stop()
      // Flip active slot to make the newly rendered wallpaper authoritative
      root.activeSlot = (root.activeSlot === 0 ? 1 : 0)
      if (root.activeSlot === 0) {
        root.slotASource = root.imageUrl(root.targetBackground)
      } else {
        root.slotBSource = root.imageUrl(root.targetBackground)
      }
      root.displayedBackground = root.targetBackground
      root.transitioning = false
      root.revealProgress = 1.0
      root.incomingBackground = ""
      ThemeTransition.finishTransition()
    }
  }

  property string displayedBackground: ""

  Component.onCompleted: refreshBackground()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      updatesEnabled: true

      property bool maskReady: false

      readonly property Item incomingSlotItem: root.activeSlot === 0 ? slotB : slotA
      readonly property Item activeSlotItem: root.activeSlot === 0 ? slotA : slotB

      function maybeStartReveal() {
        if (!root.transitioning || maskReady) return
        if (incomingSlotItem.status === Image.Error) {
          transitionSafetyTimer.triggered()
          return
        }
        if (incomingSlotItem.status !== Image.Ready) return
        root.startReveal(panel)
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: slotA
        anchors.fill: parent
        source: root.slotASource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        visible: root.activeSlot === 0 || root.transitioning
        z: root.activeSlot === 0 ? 2 : 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Image {
        id: slotB
        anchors.fill: parent
        source: root.slotBSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        visible: root.activeSlot === 1 || root.transitioning
        z: root.activeSlot === 1 ? 2 : 1
        onStatusChanged: panel.maybeStartReveal()
      }

      ShaderEffect {
        id: transitionShader
        anchors.fill: parent
        visible: root.transitioning && panel.maskReady
        z: 3

        property var source: root.activeSlot === 0 ? slotA : slotB
        property var incoming: root.activeSlot === 0 ? slotB : slotA
        property real progress: root.revealProgress
        property int mode: root.transitionModeInt
        property real aspect: width / Math.max(1.0, height)
        property color accent: ThemeTransition.targetAccent

        fragmentShader: Qt.resolvedUrl("shaders/transition.frag.qsb")
      }

      Connections {
        target: root
        function onTransitioningChanged() {
          if (root.transitioning) {
            panel.maskReady = false
            panel.maybeStartReveal()
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
