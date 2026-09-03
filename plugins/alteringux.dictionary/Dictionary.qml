import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string step: "search" // "search" | "overview"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var suggestions: []

  // Overview state for the selected word.
  property string overviewWord: ""
  property string overviewSummary: ""
  property string overviewRaw: ""
  property bool overviewLoading: false
  property var overviewData: null // parsed claude JSON once it lands
  property bool overviewStarred: false

  // Self-improving suggestion: learns from starred/frequent words over time.
  property var dailySuggestion: null

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(420), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(56), Style.font.title + Style.spacing.controlPaddingY * 4)

  readonly property string keyHint: root.step === "overview"
    ? "Esc: back"
    : "↑↓: navigate  ·  Enter: select  ·  Esc: clear/close"

  readonly property var guard: Kit.BugGuard.create("alteringux.dictionary", function(argv) { Quickshell.execDetached(argv) })

  function open(payloadJson) {
    guard.run("open", function() {
      var payload = ({})
      try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

      root.opened = true
      root.step = "search"
      root.selectedIndex = 0
      root.cursorActive = false
      root.suggestions = []
      root.resetOverview()

      var word = (payload.word || "").toString().trim()
      root.setFilter(word)

      suggestDailyProcess.command = ["omarchy-dictionary-suggest-daily", "refresh"]
      suggestDailyProcess.running = true

      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "alteringux.dictionary")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function resetOverview() {
    root.overviewWord = ""
    root.overviewSummary = ""
    root.overviewRaw = ""
    root.overviewLoading = false
    root.overviewData = null
  }

  function backToSearch() {
    root.step = "search"
    root.resetOverview()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = false
    debounceTimer.restart()
  }

  function runSuggest() {
    guard.run("runSuggest", function() {
      if (!root.filterText) {
        root.suggestions = []
        suggestModel.clear()
        return
      }
      suggestProcess.command = ["omarchy-dictionary-suggest-summaries", root.filterText, "8"]
      suggestProcess.running = true
    })
  }

  function applySuggestions(list) {
    guard.run("applySuggestions", function() {
      root.suggestions = list
      suggestModel.clear()
      for (var i = 0; i < list.length; i++) {
        suggestModel.append({ word: list[i].word, summary: list[i].summary })
      }
      if (suggestModel.count === 0) root.selectedIndex = 0
      else if (root.selectedIndex >= suggestModel.count) root.selectedIndex = suggestModel.count - 1
      root.cursorActive = suggestModel.count > 0
    })
  }

  function moveSelection(delta) {
    if (suggestModel.count === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? suggestModel.count - 1 : 0
      return
    }
    root.selectedIndex = (root.selectedIndex + delta + suggestModel.count) % suggestModel.count
  }

  function activateIndex(index) {
    if (index < 0 || index >= suggestModel.count) return
    var row = suggestModel.get(index)
    root.selectWord(row.word)
  }

  function selectWord(word) {
    guard.run("selectWord", function() {
      if (!word) return
      root.step = "overview"
      root.resetOverview()
      root.overviewWord = word
      root.overviewLoading = true

      // Local lookup first (near-instant): shows a definition right away and
      // hands the LLM call real GCIDE context instead of an empty hint.
      lookupProcess.forWord = word
      lookupProcess.command = ["omarchy-dictionary-lookup", word]
      lookupProcess.running = true

      // Fire-and-forget usage signal: feeds the self-improving suggestion.
      trackProcess.command = ["omarchy-dictionary-track", "lookup", word]
      trackProcess.running = true

      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    })
  }

  function toggleStar() {
    guard.run("toggleStar", function() {
      if (!root.overviewWord) return
      root.overviewStarred = !root.overviewStarred
      starProcess.command = ["omarchy-dictionary-track", root.overviewStarred ? "star" : "unstar", root.overviewWord]
      starProcess.running = true
    })
  }

  function applyLookup(word, data) {
    guard.run("applyLookup", function() {
      if (word !== root.overviewWord) return // stale: user moved on to another word
      if (data && data.found) {
        root.overviewSummary = data.summary || ""
        root.overviewRaw = data.raw || ""
      }
      overviewProcess.forWord = word
      overviewProcess.command = ["omarchy-dictionary-overview", word, root.overviewSummary]
      overviewProcess.running = true
    })
  }

  function applyOverview(word, data) {
    guard.run("applyOverview", function() {
      if (word !== root.overviewWord) return // stale: user moved on to another word
      root.overviewLoading = false
      if (data && !data.error) root.overviewData = data
    })
  }

  Timer {
    id: debounceTimer
    interval: 120
    repeat: false
    onTriggered: root.runSuggest()
  }

  ListModel { id: suggestModel }

  Process {
    id: suggestProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "[]")
          root.applySuggestions(Array.isArray(data) ? data : [])
        } catch (e) {
          root.applySuggestions([])
        }
      }
    }
  }

  Process {
    id: lookupProcess
    running: false
    property string forWord: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var w = lookupProcess.forWord
        try { root.applyLookup(w, JSON.parse(text || "{}")) }
        catch (e) { root.applyLookup(w, null) }
      }
    }
  }

  Process {
    id: trackProcess
    running: false
    property string forWord: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          if (data.word === root.overviewWord) root.overviewStarred = !!data.starred
        } catch (e) {}
      }
    }
  }

  Process {
    id: starProcess
    running: false
  }

  Process {
    id: suggestDailyProcess
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text || "{}")
          root.dailySuggestion = (data && data.word) ? data : null
        } catch (e) {
          root.dailySuggestion = null
        }
      }
    }
  }

  Process {
    id: overviewProcess
    running: false
    property string forWord: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.applyOverview(overviewProcess.forWord, JSON.parse(text || "{}")) }
        catch (e) { root.applyOverview(overviewProcess.forWord, null) }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.applyOverview(overviewProcess.forWord, null)
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dictionary"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.step === "overview") root.backToSearch()
            else if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (root.step === "search" && Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (root.step === "search" && event.key === Qt.Key_Up) {
            root.moveSelection(-1)
            event.accepted = true
          } else if (root.step === "search" && event.key === Qt.Key_Down) {
            root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.step === "search" && root.cursorActive) root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (root.step === "search" && event.text && event.text.length === 1 &&
                     event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            id: headerTitle
            anchors.left: parent.left
            anchors.right: root.step === "overview" ? starToggle.left : headerHint.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.step === "overview" ? ("← " + root.overviewWord) : (root.filterText || "Look up a word…")
            color: root.foreground
            opacity: (root.step === "search" && !root.filterText) ? 0.58 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: starToggle
            visible: root.step === "overview"
            anchors.right: headerHint.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.overviewStarred ? "★" : "☆"
            color: root.foreground
            opacity: root.overviewStarred ? 1 : 0.5
            font.pixelSize: Style.font.heading

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.spacing.sm
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleStar()
            }
          }

          Text {
            id: headerHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.keyHint
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Search step: suggestion list.
        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          visible: root.step === "search"

          ListView {
            id: resultList
            anchors.fill: parent
            model: suggestModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Kit.WheelBoost { flick: resultList }

            delegate: Rectangle {
              required property int index
              required property string word
              required property string summary

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.spacing.controlPaddingY
                spacing: Style.space(2)

                Text {
                  text: word
                  color: hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }
                Text {
                  text: summary
                  color: hasCursor ? root.selectedText : root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: root.selectWord(word)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: suggestModel.count === 0 && root.filterText.length > 0
            text: "No matches for “" + root.filterText + "”"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // Self-improving pick: a word related to what you've starred/looked
          // up before, suggested by claude and refreshed at most every 12h.
          Column {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !root.filterText && !!root.dailySuggestion
            spacing: Style.space(2)

            MouseArea {
              width: parent.width
              height: suggestionWord.height + suggestionNote.height + Style.space(2)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectWord(root.dailySuggestion.word)

              Column {
                anchors.fill: parent
                spacing: Style.space(2)

                Text {
                  id: suggestionWord
                  text: "✦ Try: " + (root.dailySuggestion ? root.dailySuggestion.word : "")
                  color: root.foreground
                  opacity: 0.75
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  id: suggestionNote
                  width: parent.width
                  text: root.dailySuggestion ? root.dailySuggestion.note || "" : ""
                  wrapMode: Text.WordWrap
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }

        // Overview step: full word breakdown, progressive local -> LLM.
        Kit.PanelScroll {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing
          visible: root.step === "overview"
          contentHeight: overviewColumn.height

          Column {
            id: overviewColumn
            width: parent.width
            spacing: Style.spacing.md

            Text {
              width: parent.width
              visible: !!(root.overviewData && root.overviewData.pronunciation)
              text: (root.overviewData ? root.overviewData.pronunciation : "") +
                    (root.overviewData && root.overviewData.part_of_speech ? "  ·  " + root.overviewData.part_of_speech : "")
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: !root.overviewData && !!root.overviewSummary
              text: root.overviewSummary
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.overviewData ? root.overviewData.definitions || [] : []
              delegate: Text {
                width: overviewColumn.width
                text: (index + 1) + ". " + modelData
                wrapMode: Text.WordWrap
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Text {
              width: parent.width
              visible: !!(root.overviewData && root.overviewData.examples && root.overviewData.examples.length)
              text: "Examples"
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Repeater {
              model: root.overviewData ? root.overviewData.examples || [] : []
              delegate: Text {
                width: overviewColumn.width
                text: "“" + modelData + "”"
                wrapMode: Text.WordWrap
                color: root.foreground
                opacity: 0.85
                font.family: root.fontFamily
                font.italic: true
                font.pixelSize: Style.font.bodySmall
              }
            }

            Text {
              width: parent.width
              visible: !!(root.overviewData && root.overviewData.synonyms && root.overviewData.synonyms.length)
              text: "Synonyms: " + (root.overviewData ? (root.overviewData.synonyms || []).join(", ") : "")
              wrapMode: Text.WordWrap
              color: root.foreground
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: !!(root.overviewData && root.overviewData.etymology)
              text: "Etymology: " + (root.overviewData ? root.overviewData.etymology : "")
              wrapMode: Text.WordWrap
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: root.overviewLoading
              text: "Loading richer overview…"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
