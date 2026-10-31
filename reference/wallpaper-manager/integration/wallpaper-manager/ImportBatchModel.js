.pragma library
function count(batches) { return batches.reduce(function(n, b) { return n + b.items.length }, 0) }
function add(batches, items, group, options, label) {
    var known = {}
    batches.forEach(function(b) { b.items.forEach(function(i) { known[i.source] = true }) })
    if (!items.length) throw new Error("Select wallpapers for this batch first.")
    items.forEach(function(i) { if (known[i.source]) throw new Error("This source is already queued: " + i.source) })
    var cleanGroup = (group && group !== "Ungrouped") ? group.trim() : ""
    var batch = Object.assign({}, options, {label: label || "Selected files", group: cleanGroup,
        items: items.map(function(i) { return Object.assign({}, i, {group: cleanGroup}) })})
    return batches.concat([batch])
}
function setGroup(batches, index, group) {
    var cleanGroup = (group && group !== "Ungrouped") ? group.trim() : ""
    return batches.map(function(b, i) {
        if (i !== index) return b
        return Object.assign({}, b, {
            group: cleanGroup,
            items: (b.items || []).map(function(item) {
                return Object.assign({}, item, {group: cleanGroup})
            })
        })
    })
}
function matchKnownGroup(name, knownGroups) {
    if (!name || !knownGroups || !knownGroups.length) return ""
    var normalized = name.replace(/[-_]+/g, " ").trim().toLowerCase()
    for (var i = 0; i < knownGroups.length; i++) {
        var g = knownGroups[i]
        if (g && g.replace(/[-_]+/g, " ").trim().toLowerCase() === normalized) {
            return g
        }
    }
    return ""
}
function addFolders(batches, folders, options, knownGroups) {
    var next = batches.slice(), known = {}, added = 0, skipped = 0, messages = []
    next.forEach(function(b) { b.items.forEach(function(i) { known[i.source] = true }) })
    folders.forEach(function(folder) {
        var items = folder.candidates.filter(function(item) {
            if (item.installed || known[item.source]) { skipped++; return false }
            known[item.source] = true
            return true
        })
        var matched = matchKnownGroup(folder.folder.split("/").pop(), knownGroups)
        if (items.length) { next = add(next, items, matched, options, folder.folder); added++ }
        else messages.push(folder.folder + ": no new wallpapers to queue.")
        folder.issues.forEach(function(issue) { messages.push(issue.source + ": " + issue.reason) })
    })
    return {batches: next, added: added, skipped: skipped, messages: messages}
}
