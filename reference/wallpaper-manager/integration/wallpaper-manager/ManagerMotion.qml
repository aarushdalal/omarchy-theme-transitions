import QtQuick
import qs.Commons as ShellCommons

// Reuse the shell policy; non-shell test hosts safely render without motion.
QtObject {
    readonly property var policy: typeof ShellCommons.Motion === "undefined" ? null : ShellCommons.Motion
    readonly property bool reducedMotion: !policy || policy.reducedMotion
    readonly property int micro: reducedMotion ? 0 : Math.min(140, policy.micro)
    readonly property int standard: reducedMotion ? 0 : Math.min(220, policy.standard)
    readonly property int easing: reducedMotion ? Easing.Linear : policy.easeMicro
}
