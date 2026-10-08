import QtQuick
import QtQuick.Window
import QtQuick.Controls

// Common text treatment for labels clipped to fit a plugin layout. The
// caller's wrapping and elision stay in place until the text is hovered.
Item {
  id: root

  property alias text: overflowProbe.text
  property alias color: label.color
  property alias horizontalAlignment: label.horizontalAlignment
  property alias verticalAlignment: label.verticalAlignment
  property alias leftPadding: label.leftPadding
  property alias rightPadding: label.rightPadding
  property alias bottomPadding: label.bottomPadding
  property alias topPadding: label.topPadding
  property font textFont
  property int requestedWrapMode: Text.NoWrap
  property int requestedMaximumLineCount: -1
  property int requestedElide: Text.ElideRight
  property int requestedTextFormat: Text.PlainText
  property bool active: false
  property bool focusableOnOverflow: true
  property bool motionEnabled: TextPreferences.animateTruncatedText
  property string detailsTitle: "Complete text"
  property bool separateDetailsWindow: false
  readonly property bool detailsVisible: details.opened
  readonly property alias detailsView: details
  readonly property string readableText: requestedTextFormat === Text.PlainText
    ? text : semanticText.getText(0, semanticText.length).replace(/[\u2028\u2029]/g, "\n")
  readonly property real scrollSpeed: 120
  // A moving label has one horizontal track. Turn hard line breaks and
  // block boundaries into spaces there so line clamping cannot hide content;
  // the source and resting label retain their original formatting.
  readonly property string scrollText: {
    var value = root.text.replace(/[\r\n]+/g, " ")
    if (root.requestedTextFormat === Text.StyledText) {
      value = value.replace(/<br\s*\/?>/gi, " ")
        .replace(/<\/?(?:p|div|li|ul|ol|blockquote|h[1-6])\b[^>]*>/gi, " ")
    }
    return value
  }
  readonly property real renderedTextWidth: label.contentWidth + label.leftPadding + label.rightPadding
  readonly property int scrollDuration: Math.max(700, Math.round(Math.max(0, renderedTextWidth - width) * 1000 / scrollSpeed))
  readonly property bool hasOverflow: overflowProbe.truncated ||
    overflowProbe.contentWidth + leftPadding + rightPadding > root.width + 0.5 ||
    overflowProbe.contentHeight + topPadding + bottomPadding > root.height + 0.5
  readonly property bool scrolling: motionEnabled && visible && enabled
    && root.Window.window && root.Window.window.visible
    && !details.opened && hasOverflow && (active || hoverTracker.hovered)

  implicitWidth: overflowProbe.implicitWidth
  implicitHeight: overflowProbe.implicitHeight
  clip: true
  // Qt keeps an active item's tab eligibility until focus is released. Data
  // updates can make a focused label fit, so release it before removing the
  // details affordance from the tab order.
  activeFocusOnTab: false
  onHasOverflowChanged: {
    if ((!hasOverflow || !focusableOnOverflow) && activeFocus) focus = false
    activeFocusOnTab = focusableOnOverflow && hasOverflow
  }
  onFocusableOnOverflowChanged: {
    if (!focusableOnOverflow && activeFocus) focus = false
    activeFocusOnTab = focusableOnOverflow && hasOverflow
  }
  Component.onCompleted: activeFocusOnTab = focusableOnOverflow && hasOverflow
  Accessible.role: hasOverflow ? Accessible.Button : Accessible.StaticText
  Accessible.name: readableText
  Accessible.description: hasOverflow
    ? "Read complete text. Press Enter or F2 for a stationary, selectable view and text motion settings." : ""
  Accessible.onPressAction: if (hasOverflow) openDetails()

  function openDetails() { if (visible && enabled) details.open() }
  function closeDetails() { details.close() }
  Keys.onPressed: function(event) {
    if (hasOverflow && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space || event.key === Qt.Key_F2)) {
      openDetails()
      event.accepted = true
    }
  }

  // Keep layout and overflow decisions tied to the resting presentation.
  // The animated label changes wrap mode and width while scrolling; measuring
  // it directly made hover alter its own row height and could underestimate
  // StyledText because stripped markup does not preserve rendered font runs.
  Text {
    id: overflowProbe
    width: root.width
    height: root.height
    textFormat: root.requestedTextFormat
    font: root.textFont
    leftPadding: root.leftPadding
    rightPadding: root.rightPadding
    topPadding: root.topPadding
    bottomPadding: root.bottomPadding
    wrapMode: root.requestedWrapMode
    maximumLineCount: root.requestedMaximumLineCount
    elide: root.requestedElide
    visible: false
    Accessible.ignored: true
  }

  Text {
    id: label
    width: root.scrolling ? Math.max(root.width, root.renderedTextWidth) : root.width
    height: root.height
    text: root.scrolling ? root.scrollText : root.text
    textFormat: root.requestedTextFormat
    font: root.textFont
    wrapMode: root.scrolling ? Text.NoWrap : root.requestedWrapMode
    maximumLineCount: root.scrolling ? 1 : root.requestedMaximumLineCount
    elide: root.scrolling ? Text.ElideNone : root.requestedElide
    Accessible.ignored: true
  }

  // Qt's rich-text parser supplies decoded semantic text, including explicit
  // paragraph/line boundaries; markup and rendering helpers stay out of AT.
  TextEdit {
    id: semanticText
    visible: false
    text: root.text
    textFormat: root.requestedTextFormat === Text.PlainText ? TextEdit.PlainText : TextEdit.RichText
    readOnly: true
    Accessible.ignored: true
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.color: root.color
    border.width: 2
    radius: 2
    visible: root.activeFocus && root.hasOverflow
    Accessible.ignored: true
  }

  ToolTip.visible: activeFocus && hasOverflow && !details.opened
  ToolTip.text: "Enter: read complete text · F2: text options"

  FullTextView {
    id: details
    sourceText: root.readableText
    sourceFont: root.textFont
    title: root.detailsTitle
    forceSeparateWindow: root.separateDetailsWindow
    returnFocusItem: root.hasOverflow ? root : root.parent
  }

  HoverHandler { id: hoverTracker }

  SequentialAnimation {
    id: scroll
    running: root.scrolling && root.renderedTextWidth > root.width + 0.5
    loops: Animation.Infinite
    PauseAnimation { duration: 450 }
    NumberAnimation {
      target: label
      property: "x"
      to: Math.min(0, root.width - root.renderedTextWidth)
      duration: root.scrollDuration
      easing.type: Easing.InOutSine
    }
    PauseAnimation { duration: 450 }
    NumberAnimation {
      target: label
      property: "x"
      to: 0
      duration: root.scrollDuration
      easing.type: Easing.InOutSine
    }
  }

  onScrollingChanged: if (!scrolling) label.x = 0
  function restartScroll() { label.x = 0; scroll.restart() }
  onWidthChanged: if (scrolling) restartScroll()
  onTextFontChanged: if (scrolling) restartScroll()
  onTextChanged: {
    if (details.opened) details.close()
    if (scrolling) restartScroll()
  }
  onVisibleChanged: if (!visible) details.close()
}
