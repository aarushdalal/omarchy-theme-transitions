function nameForPath(path) {
  return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "")
}

function labelForPath(path) {
  var name = nameForPath(path).replace(/-[a-f0-9]{12}-/g, "-").replace(/_/g, "-")
  name = name.replace(/^(.+)-\1$/, "$1").replace(/^we-/, "")
  return name.replace(/[-_]+/g, " ").replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function loadRows(rows) {
  var images = []
  var seen = {}
  var paths = String(rows || "").split("\n")

  for (var i = 0; i < paths.length; i++) {
    var row = paths[i]
    if (!row) continue

    var columns = row.split("\t")
    var path = columns[0]
    if (!path) continue

    if (seen[path]) continue
    seen[path] = true

    var fileName = path.split("/").pop()
    var name = nameForPath(path)
    var label = labelForPath(path)
    var thumb = columns[1] || path

    images.push({
      filePath: path,
      fileName: fileName,
      name: name,
      label: label,
      thumbnailPath: thumb,
      searchLower: (name + " " + label).toLowerCase()
    })
  }

  return images
}

function itemMatches(images, index, filterText) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return false
  var needle = String(filterText || "").toLowerCase().trim()
  if (!needle) return true

  var item = images[index]
  if (!item) return false
  if (item.searchLower) {
    return item.searchLower.indexOf(needle) !== -1
  }
  var path = String(item.filePath || "")
  return nameForPath(path).toLowerCase().indexOf(needle) !== -1
      || labelForPath(path).toLowerCase().indexOf(needle) !== -1
}

function firstMatchingIndex(images, filterText) {
  var values = Array.isArray(images) ? images : []
  var needle = String(filterText || "").toLowerCase().trim()
  for (var i = 0; i < values.length; i++) {
    if (!needle) return i
    var item = values[i]
    if (item && item.searchLower && item.searchLower.indexOf(needle) !== -1) return i
    if (itemMatches(values, i, filterText)) return i
  }

  return -1
}

function filteredPosition(images, index, filterText) {
  if (!filterText) return index
  var needle = String(filterText || "").toLowerCase().trim()
  if (!needle) return index

  var position = 0
  for (var i = 0; i < index; i++) {
    var item = images[i]
    var match = item && item.searchLower ? (item.searchLower.indexOf(needle) !== -1) : itemMatches(images, i, filterText)
    if (match) position++
  }

  return position
}

function selectedFilteredPosition(images, selectedIndex, filterText) {
  if (!filterText) return selectedIndex
  return itemMatches(images, selectedIndex, filterText) ? filteredPosition(images, selectedIndex, filterText) : 0
}

function indexForSelectedImage(images, selectedImage) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].filePath === selectedImage) return i
  }

  return 0
}

function nextSelectedIndexForFilter(images, selectedIndex, filterText) {
  if (itemMatches(images, selectedIndex, filterText)) return selectedIndex
  return firstMatchingIndex(images, filterText)
}

function filteredImages(images, filterText) {
  var rows = []
  var needle = String(filterText || "").toLowerCase().trim()
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    var match = !needle || (item && item.searchLower ? item.searchLower.indexOf(needle) !== -1 : itemMatches(values, i, filterText))
    if (match) {
      rows.push({
        originalIndex: i,
        filePath: item.filePath,
        thumbnailPath: item.thumbnailPath,
        fileName: item.fileName,
        label: item.label,
        name: item.name
      })
    }
  }
  return rows
}

function positions(images, filterText) {
  var result = [], position = 0
  var needle = String(filterText || "").toLowerCase().trim()
  var hasFilter = needle.length > 0
  var len = Array.isArray(images) ? images.length : 0
  for (var i = 0; i < len; i++) {
    var item = images[i]
    var match = !hasFilter || (item && item.searchLower ? item.searchLower.indexOf(needle) !== -1 : itemMatches(images, i, filterText))
    result.push(match ? position++ : -1)
  }
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    nameForPath: nameForPath,
    labelForPath: labelForPath,
    loadRows: loadRows,
    itemMatches: itemMatches,
    firstMatchingIndex: firstMatchingIndex,
    filteredPosition: filteredPosition,
    selectedFilteredPosition: selectedFilteredPosition,
    indexForSelectedImage: indexForSelectedImage,
    nextSelectedIndexForFilter: nextSelectedIndexForFilter,
    filteredImages: filteredImages,
    positions: positions
  }
}
