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

    var fileName = path.split("/").pop()
    if (seen[path]) continue
    seen[path] = true

    images.push({
      filePath: path,
      fileName: fileName,
      thumbnailPath: columns[1] || path
    })
  }

  return images
}

function itemMatches(images, index, filterText) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return false
  var needle = String(filterText || "").toLowerCase()
  if (!needle) return true

  var path = String(images[index].filePath || "")
  return nameForPath(path).toLowerCase().indexOf(needle) !== -1
      || labelForPath(path).toLowerCase().indexOf(needle) !== -1
}

function firstMatchingIndex(images, filterText) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (itemMatches(values, i, filterText)) return i
  }

  return -1
}

function filteredPosition(images, index, filterText) {
  if (!filterText) return index

  var position = 0
  for (var i = 0; i < index; i++) {
    if (itemMatches(images, i, filterText)) position++
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
    nextSelectedIndexForFilter: nextSelectedIndexForFilter
  }
}

function filteredImages(images, filterText) {
  var rows = []
  for (var i = 0; i < images.length; i++) {
    if (itemMatches(images, i, filterText)) {
      rows.push({ originalIndex: i, filePath: images[i].filePath,
                  thumbnailPath: images[i].thumbnailPath, fileName: images[i].fileName })
    }
  }
  return rows
}
if (typeof module !== "undefined") module.exports.filteredImages = filteredImages

function positions(images, filterText) {
  var result = [], position = 0
  for (var i = 0; i < images.length; i++) result.push(itemMatches(images, i, filterText) ? position++ : -1)
  return result
}
if (typeof module !== "undefined") module.exports.positions = positions
