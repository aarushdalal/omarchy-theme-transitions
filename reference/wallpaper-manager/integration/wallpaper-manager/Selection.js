.pragma library

// Shared file-manager selection rules for visible, ordered items.
function select(keys, current, key, modifiers, anchor, toggle) {
    key = String(key)
    var ctrl = (modifiers & Qt.ControlModifier) !== 0
    var shift = (modifiers & Qt.ShiftModifier) !== 0
    var next = (ctrl || toggle) ? Object.assign({}, current) : {}
    if (shift && !toggle) {
        if (keys.indexOf(anchor) < 0) anchor = key
        var first = keys.indexOf(anchor), last = keys.indexOf(key)
        for (var i = Math.min(first, last); i <= Math.max(first, last); i++)
            if (i >= 0) next[keys[i]] = true
    } else {
        next[key] = (ctrl || toggle) ? !next[key] : true
        anchor = key
    }
    return {selected: next, anchor: anchor}
}
