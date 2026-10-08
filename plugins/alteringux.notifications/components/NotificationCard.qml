// Notification card. Pure presentational — no service, Notification, or
// ListModel references. The popup container drives lifetime; the history
// panel drives static rendering. Both use the same component.

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic
import "../../shared"
import "../../alteringux.kit" as Kit

BorderSurface {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  // Nerd Font glyph rendered in the icon slot when no real icon is set.
  // Used by omarchy-notification-send so user-action toasts (`Silenced
  // notifications` etc.) show their bell/lock/etc. glyph without leaking
  // into the summary text.
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  property int cornerRadius: 0

  // System monospace font injected by the container.
  property string fontFamily: ""
  property bool separateDetailsWindow: false
  readonly property bool hasClippedText: (summaryText.visible && summaryText.hasOverflow)
    || (bodyText.visible && bodyText.hasOverflow)
  readonly property string accessibleLabel: {
    var content = summaryText.readableText || bodyText.readableText
    var sender = root.app.trim()
    if (sender && content) return "Notification from " + sender + ": " + content
    if (content) return "Notification: " + content
    if (sender) return "Notification from " + sender
    return "Notification"
  }
  readonly property alias readButton: readButton
  readonly property alias detailsView: notificationDetails

  readonly property bool pointerHovered: hoverTracker.hovered
  readonly property bool readingActive: summaryText.detailsVisible || bodyText.detailsVisible
    || notificationDetails.opened
  // The toast lifetime consumes hovered. Keep it paused during deliberate
  // keyboard reading as well, so the parent cannot expire mid-copy.
  readonly property bool keyboardReading: root.visible && root.Window.window
    && root.Window.window.visible && root.Window.window.active
    && (activeFocus || summaryText.activeFocus || bodyText.activeFocus || readButton.activeFocus)
  readonly property bool hovered: pointerHovered || readingActive || keyboardReading

  signal closeRequested()
  signal cardClicked()
  // Prefer per-notification media/avatar data, then fall back to the app icon.
  // The `check` flag avoids Qt's missing-texture placeholder for unknown names.
  readonly property string smallIconSource: image.length > 0 ? image : iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool compactGlyph: NotificationLogic.shouldRenderCompactGlyph(glyph, smallIconSource, singleLineToast)
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  // Commit normalized input after source bindings settle. Measuring rich
  // text during a sanitizer binding can re-enter that same binding.
  property string _sanitizedBody: ""
  readonly property string sanitizedBody: _sanitizedBody
  readonly property string styledBody: sanitizedBody.replace(/\r\n|\r|\n/g, "<br/>")

  readonly property color dimColor: _webPalette.muted
  readonly property color bodyColor: _webPalette.notificationText
  readonly property color accentColor: urgency === 2 ? _webPalette.urgent : (urgency === 0 ? dimColor : _webPalette.notificationCountdown)
  readonly property var cardBorderSpec: Border.surfaceSpec("notifications", "border", _webPalette.notificationBorder, Math.max(1, Style.space(2)))


  function sanitizeBody(s) {
    return NotificationLogic.sanitizeBody(s, app, appIcon)
  }
  function refreshSanitizedBody() {
    root._sanitizedBody = root.sanitizeBody(root.body)
  }
  Component.onCompleted: Qt.callLater(root.refreshSanitizedBody)

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  implicitWidth: Style.space(380)
  // Add vertical border insets so mainColumn (inset by border on top/left/right)
  // doesn't push content under the bottom edge.
  implicitHeight: mainColumn.implicitHeight + borderTop + borderBottom
  radius: cornerRadius
  color: _webPalette.notificationBackground
  borderSpec: cardBorderSpec
  clip: true
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: root.accessibleLabel
  Accessible.description: "Enter: open notification. Delete: dismiss. F2 or Read complete text: read clipped text."
  Accessible.onPressAction: root.cardClicked()
  Keys.onReturnPressed: root.cardClicked()
  Keys.onEnterPressed: root.cardClicked()
  Keys.onSpacePressed: root.cardClicked()
  Keys.onDeletePressed: root.closeRequested()
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_F2 && root.hasClippedText) {
      root.readCompleteText()
      event.accepted = true
    }
  }

  function readCompleteText() {
    if (visible && enabled && hasClippedText) {
      root.refreshSanitizedBody()
      notificationDetails.sourceText = [root.summary, bodyText.readableText]
        .filter(function(text) { return text.length > 0 }).join("\n\n")
      notificationDetails.open()
    }
  }
  onVisibleChanged: if (!visible) notificationDetails.close()
  onSummaryChanged: if (notificationDetails.opened) notificationDetails.close()
  onBodyChanged: {
    Qt.callLater(root.refreshSanitizedBody)
    if (notificationDetails.opened) notificationDetails.close()
  }
  onAppChanged: {
    Qt.callLater(root.refreshSanitizedBody)
    if (notificationDetails.opened) notificationDetails.close()
  }
  onAppIconChanged: {
    Qt.callLater(root.refreshSanitizedBody)
    if (notificationDetails.opened) notificationDetails.close()
  }

  FullTextView {
    id: notificationDetails
    title: root.app.length ? "Notification from " + root.app : "Complete notification"
    sourceFont: bodyText.textFont
    returnFocusItem: readButton.visible ? readButton : root
    forceSeparateWindow: root.separateDetailsWindow
  }

  HoverHandler { id: hoverTracker }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    radius: root.cornerRadius
    border.width: 2
    border.color: _webPalette.accent
    visible: root.activeFocus
    z: 10
    Accessible.ignored: true
  }

  // A glanceable severity stripe for the two urgencies that aren't "business
  // as usual" -- accentColor was already computed (urgent red for critical,
  // dimmed for low) but had no consumer, so every toast looked identical
  // regardless of urgency until you read the text. Normal-urgency toasts
  // (the common case) stay stripe-free rather than adding noise.
  Rectangle {
    id: urgencyStripe
    visible: root.urgency !== 1
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.borderLeft
    anchors.topMargin: root.borderTop
    anchors.bottomMargin: root.borderBottom
    width: Style.space(3)
    color: root.accentColor
  }

  MouseArea {
    id: cardMouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.closeRequested()
      } else {
        root.cardClicked()
      }
    }
  }

  ColumnLayout {
    id: mainColumn
    // Inset by the card border so the content doesn't paint over the card's
    // outer border.
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.borderTop
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
    spacing: 0

    // Text content.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      Layout.bottomMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? Style.space(8) : Style.space(12))

      Item {
        id: smallIconSlot
        Layout.preferredWidth: visible ? Style.space(40) : 0
        Layout.preferredHeight: visible ? Style.space(40) : 0
        Layout.alignment: Qt.AlignVCenter
        // Hide the slot when the icon failed to resolve (themed-icon name
        // not in the user's icon theme) AND we don't have a glyph fallback
        // — prevents rendering Qt's pink broken-image placeholder.
        visible: !root.collapseRedundantIcon && !root.compactGlyph && (root.hasSmallIcon || root.hasGlyph) && (root.hasGlyph || smallIconImage.status !== Image.Error)

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          visible: !root.hasGlyph || smallIconImage.status === Image.Ready
        }

        // Glyph fallback (Nerd Font character) when no image icon is
        // available. Used by omarchy-notification-send's `-g` flag.
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: root.hasGlyph && smallIconImage.status !== Image.Ready
          text: root.glyph
          color: _webPalette.notificationText
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
        visible: root.compactGlyph
        text: root.glyph
        color: _webPalette.notificationText
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        MarqueeText {
          id: summaryText
          focusableOnOverflow: false
          separateDetailsWindow: root.separateDetailsWindow
          active: root.pointerHovered && !root.readingActive
          // The spec defines the summary as a single line of plain text, so
          // AutoText (Text's default) could only ever promote a hostile
          // string to rich text -- a sender could make its summary render
          // bold/colored/linked instead of literal text, up to visually
          // spoofing another app's toast. The body below is StyledText on
          // purpose (see Service.qml's bodyMarkupSupported) and is sanitized
          // in NotificationLogic; the summary never should be.
          requestedTextFormat: Text.PlainText
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          textFont.family: Style.font.menuFamily
          color: _webPalette.notificationText
          textFont.pixelSize: Style.font.title
          textFont.bold: true
          requestedWrapMode: Text.WordWrap
          requestedMaximumLineCount: 2
        }

        MarqueeText {
          id: bodyText
          focusableOnOverflow: false
          separateDetailsWindow: root.separateDetailsWindow
          active: root.pointerHovered && !root.readingActive
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          visible: root.sanitizedBody.length > 0
          text: root.styledBody
          requestedTextFormat: Text.StyledText
          textFont.family: Style.font.menuFamily
          color: root.bodyColor
          textFont.pixelSize: Style.font.title
          requestedWrapMode: Text.WordWrap
          requestedMaximumLineCount: 3
        }
      }
    }

    Kit.ActionButton {
      id: readButton
      objectName: "notification-read-complete-text"
      text: "Read complete text"
      visible: root.hasClippedText
      Layout.alignment: Qt.AlignRight
      Layout.rightMargin: Style.space(12)
      Layout.bottomMargin: Style.space(8)
      fontFamily: Style.font.menuFamily
      fontSize: Style.font.caption
      foreground: _webPalette.notificationText
      bordered: true
      Accessible.name: "Read complete notification text"
      Accessible.description: "Open a stationary, selectable view. Escape returns to this button."
      onClicked: root.readCompleteText()
    }
  }

}
