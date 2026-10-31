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
    var palette = columns[2] ? columns[2].split(",") : []
    var accent = palette[0] || ""
    var bg = palette[1] || ""
    var fg = palette[2] || ""

    images.push({
      filePath: path,
      fileName: fileName,
      name: name,
      label: label,
      thumbnailPath: thumb,
      accent: accent,
      bg: bg,
      fg: fg,
      searchLower: (name + " " + label).toLowerCase()
    })
  }

  return images
}

function itemMatches(images, index, filterText, favoriteList) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return false
  var item = images[index]
  if (!item) return false

  if (Array.isArray(favoriteList)) {
    var slug = item.name || nameForPath(item.filePath)
    var clean = String(slug).replace(/\s*\(\d+\)$/, "").trim()
    var isFav = false
    for (var f = 0; f < favoriteList.length; f++) {
      var fav = favoriteList[f]
      if (fav === slug || fav === clean || fav === item.label || fav === item.filePath) {
        isFav = true
        break
      }
    }
    if (!isFav) return false
  }

  var needle = String(filterText || "").toLowerCase().trim()
  if (!needle) return true

  if (item.searchLower) {
    return item.searchLower.indexOf(needle) !== -1
  }
  var path = String(item.filePath || "")
  return nameForPath(path).toLowerCase().indexOf(needle) !== -1
      || labelForPath(path).toLowerCase().indexOf(needle) !== -1
}

function firstMatchingIndex(images, filterText, favoriteList) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (itemMatches(values, i, filterText, favoriteList)) return i
  }

  return -1
}

function filteredPosition(images, index, filterText, favoriteList) {
  var position = 0
  for (var i = 0; i < index; i++) {
    if (itemMatches(images, i, filterText, favoriteList)) position++
  }

  return position
}

function selectedFilteredPosition(images, selectedIndex, filterText, favoriteList) {
  return itemMatches(images, selectedIndex, filterText, favoriteList) ? filteredPosition(images, selectedIndex, filterText, favoriteList) : 0
}

function indexForSelectedImage(images, selectedImage) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].filePath === selectedImage) return i
  }

  return 0
}

function nextSelectedIndexForFilter(images, selectedIndex, filterText, favoriteList) {
  if (itemMatches(images, selectedIndex, filterText, favoriteList)) return selectedIndex
  return firstMatchingIndex(images, filterText, favoriteList)
}

function filteredImages(images, filterText, favoriteList) {
  var rows = []
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (itemMatches(values, i, filterText, favoriteList)) {
      var item = values[i]
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

function positions(images, filterText, favoriteList) {
  var result = [], position = 0
  var needle = String(filterText || "").toLowerCase().trim()
  var hasFilter = needle.length > 0 || Array.isArray(favoriteList)
  var len = Array.isArray(images) ? images.length : 0
  for (var i = 0; i < len; i++) {
    var match = !hasFilter || itemMatches(images, i, filterText, favoriteList)
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
