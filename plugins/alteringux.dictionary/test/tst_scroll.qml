import QtQuick
import QtTest
import "plugins/alteringux.dictionary" as Dictionary

TestCase {
  name: "DictionaryScroll"
  when: true

  Dictionary.Dictionary { id: dictionary; opened: true }
  property var list
  property var overview

  function scrollables(item) {
    var result = []
    if (item.contentY !== undefined) result.push(item)
    if (item.children)
      for (var child of item.children) result = result.concat(scrollables(child))
    return result
  }

  function initTestCase() {
    var panel = dictionary.resources.find(function(item) { return item.contentItem !== undefined })
    verify(panel !== undefined, "dictionary panel must exist")
    var views = scrollables(panel.contentItem)
    compare(views.length, 2)
    list = views[0]
    overview = views[1]
    wait(100)
  }

  function init() {
    dictionary.step = "search"
    dictionary.selectedIndex = 0
    dictionary.applySuggestions(Array.from({length: 8}, function(_, i) {
      return {word: "word" + i, summary: "A definition"}
    }))
    list.contentY = 0
    // Keep physical pointer hover out of keyboard selection assertions.
    mouseMove(list, -10, -10)
    wait(100)
  }

  function selectionVisible() {
    var row = list.itemAtIndex(dictionary.selectedIndex)
    return row && row.y >= list.contentY - 1
      && row.y + row.height <= list.contentY + list.height + 1
  }

  function cleanup() {
    console.log((qtest_results.failed ? "FAIL: " : "PASS: ") + qtest_results.functionName)
  }

  function test_keyboardRevealsSelectedWord() {
    verify(list.contentHeight > list.height, "fixture must overflow")
    for (var i = 0; i < 7; i++) keyClick(Qt.Key_Down)
    compare(dictionary.selectedIndex, 7)
    tryVerify(selectionVisible, 1000, "Down must scroll the selected word into view")
    keyClick(Qt.Key_Down)
    compare(dictionary.selectedIndex, 0)
    tryVerify(selectionVisible, 1000, "wrapping to the first word must scroll up")
    keyClick(Qt.Key_Up)
    compare(dictionary.selectedIndex, 7)
    tryVerify(selectionVisible, 1000, "wrapping to the last word must scroll down")
    dictionary.cursorActive = false
    keyClick(Qt.Key_Down)
    compare(dictionary.selectedIndex, 0)
    tryVerify(selectionVisible, 1000, "initial navigation must reveal the selected word")
  }

  function test_mouseWheelBothViews() {
    mouseMove(list, list.width / 2, list.height / 2)
    mouseWheel(list, list.width / 2, list.height / 2, 0, -120)
    tryVerify(function() { return list.contentY > 0 }, 1000)
    mouseWheel(list, list.width / 2, list.height / 2, 0, 120)
    tryCompare(list, "contentY", 0, 1000)

    dictionary.step = "overview"
    dictionary.overviewSummary = "A long definition. ".repeat(200)
    wait(100)
    overview.contentY = 0
    verify(overview.contentHeight > overview.height, "definition fixture must overflow")
    for (var i = 0; i < 4; i++) {
      var before = overview.contentY
      mouseWheel(overview, overview.width / 2, overview.height / 2, 0, -120)
      tryVerify(function() { return overview.contentY > before }, 1000)
    }
    var bottom = overview.contentY
    mouseWheel(overview, overview.width / 2, overview.height / 2, 0, 120)
    tryVerify(function() { return overview.contentY < bottom }, 1000)
  }

  function cleanupTestCase() {
    console.log("DICTIONARY_SCROLL_RESULT: " + qtest_results.failCount + " failures")
    dictionary.close()
  }
}
