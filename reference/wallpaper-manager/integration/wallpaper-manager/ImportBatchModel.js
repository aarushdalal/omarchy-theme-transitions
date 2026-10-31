.pragma library
function count(batches) { return batches.reduce(function(n, b) { return n + b.items.length }, 0) }
function add(batches, items, group, options, label) {
    var known = {}
    batches.forEach(function(b) { b.items.forEach(function(i) { known[i.source] = true }) })
    if (!items.length) throw new Error("Select wallpapers for this batch first.")
    items.forEach(function(i) { if (known[i.source]) throw new Error("This source is already queued: " + i.source) })
    var batch = Object.assign({}, options, {label: label || "Selected files", group: group,
        items: items.map(function(i) { return Object.assign({}, i, {group: group}) })})
    return batches.concat([batch])
}
function setGroup(batches, index, group) {
    return batches.map(function(b, i) { return i === index ? Object.assign({}, b, {group: group}) : b })
}
function addFolders(batches, folders, options) {
    var next = batches.slice(), known = {}, added = 0, skipped = 0, messages = []
    next.forEach(function(b) { b.items.forEach(function(i) { known[i.source] = true }) })
    folders.forEach(function(folder) {
        var items = folder.candidates.filter(function(item) {
            if (item.installed || known[item.source]) { skipped++; return false }
            known[item.source] = true
            return true
        })
        if (items.length) { next = add(next, items, "", options, folder.folder); added++ }
        else messages.push(folder.folder + ": no new wallpapers to queue.")
        folder.issues.forEach(function(issue) { messages.push(issue.source + ": " + issue.reason) })
    })
    return {batches: next, added: added, skipped: skipped, messages: messages}
}
