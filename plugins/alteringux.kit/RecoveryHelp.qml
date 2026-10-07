import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import "." as Kit
import qs.Commons
import "../shared"
import "RecoveryModel.js" as Model

// Lives in the current panel's window. Reading or selecting a record cannot
// execute it: the catalog contains presentation fields and no dispatch API.
Popup {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  property Item returnFocusItem: null
  property Item previousFocusItem: null
  property bool recoveryOnly: true
  property bool auditMode: false
  property alias localBindings: catalog.localBindings
  property bool pilotAvailable: false
  readonly property var matches: Model.filter(catalog.records, search.text, recoveryOnly)
  readonly property var auditMatches: Model.filterAudit(catalog.auditReport.collisions, search.text)
  parent: returnFocusItem && returnFocusItem.Window.window
    ? returnFocusItem.Window.window.contentItem : null
  width: Math.max(0, Math.min(600, parent ? parent.width - 16 : 600))
  height: Math.max(0, Math.min(520, parent ? parent.height - 16 : 520))
  x: parent ? (parent.width - width) / 2 : 0
  y: parent ? (parent.height - height) / 2 : 0
  padding: Style.space(12)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  palette.window: _webPalette.background
  palette.base: _webPalette.background
  palette.text: _webPalette.foreground
  palette.windowText: _webPalette.foreground
  palette.buttonText: _webPalette.foreground
  palette.button: _webPalette.background
  palette.highlight: _webPalette.accent
  palette.highlightedText: _webPalette.background
  palette.placeholderText: _webPalette.muted

  function show() {
    // A clicked header and F1 share the same owner-provided documentation.
    let owner = returnFocusItem
    localBindings = []
    pilotAvailable = false
    while (owner) {
      if (typeof owner.shortcutDescriptions !== "undefined") {
        localBindings = owner.shortcutDescriptions
        pilotAvailable = owner.recoveryPilot === true && owner.recoveryPilotVerified === true
        break
      }
      owner = owner.parent
    }
    previousFocusItem = returnFocusItem && returnFocusItem.Window.window
      ? returnFocusItem.Window.window.activeFocusItem : null
    recoveryOnly = true
    auditMode = false
    search.text = ""
    open()
  }
  function auditSummaryText() {
    const report = catalog.auditReport
    return report.rawCount + " raw · " + report.describedCount + " described · "
      + report.normalizedCount + " shown · " + report.uniqueChordCount + " unique chords · "
      + report.collisionCount + " collisions · " + report.actionableCount + " actionable · "
      + report.intentionalCount + " intentional · " + report.unknownCount + " unknown · "
      + report.usage.mode + " usage (" + Math.round(report.usage.coverage * 100) + "% coverage)"
  }
  function auditLayerText() {
    return catalog.auditReport.layers.map(function(row) {
      return row.name + ": " + row.usedCount + "/" + row.capacity + " used"
        + (row.unused.length ? " · free " + row.unused.join(", ") : " · full")
    }).join("\n")
  }
  onOpened: { catalog.refresh(); search.forceActiveFocus() }
  onClosed: Qt.callLater(function() {
    const target = root.previousFocusItem || root.returnFocusItem
    if (target && target.visible && target.enabled && target.Window.window
        && target.Window.window.visible) target.forceActiveFocus()
  })
  background: Rectangle {
    Accessible.role: Accessible.Dialog
    Accessible.name: root.auditMode ? "Shortcut audit"
      : root.recoveryOnly ? "Recovery shortcuts" : "All shortcuts"
    color: _webPalette.background
    border.width: 1
    border.color: _webPalette.accent
    radius: Style.cornerRadius
  }
  RecoveryCatalog { id: catalog }
  contentItem: ColumnLayout {
    spacing: Style.space(8)
    Label {
      text: root.auditMode ? "Shortcut audit" : root.recoveryOnly ? "Recovery shortcuts" : "All shortcuts"
      font.pixelSize: Style.font.title
      font.bold: true
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }
    TextField {
      id: search
      Layout.fillWidth: true
      placeholderText: root.auditMode ? "Search conflicts" : "Search descriptions or keys"
      Accessible.name: "Search shortcuts"
      selectByMouse: true
      Keys.onDownPressed: if (list.count) { list.currentIndex = 0; list.forceActiveFocus() }
    }
    Label {
      text: catalog.loading ? "Loading shortcuts…" : catalog.error
      visible: catalog.loading || catalog.error.length > 0
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      Accessible.name: text
    }
    Label {
      visible: root.auditMode && !catalog.loading && !catalog.error
      text: root.auditSummaryText()
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      font.pixelSize: Style.font.caption
    }
    Label {
      visible: root.auditMode && !catalog.loading && !catalog.error
      text: root.auditLayerText()
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      font.pixelSize: Style.font.caption
      color: _webPalette.muted
      Accessible.name: text
    }
    Label {
      visible: root.auditMode && !catalog.loading && !catalog.error
      text: catalog.auditReport.usage.note
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      font.pixelSize: Style.font.caption
      color: _webPalette.muted
    }
    Label {
      visible: !catalog.loading && !catalog.error
        && (root.auditMode ? !root.auditMatches.length : !root.matches.length)
      text: search.text.trim().length ? "No shortcuts match this search."
        : root.auditMode ? "No shortcut collisions found."
        : root.recoveryOnly ? "No reset or restart shortcuts found." : "No described shortcuts found."
      wrapMode: Text.Wrap
      Layout.fillWidth: true
    }
    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      model: root.auditMode ? root.auditMatches : root.matches
      spacing: Style.space(8)
      currentIndex: -1
      keyNavigationEnabled: true
      activeFocusOnTab: count > 0
      Accessible.name: "Shortcut descriptions"
      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        visible: size > 0 && size < 1
        enabled: visible
        interactive: visible
      }
      delegate: Rectangle {
        id: record
        required property var modelData
        required property int index
        width: list.width
        implicitHeight: lines.implicitHeight + Style.space(16)
        color: list.activeFocus && list.currentIndex === index ? _webPalette.accent : "transparent"
        border.color: _webPalette.muted
        border.width: 1
        radius: Style.cornerRadius
        Accessible.role: Accessible.ListItem
        Accessible.selected: list.currentIndex === index
          Accessible.name: modelData.keys + ". " + modelData.description + ". "
          + (root.auditMode ? modelData.classification + ". " : "")
          + modelData.context + (modelData.flags ? ". " + modelData.flags : "")
        Column {
          id: lines
          x: Style.space(8); y: Style.space(8)
          width: Math.max(0, parent.width - Style.space(16))
          spacing: Style.space(4)
          Label {
            width: parent.width
            text: record.modelData.keys
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            font.bold: true
        color: list.activeFocus && list.currentIndex === record.index ? _webPalette.background : _webPalette.foreground
            Accessible.ignored: true
          }
          Label {
            visible: root.auditMode
            width: parent.width
            text: "Classification: " + record.modelData.classification
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.pixelSize: Style.font.caption
            color: list.activeFocus && list.currentIndex === record.index ? _webPalette.background : _webPalette.muted
            Accessible.ignored: true
          }
          Label {
            width: parent.width
            text: record.modelData.description
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        color: list.activeFocus && list.currentIndex === record.index ? _webPalette.background : _webPalette.foreground
            Accessible.ignored: true
          }
          Label {
            width: parent.width
            text: record.modelData.context + (record.modelData.flags ? " · " + record.modelData.flags : "")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            font.pixelSize: Style.font.caption
        color: list.activeFocus && list.currentIndex === record.index ? _webPalette.background : _webPalette.muted
            Accessible.ignored: true
          }
        }
      }
    }
    CheckBox {
      id: suggestionOptIn
      visible: root.pilotAvailable && !root.auditMode
      Layout.fillWidth: true
      text: "Suggest recovery shortcuts"
      checked: TextPreferences.suggestRecoveryShortcuts
      Accessible.description: "Show suggestions after three distinct, unhandled Ctrl/Alt/Super shortcuts within four seconds in Pulse or Timers while panel shortcuts own focus. Commands are never run."
      contentItem: Label {
        text: suggestionOptIn.text
        wrapMode: Text.Wrap
        leftPadding: suggestionOptIn.indicator.width + suggestionOptIn.spacing
        Accessible.ignored: true
      }
      onToggled: {
        TextPreferences.suggestRecoveryShortcuts = checked
        TextPreferences.sync()
      }
    }
    Label {
      visible: root.pilotAvailable && !root.auditMode
      text: "Suggestions apply after three distinct, unhandled Ctrl/Alt/Super shortcuts within four seconds in Pulse or Timers while panel shortcuts have focus. Editing stays separate."
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      font.pixelSize: Style.font.caption
      color: _webPalette.muted
    }
    Flow {
      Layout.fillWidth: true
      spacing: Style.space(8)
      Button {
        text: "Clear search"
        visible: search.text.length > 0
        onClicked: { search.text = ""; search.forceActiveFocus() }
      }
      Button {
        text: root.auditMode ? "All shortcuts" : "Audit"
        Accessible.name: text
        onClicked: {
          root.auditMode = !root.auditMode
          root.recoveryOnly = false
          search.text = ""
          search.forceActiveFocus()
        }
      }
      Button {
        visible: !root.auditMode
        text: root.recoveryOnly ? "All shortcuts" : "Recovery only"
        onClicked: { root.recoveryOnly = !root.recoveryOnly; search.text = ""; search.forceActiveFocus() }
      }
      Button { text: "Retry"; visible: !!catalog.error; onClicked: catalog.refresh() }
      Button { text: "Close"; onClicked: root.close() }
    }
  }
}
