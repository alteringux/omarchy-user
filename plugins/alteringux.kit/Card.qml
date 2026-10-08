import QtQuick
import "." as Kit
import qs.Commons
import "../shared"

// Kit.Card — the translucent panel card every alteringux.* overlay hand-rolled
// as `Rectangle { radius; color: Util.alpha(fg,0.05); border: 1px …0.14 }`.
// Adds an optional coloured left spine keyed to a semantic `tone` and an
// optional UPPERCASE accent title.
//
// Content is an explicit `body: Item` this reparents + positions — NOT a
// default-property slot (that collapsed height inside Repeater delegates; see
// docs/adr/0003). Point `body` at your content Column and size it to
// `bodyWidth`:
//
//   Kit.Card {
//     id: card
//     width: list.width
//     title: "Top stories"; tone: "accent"
//     body: col
//     Column { id: col; width: card.bodyWidth; spacing: Style.space(6); /* rows */ }
//   }
//
// `tone`: "neutral" (default — no spine) | "accent" | "positive" | "negative"
// | "warning". `spine` defaults to (tone !== "neutral"), so a plain card is
// quiet and a status card carries colour. Bind `tone` to the card's state
// (running long, up/down, connected) so the spine is signal, not decoration.
Rectangle {
  property QtObject _webPalette: Kit.Palette {}
  id: card

  property string title: ""
  property string tone: "neutral"
  property bool spine: tone !== "neutral"
  property Item body: null
  property color foreground: _webPalette.contrastColorFor(_webPalette.foreground, card.color)
  property real pad: Style.space(12)

  readonly property real spineWidth: Style.space(3)
  readonly property real bodyWidth: Math.max(0, width - pad * 2 - (spine ? spineWidth : 0))

  radius: Style.cornerRadius
  clip: true
  color: _webPalette.cardBg
  border.width: 1
  border.color: _webPalette.cardBorder

  implicitWidth: (body ? body.implicitWidth : 0) + pad * 2 + (spine ? spineWidth : 0)
  implicitHeight: (titleLabel.visible ? titleLabel.implicitHeight + pad : 0)
                  + (body ? body.implicitHeight : 0) + pad * 2

  Rectangle {
    visible: card.spine
    width: card.spineWidth
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
    color: _webPalette.toneColor(card.tone, card.color, 3, _webPalette.background)
  }

  MarqueeText {
    id: titleLabel
    visible: card.title.length > 0
    x: card.pad + (card.spine ? card.spineWidth : 0)
    y: card.pad
    width: card.bodyWidth
    text: card.title.toUpperCase()
    color: _webPalette.contrastColorFor(_webPalette.accent, card.color)
    textFont.family: Style.font.family
    textFont.pixelSize: Style.font.caption
    textFont.bold: true
    textFont.letterSpacing: 0.5
    requestedElide: Text.ElideRight
  }

  // Reparent + position the caller's content. Bindings so it tracks resize and
  // the spine toggling.
  onBodyChanged: {
    if (!body)
      return
    body.parent = card
    body.x = Qt.binding(function () { return card.pad + (card.spine ? card.spineWidth : 0) })
    body.y = Qt.binding(function () { return card.pad + (titleLabel.visible ? titleLabel.implicitHeight + card.pad : 0) })
    body.width = Qt.binding(function () { return card.bodyWidth })
  }
}
