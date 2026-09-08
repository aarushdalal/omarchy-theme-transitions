pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Universal Theme Switching Transition Engine for Omarchy
// Orchestrates visual transitions when switching Theme A -> Theme B across
// 8 distinct mathematical & perceptual signature modes with zero hardcoded themes.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state/omarchy"
  readonly property string modeFilePath: stateHome + "/theme-transition-mode"
  readonly property string reducedMotionFilePath: stateHome + "/reduced-motion"

  // 1. Transition Mode Selection
  property string currentMode: "color-morph"
  property bool reducedMotion: false
  property bool active: false
  property real progress: 0.0
  property bool needsOverlay: false

  // 2. Semantic Color States
  property color startForeground: Color.foreground
  property color startBackground: Color.background
  property color startAccent: Color.accent
  property color startUrgent: Color.urgent
  property color startMuted: Color.muted

  property color targetForeground: Color.foreground
  property color targetBackground: Color.background
  property color targetAccent: Color.accent
  property color targetUrgent: Color.urgent
  property color targetMuted: Color.muted

  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""

  // 3. Mode-Specific Dynamic Properties
  property real auroraX: -0.6
  property real inkRadius: 0.0
  property real prismAberration: 0.0
  property real liquidTension: 0.0
  property real atmosphericDim: 1.0
  property real materialScanY: 0.0
  property real realityWarp: 0.0

  // 4. Persistence Watchers
  property FileView modeFile: FileView {
    path: root.modeFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadMode(text())
    onFileChanged: reload()
    onLoadFailed: root.currentMode = "color-morph"
  }

  property FileView reducedMotionFile: FileView {
    path: root.reducedMotionFilePath
    watchChanges: true
    printErrors: false
    onLoaded: root.reducedMotion = (String(text() || "").trim() === "true")
    onFileChanged: reload()
    onLoadFailed: root.reducedMotion = false
  }

  function loadMode(raw) {
    var m = String(raw || "").trim().toLowerCase()
    var validModes = [
      "color-morph", "aurora-flow", "ink-spread", "prism-shift",
      "liquid-transform", "atmospheric-fade", "material-repaint", "reality-shift"
    ]
    if (validModes.indexOf(m) >= 0) {
      currentMode = m
    } else {
      currentMode = "color-morph"
    }
  }

  // 5. Mathematical & Perceptual Color Interpolation
  function clamp01(v) {
    return Math.max(0.0, Math.min(1.0, v))
  }

  function luminance(c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
  }

  // Gamma-corrected perceptual blending: prevents dark muddy midtones
  function lerpPerceptual(c1, c2, t) {
    t = clamp01(t)
    var r = Math.sqrt((1.0 - t) * c1.r * c1.r + t * c2.r * c2.r)
    var g = Math.sqrt((1.0 - t) * c1.g * c1.g + t * c2.g * c2.g)
    var b = Math.sqrt((1.0 - t) * c1.b * c1.b + t * c2.b * c2.b)
    var a = (1.0 - t) * c1.a + t * c2.a
    return Qt.rgba(r, g, b, a)
  }

  function lerpColorLinear(c1, c2, t) {
    t = clamp01(t)
    return Qt.rgba(
      (1.0 - t) * c1.r + t * c2.r,
      (1.0 - t) * c1.g + t * c2.g,
      (1.0 - t) * c1.b + t * c2.b,
      (1.0 - t) * c1.a + t * c2.a
    )
  }

  // 6. Transition Timing Configurations
  function getDuration(mode) {
    switch (mode) {
      case "aurora-flow":        return 700
      case "ink-spread":         return 650
      case "prism-shift":        return 550
      case "liquid-transform":   return 600
      case "atmospheric-fade":   return 600
      case "material-repaint":   return 750
      case "reality-shift":      return 500
      case "color-morph":
      default:                   return 420
    }
  }

  function getEasing(mode) {
    switch (mode) {
      case "aurora-flow":        return Easing.OutQuad
      case "ink-spread":         return Easing.OutCubic
      case "prism-shift":        return Easing.InOutCubic
      case "liquid-transform":   return Easing.OutBack
      case "atmospheric-fade":   return Easing.InOutQuad
      case "material-repaint":   return Easing.Linear
      case "reality-shift":      return Easing.InOutQuad
      case "color-morph":
      default:                   return Easing.OutCubic
    }
  }

  function checkNeedsOverlay(mode) {
    return false
  }

  // 7. Core Interpolation Loop (Called on every frame)
  function applyProgress(p) {
    p = clamp01(p)
    var startBgLum = luminance(startBackground)
    var targetBgLum = luminance(targetBackground)
    var isPolarityFlip = (startBgLum < 0.5) !== (targetBgLum < 0.5)

    // Mode-specific parameter and color calculations
    switch (currentMode) {
      case "aurora-flow":
        auroraX = -0.6 + p * 2.2
        applyStandardLerp(p, isPolarityFlip)
        break

      case "ink-spread":
        inkRadius = p * 1.5
        applyStandardLerp(p, isPolarityFlip)
        break

      case "prism-shift":
        prismAberration = Math.sin(p * Math.PI)
        applyPrismShift(p, isPolarityFlip)
        break

      case "liquid-transform":
        liquidTension = Math.sin(p * Math.PI)
        applyLiquidTransform(p, isPolarityFlip)
        break

      case "atmospheric-fade":
        atmosphericDim = 1.0 - (Math.sin(p * Math.PI) * 0.28)
        applyAtmosphericFade(p, isPolarityFlip)
        break

      case "material-repaint":
        materialScanY = p
        applyMaterialRepaint(p)
        break

      case "reality-shift":
        realityWarp = Math.sin(p * Math.PI)
        applyRealityShift(p, isPolarityFlip)
        break

      case "color-morph":
      default:
        applyStandardLerp(p, isPolarityFlip)
        break
    }
  }

  // Standard Perceptual Interpolation with Contrast Preservation
  function applyStandardLerp(p, isPolarityFlip) {
    var tBg = p
    var tFg = p
    if (isPolarityFlip) {
      // Offset text transition so background reaches safe luminance threshold first
      tBg = p < 0.6 ? (p / 0.6) : 1.0
      tFg = p > 0.4 ? ((p - 0.4) / 0.6) : 0.0
    }

    var fg = lerpPerceptual(startForeground, targetForeground, tFg)
    var bg = lerpPerceptual(startBackground, targetBackground, tBg)
    var ac = lerpPerceptual(startAccent, targetAccent, p)
    var ur = lerpPerceptual(startUrgent, targetUrgent, p)
    var mu = lerpPerceptual(startMuted, targetMuted, tFg)

    Color.setSemanticPalette(fg, bg, ac, ur, mu)
  }

  // Mode 4: Prism Shift (Optical dispersion during transition)
  function applyPrismShift(p, isPolarityFlip) {
    var tBg = p
    var tFg = p
    if (isPolarityFlip) {
      tBg = p < 0.6 ? (p / 0.6) : 1.0
      tFg = p > 0.4 ? ((p - 0.4) / 0.6) : 0.0
    }

    // Micro-channel separation in accent & text
    var disp = Math.sin(p * Math.PI) * 0.12
    var tR = clamp01(p + disp)
    var tB = clamp01(p - disp)

    var acR = Math.sqrt((1.0 - tR) * startAccent.r * startAccent.r + tR * targetAccent.r * targetAccent.r)
    var acG = Math.sqrt((1.0 - p) * startAccent.g * startAccent.g + p * targetAccent.g * targetAccent.g)
    var acB = Math.sqrt((1.0 - tB) * startAccent.b * startAccent.b + tB * targetAccent.b * targetAccent.b)

    var fg = lerpPerceptual(startForeground, targetForeground, tFg)
    var bg = lerpPerceptual(startBackground, targetBackground, tBg)
    var ac = Qt.rgba(acR, acG, acB, 1.0)
    var ur = lerpPerceptual(startUrgent, targetUrgent, p)
    var mu = lerpPerceptual(startMuted, targetMuted, tFg)

    Color.setSemanticPalette(fg, bg, ac, ur, mu)
  }

  // Mode 5: Liquid Transform (Fluid viscosity & elastic swelling)
  function applyLiquidTransform(p, isPolarityFlip) {
    var tBg = p
    var tFg = p
    if (isPolarityFlip) {
      tBg = p < 0.6 ? (p / 0.6) : 1.0
      tFg = p > 0.4 ? ((p - 0.4) / 0.6) : 0.0
    }

    var swell = 1.0 + (Math.sin(p * Math.PI) * 0.14)
    var baseAc = lerpPerceptual(startAccent, targetAccent, p)
    var ac = Qt.rgba(
      Math.min(1.0, baseAc.r * swell),
      Math.min(1.0, baseAc.g * swell),
      Math.min(1.0, baseAc.b * swell),
      1.0
    )

    var fg = lerpPerceptual(startForeground, targetForeground, tFg)
    var bg = lerpPerceptual(startBackground, targetBackground, tBg)
    var ur = lerpPerceptual(startUrgent, targetUrgent, p)
    var mu = lerpPerceptual(startMuted, targetMuted, tFg)

    Color.setSemanticPalette(fg, bg, ac, ur, mu)
  }

  // Mode 6: Atmospheric Fade (Cinematic environmental luminance dip & bloom)
  function applyAtmosphericFade(p, isPolarityFlip) {
    var dip = 1.0 - (Math.sin(p * Math.PI) * 0.22)
    var tBg = p
    var tFg = p
    if (isPolarityFlip) {
      tBg = p < 0.6 ? (p / 0.6) : 1.0
      tFg = p > 0.4 ? ((p - 0.4) / 0.6) : 0.0
    }

    var baseBg = lerpPerceptual(startBackground, targetBackground, tBg)
    var baseFg = lerpPerceptual(startForeground, targetForeground, tFg)
    var baseAc = lerpPerceptual(startAccent, targetAccent, p)

    var bg = Qt.rgba(baseBg.r * dip, baseBg.g * dip, baseBg.b * dip, 1.0)
    var fg = baseFg
    var ac = Qt.rgba(baseAc.r * dip, baseAc.g * dip, baseAc.b * dip, 1.0)
    var ur = lerpPerceptual(startUrgent, targetUrgent, p)
    var mu = lerpPerceptual(startMuted, targetMuted, tFg)

    Color.setSemanticPalette(fg, bg, ac, ur, mu)
  }

  // Mode 7: Material Repaint (5 Staggered Architectural Stages)
  function applyMaterialRepaint(p) {
    // Stage 1 (0.00 to 0.35): Deep canvas / background
    var t1 = clamp01(p / 0.35)
    // Stage 2 (0.15 to 0.50): Surfaces
    var t2 = clamp01((p - 0.15) / 0.35)
    // Stage 3 (0.30 to 0.65): Borders
    var t3 = clamp01((p - 0.30) / 0.35)
    // Stage 4 (0.45 to 0.80): Text & Muted
    var t4 = clamp01((p - 0.45) / 0.35)
    // Stage 5 (0.60 to 1.00): Accent & Urgent
    var t5 = clamp01((p - 0.60) / 0.40)

    var bg = lerpPerceptual(startBackground, targetBackground, t1)
    var fg = lerpPerceptual(startForeground, targetForeground, t4)
    var ac = lerpPerceptual(startAccent, targetAccent, t5)
    var ur = lerpPerceptual(startUrgent, targetUrgent, t5)
    var mu = lerpPerceptual(startMuted, targetMuted, t4)

    Color.setSemanticPalette(fg, bg, ac, ur, mu)
  }

  // Mode 8: Reality Shift (Dimensional phase frequency warp)
  function applyRealityShift(p, isPolarityFlip) {
    var tBg = p
    var tFg = p
    if (isPolarityFlip) {
      tBg = p < 0.6 ? (p / 0.6) : 1.0
      tFg = p > 0.4 ? ((p - 0.4) / 0.6) : 0.0
    }

    var pulse = Math.sin(p * Math.PI) * 0.10
    var baseAc = lerpPerceptual(startAccent, targetAccent, p)
    // Shift slightly into cyan/holographic during peak warp
    var ac = Qt.rgba(
      Math.max(0.0, baseAc.r * (1.0 - pulse)),
      Math.min(1.0, baseAc.g * (1.0 + pulse * 0.5)),
      Math.min(1.0, baseAc.b * (1.0 + pulse)),
      1.0
    )

    var fg = lerpPerceptual(startForeground, targetForeground, tFg)
    var bg = lerpPerceptual(startBackground, targetBackground, tBg)
    var ur = lerpPerceptual(startUrgent, targetUrgent, p)
    var mu = lerpPerceptual(startMuted, targetMuted, tFg)

    Color.setSemanticPalette(fg, bg, ac, ur, mu)
  }

  // 8. Animation Drivers
  property NumberAnimation transitionAnim: NumberAnimation {
    id: transitionAnim
    target: root
    property: "progress"
    from: 0.0
    to: 1.0
    duration: root.getDuration(root.currentMode)
    easing.type: root.getEasing(root.currentMode)
    easing.overshoot: root.currentMode === "liquid-transform" ? 1.15 : 1.0

    onFinished: root.finishTransition()
  }

  property real lastAppliedProgress: -1

  onProgressChanged: {
    if (!active) return
    // Eliminate main-thread CPU binding storm across top bar widgets during animation.
    // Full 60 FPS GPU shader handles the per-pixel transition with hardware acceleration.
    if (currentMode === "color-morph") {
      if (lastAppliedProgress < 0.5 && progress >= 0.5) {
        lastAppliedProgress = 0.5
        applyProgress(0.5)
      }
    }
  }

  // 9. Public API: Start Transition
  property var completionCallback: null

  function startTransition(colorsRaw, shellRaw, onComplete) {
    var parsed = Color.parseColors(colorsRaw)

    // Capture starting point: if currently animating, take live color values
    startForeground = Color.foreground
    startBackground = Color.background
    startAccent = Color.accent
    startUrgent = Color.urgent
    startMuted = Color.muted

    targetForeground = parsed.foreground
    targetBackground = parsed.background
    targetAccent = parsed.accent
    targetUrgent = parsed.urgent
    targetMuted = parsed.muted

    pendingColorsRaw = colorsRaw
    pendingShellRaw = shellRaw
    completionCallback = onComplete || null

    // Reduced Motion Bypass
    if (reducedMotion) {
      if (transitionAnim.running) transitionAnim.stop()
      Color.loadColors(colorsRaw)
      Color.loadShell(shellRaw)
      Style.scheduleRefresh()
      active = false
      needsOverlay = false
      if (typeof completionCallback === "function") {
        var cb = completionCallback
        completionCallback = null
        cb()
      }
      return
    }

    // Interruption Safety: stop ongoing animation cleanly and retarget
    if (transitionAnim.running) {
      transitionAnim.stop()
    }

    needsOverlay = checkNeedsOverlay(currentMode)
    lastAppliedProgress = -1
    active = true
    progress = 0.0

    transitionAnim.duration = getDuration(currentMode)
    transitionAnim.easing.type = getEasing(currentMode)
    transitionAnim.restart()
  }

  function finishTransition() {
    active = false
    needsOverlay = false
    lastAppliedProgress = -1
    progress = 1.0

    // Lock in final authoritative state
    if (pendingColorsRaw) {
      Color.loadColors(pendingColorsRaw)
    }
    if (pendingShellRaw) {
      Color.loadShell(pendingShellRaw)
    }
    Style.scheduleRefresh()

    if (typeof completionCallback === "function") {
      var cb = completionCallback
      completionCallback = null
      cb()
    }
  }

  // 10. Preview System
  property bool previewing: false
  property string previewOrigColors: ""
  property string previewOrigShell: ""
  property string previewSavedMode: ""

  property Timer previewReturnTimer: Timer {
    id: previewReturnTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (root.previewing) {
        root.startTransition(root.previewOrigColors, root.previewOrigShell, function() {
          root.previewing = false
          root.currentMode = root.previewSavedMode
        })
      }
    }
  }

  function previewTransition(mode) {
    if (active || previewing) return
    var testMode = mode || currentMode
    previewing = true
    previewSavedMode = currentMode
    currentMode = testMode

    // Save active colors
    previewOrigColors = "background = '" + Color.background + "'\nforeground = '" + Color.foreground + "'\naccent = '" + Color.accent + "'\nurgent = '" + Color.urgent + "'\nmuted = '" + Color.muted + "'\n"
    previewOrigShell = ""

    // Create high-contrast test target
    var isDark = luminance(Color.background) < 0.5
    var testColorsRaw = isDark
      ? "mode = 'light'\nbackground = '#eff1f5'\nforeground = '#4c4f69'\naccent = '#1e66f5'\nurgent = '#d20f39'\nmuted = '#acb0be'\n"
      : "mode = 'dark'\nbackground = '#101315'\nforeground = '#cacccc'\naccent = '#88c0d0'\nurgent = '#bf616a'\nmuted = '#707880'\n"

    startTransition(testColorsRaw, "", function() {
      previewReturnTimer.restart()
    })
  }
}
