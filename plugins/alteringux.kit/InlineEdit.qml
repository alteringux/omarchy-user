import QtQuick
import "." as Kit
import qs.Commons
import qs.Ui

// Edit-in-place for a user-authored card label / panel title. Renders `text`
// as a plain wrapped Text; a click swaps in a TextField pre-filled and fully
// selected. Committing — Enter, or focus leaving the field for any reason —
// fires accepted(value) once with the trimmed text, but only if it actually
// changed and is non-empty. Esc cancels back to the original with no signal.
//
// The host panel must OR `editing` into its PanelKeyCatcher.blocked (via an
// inlineEditors count) so keystrokes — Esc especially — reach the field.
// Shared via alteringux.kit; see docs/adr/0003. Used as `Kit.InlineEdit { }`.
Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property string text: ""
  property color foreground: _webPalette.foreground
  property real pixelSize: Style.font.body
  property bool bold: false
  property string placeholderText: ""
  property bool editable: true

  readonly property bool editing: priv.editing

  signal accepted(string value)

  implicitHeight: priv.editing ? field.implicitHeight : label.implicitHeight

  QtObject {
    id: priv
    property bool editing: false
    // Guards commit()/cancel() so the focus-out that each triggers can't
    // fire a second time.
    property bool settled: false
  }

  function beginEdit() {
    if (!root.editable || priv.editing) return
    priv.settled = false
    field.text = root.text
    priv.editing = true
    field.forceActiveFocus()
    Qt.callLater(field.selectAll)
  }

  function commit() {
    if (priv.settled) return
    priv.settled = true
    priv.editing = false
    var v = field.text.trim()
    if (v.length > 0 && v !== root.text) root.accepted(v)
  }

  function cancel() {
    if (priv.settled) return
    priv.settled = true
    priv.editing = false
  }

  Text {
    id: label
    visible: !priv.editing
    width: root.width
    text: root.text
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: root.pixelSize
    font.bold: root.bold
    wrapMode: Text.WordWrap

    MouseArea {
      anchors.fill: parent
      enabled: root.editable
      cursorShape: Qt.IBeamCursor
      onClicked: root.beginEdit()
    }
  }

  TextField {
    id: field
    visible: priv.editing
    width: root.width
    foreground: root.foreground
    placeholderText: root.placeholderText
    font.pixelSize: root.pixelSize
    onAccepted: root.commit()
    onActiveFocusChanged: if (!field.activeFocus && priv.editing) root.commit()
    Keys.onEscapePressed: root.cancel()
  }
}
