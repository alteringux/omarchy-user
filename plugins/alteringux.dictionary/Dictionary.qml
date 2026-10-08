import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "../shared"

Item {
  property QtObject _webPalette: Kit.Palette {}
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

  property color background: _webPalette.menuBackground
  property color foreground: _webPalette.menuText
  property color border: _webPalette.menuBorder
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: _webPalette.menuScrim
  property color selectedBackground: _webPalette.menuSelectedBackground
  property color selectedText: _webPalette.menuSelectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(420), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(56), Style.font.title + Style.spacing.controlPaddingY * 4)

  readonly property string keyHint: root.step === "overview"
    ? "Esc: back  ·  F1: help"
    : "↑↓: navigate  ·  Enter: select  ·  Esc: clear/close  ·  F1: help"

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
    // Bug fix: this used to leave overviewStarred untouched, so selecting a
    // new word inherited the previous word's star state until the
    // fire-and-forget trackProcess("lookup") round trip landed and corrected
    // it — a starred word made every word opened right after it flash as
    // starred too. Reset it eagerly with the rest of the overview state.
    root.overviewStarred = false
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

  property string suggestForFilter: ""

  function runSuggest() {
    guard.run("runSuggest", function() {
      if (!root.filterText) {
        root.suggestions = []
        suggestModel.clear()
        return
      }
      root.suggestForFilter = root.filterText
      suggestProcess.command = ["omarchy-dictionary-suggest-summaries", root.filterText, "8"]
      suggestProcess.running = true
    })
  }

  function applySuggestions(list) {
    guard.run("applySuggestions", function() {
      if (root.filterText !== root.suggestForFilter) return
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
    } else {
      root.selectedIndex = (root.selectedIndex + delta + suggestModel.count) % suggestModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
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
        readonly property var shortcutDescriptions: [
          { keys: "F1", description: "Open recovery and keyboard shortcut help", context: "Dictionary" },
          { keys: "Up / Down", description: "Move through word suggestions", context: "Dictionary · search" },
          { keys: "Enter / Return", description: "Open the selected word, or look up the typed query when no suggestion is selected", context: "Dictionary · search" },
          { keys: "Enter / Return / Space", description: "Look up the daily suggested word", context: "Dictionary · daily suggestion" },
          { keys: "Escape", description: "Return to search from a word overview; in search, clear the query or close Dictionary when it is empty", context: "Dictionary" }
        ]

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_F1) {
            shortcutHelp.show()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
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
            // Feature: Enter used to do nothing unless a suggestion row was
            // already highlighted, which stranded a typed word with no
            // matches (or before the debounced suggest call returns). Fall
            // back to looking the typed text up directly.
            if (root.step === "search") {
              if (root.cursorActive) root.activateIndex(root.selectedIndex)
              else if (root.filterText.trim()) root.selectWord(root.filterText.trim())
            }
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

          MarqueeText {
            id: headerTitle
            anchors.left: parent.left
            anchors.right: root.step === "overview" ? starToggle.left : headerHint.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: root.step === "overview" ? ("← " + root.overviewWord) : (root.filterText || "Look up a word…")
            color: root.foreground
            textFont.family: root.fontFamily
            textFont.pixelSize: Style.font.heading
            requestedElide: Text.ElideRight
          }

          Kit.ActionButton {
            id: starToggle
            visible: root.step === "overview"
            anchors.right: headerHint.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            width: Style.spacing.controlHeight
            height: Style.spacing.controlHeight
            text: root.overviewStarred ? "★" : "☆"
            focusable: true
            Accessible.role: Accessible.CheckBox
            Accessible.name: "Star " + root.overviewWord
            Accessible.checked: root.overviewStarred
            foreground: root.foreground
            bordered: false
            onClicked: root.toggleStar()
          }

          Text {
            id: headerHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.keyHint
            color: root.foreground
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

            ScrollBar.vertical: ScrollBar {
              policy: ScrollBar.AsNeeded
              visible: size > 0 && size < 1
              enabled: visible
              interactive: visible
            }
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
              Accessible.role: Accessible.Button
              Accessible.name: word
              Accessible.description: summary
              Accessible.focusable: true
              Accessible.onPressAction: root.selectWord(word)

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.spacing.controlPaddingY
                spacing: Style.space(2)

                MarqueeText {
                  text: word
                  focusableOnOverflow: false
                  color: hasCursor ? root.selectedText : root.foreground
                  textFont.family: root.fontFamily
                  textFont.pixelSize: Style.font.body
                  textFont.bold: true
                  requestedElide: Text.ElideRight
                  width: parent.width
                }
                MarqueeText {
                  text: summary
                  focusableOnOverflow: false
                  color: hasCursor ? root.selectedText : root.foreground
                  textFont.family: root.fontFamily
                  textFont.pixelSize: Style.font.bodySmall
                  requestedElide: Text.ElideRight
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

          // Was a bare centered Text hand-rolling the empty-state look;
          // Kit.EmptyState is the shared styling for "nothing here yet".
          Kit.EmptyState {
            anchors.centerIn: parent
            width: Math.min(parent.width - Style.spacing.panelPadding * 2, Style.space(320))
            visible: suggestModel.count === 0 && root.filterText.length > 0
            text: "No matches for “" + root.filterText + "”"
            hint: "Press Enter to look it up anyway."
            foreground: root.foreground
          }

          // Self-improving pick: a word related to what you've starred/looked
          // up before, suggested by claude and refreshed at most every 12h.
          Rectangle {
            id: dailySuggestionCard
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !root.filterText && !!root.dailySuggestion
            width: parent.width
            height: suggestionContent.implicitHeight + Style.space(8)
            radius: root.cornerRadius
            color: "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: _webPalette.accent
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: "Try word " + (root.dailySuggestion ? root.dailySuggestion.word : "")
            Accessible.description: root.dailySuggestion ? root.dailySuggestion.note || "" : ""
            Accessible.focusable: true
            Accessible.onPressAction: if (root.dailySuggestion) root.selectWord(root.dailySuggestion.word)
            Keys.onReturnPressed: { if (root.dailySuggestion) root.selectWord(root.dailySuggestion.word); event.accepted = true }
            Keys.onEnterPressed: { if (root.dailySuggestion) root.selectWord(root.dailySuggestion.word); event.accepted = true }
            Keys.onSpacePressed: { if (root.dailySuggestion) root.selectWord(root.dailySuggestion.word); event.accepted = true }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { dailySuggestionCard.forceActiveFocus(); root.selectWord(root.dailySuggestion.word) }

              Column {
                id: suggestionContent
                anchors.fill: parent
                anchors.margins: Style.space(4)
                spacing: Style.space(2)

                Text {
                  id: suggestionWord
                  text: "✦ Try: " + (root.dailySuggestion ? root.dailySuggestion.word : "")
                  color: root.foreground
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
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: !!(root.overviewData && root.overviewData.etymology)
              text: "Etymology: " + (root.overviewData ? root.overviewData.etymology : "")
              wrapMode: Text.WordWrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              width: parent.width
              visible: root.overviewLoading
              text: "Loading richer overview…"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }

    Kit.RecoveryHelp {
      id: shortcutHelp
      returnFocusItem: keyCatcher
    }
  }
}
