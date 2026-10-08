import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import "../alteringux.kit" as Kit

// A stationary, selectable reader. Normal panels use their existing overlay;
// a bar/toast window is too small to contain a reader, so explicit activation
// requests Qt's popup window. Hover never opens or resizes a reading surface.
Popup {
  id: root
  property QtObject _webPalette: Kit.Palette {}
  palette.window: _webPalette.popupBackground
  palette.base: _webPalette.popupBackground
  palette.windowText: _webPalette.popupText
  palette.text: _webPalette.popupText
  palette.button: _webPalette.popupBackground
  palette.buttonText: _webPalette.popupText
  palette.mid: _webPalette.popupBorder
  palette.highlight: _webPalette.menuSelectedBackground
  palette.highlightedText: _webPalette.contrastColorFor(
    _webPalette.menuSelectedText, _webPalette.menuSelectedBackground, 4.5, _webPalette.popupBackground)
  property string sourceText: ""
  property string title: "Complete text"
  property font sourceFont
  property Item returnFocusItem: null
  // Fullscreen passive surfaces can still have a narrow input mask. Their
  // callers need a reader window even though their content item is large.
  property bool forceSeparateWindow: false
  readonly property alias reader: readerArea
  readonly property bool separateWindow: forceSeparateWindow
    || (parent && (parent.width < 320 || parent.height < 240))
  readonly property real screenWidth: returnFocusItem && returnFocusItem.Window.window
    && returnFocusItem.Window.window.screen ? returnFocusItem.Window.window.screen.width : 560
  readonly property real screenHeight: returnFocusItem && returnFocusItem.Window.window
    && returnFocusItem.Window.window.screen ? returnFocusItem.Window.window.screen.height : 420

  parent: returnFocusItem && returnFocusItem.Window.window
    ? returnFocusItem.Window.window.contentItem : null
  popupType: separateWindow ? Popup.Window : Popup.Item
  width: Math.max(0, Math.min(560, separateWindow ? screenWidth - 24 : parent ? parent.width - 24 : 560))
  height: Math.max(0, Math.min(420, separateWindow ? screenHeight - 24 : parent ? parent.height - 24 : 420))
  x: parent ? Math.max(0, (parent.width - width) / 2) : 0
  y: parent ? separateWindow && !forceSeparateWindow
    ? parent.height : (parent.height - height) / 2 : 0
  padding: 12
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

  onOpened: readerArea.forceActiveFocus()
  onClosed: Qt.callLater(function() {
    const target = root.returnFocusItem
    if (target && target.visible && target.enabled && target.Window.window
        && target.Window.window.visible) target.forceActiveFocus()
  })

  background: Rectangle {
    color: root._webPalette.popupBackground
    border.color: root._webPalette.popupBorder
    border.width: 1
    radius: 8
  }

  contentItem: ColumnLayout {
    Accessible.name: root.title
    Accessible.role: Accessible.Dialog
    spacing: 8
    Label {
      text: root.title
      color: root._webPalette.popupText
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      font.family: root.sourceFont.family
      font.pixelSize: Math.max(18, root.sourceFont.pixelSize)
      font.bold: true
    }
    ScrollView {
      id: viewport
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: availableWidth
      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        visible: size > 0 && size < 1
        enabled: visible
        interactive: visible
      }
      TextArea {
        id: readerArea
        objectName: "plugin-complete-text"
        text: root.sourceText
        font: root.sourceFont
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        readOnly: true
        color: root._webPalette.popupText
        selectionColor: root.palette.highlight
        selectedTextColor: root.palette.highlightedText
        selectByMouse: true
        Accessible.name: "Complete text"
        Accessible.description: "Read-only text. Select and copy with the usual editing shortcuts."
        Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
      }
    }
    CheckBox {
      id: motionToggle
      text: "Animate truncated text"
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      font: root.sourceFont
      contentItem: Label {
        text: motionToggle.text
        font: motionToggle.font
        color: root._webPalette.popupText
        leftPadding: motionToggle.indicator.width + motionToggle.spacing
        wrapMode: Text.Wrap
        verticalAlignment: Text.AlignVCenter
        Accessible.ignored: true
      }
      checked: TextPreferences.animateTruncatedText
      onToggled: {
        TextPreferences.animateTruncatedText = checked
        TextPreferences.sync()
      }
    }
    RowLayout {
      Layout.fillWidth: true
      Label {
        text: "Select text to copy · Esc: return"
        font: root.sourceFont
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }
      Button {
        text: "Close"
        Accessible.name: "Close complete text"
        font: root.sourceFont
        onClicked: root.close()
      }
    }
  }
}
