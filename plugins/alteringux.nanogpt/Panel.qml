import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
import "../shared"

Panel {
  property QtObject _webPalette: Kit.Palette {}
  id: root
  moduleName: "alteringux.nanogpt"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.nanogpt", function(argv) { Quickshell.execDetached(argv) })

  readonly property color fg: bar ? _webPalette.barTextColorFor(bar.barForeground) : _webPalette.foreground
  readonly property color accent: _webPalette.accent
  readonly property color urgent: bar ? bar.urgent : _webPalette.urgent
  readonly property color track: Style.selectedFillFor(root.fg, _webPalette.accent)
  readonly property color surface: _webPalette.cardBackgroundFor(root.fg)
  readonly property color border: _webPalette.cardBorderFor(root.fg)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool ready: hostWidget ? hostWidget.ready : false
  readonly property var plan: hostWidget ? hostWidget.plan : {}
  readonly property var today: hostWidget ? hostWidget.today : {}
  readonly property var week: hostWidget ? hostWidget.week : []
  readonly property var allTime: hostWidget ? hostWidget.allTime : {}
  readonly property var models: hostWidget ? hostWidget.models : []
  readonly property var tokenComposition: hostWidget ? hostWidget.tokenComposition : {}
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing : false

  readonly property real quotaRatio: Model.quotaRatio(root.plan)
  readonly property color quotaTone: root.quotaRatio >= 0.9
    ? _webPalette.negative
    : (root.quotaRatio >= 0.75 ? _webPalette.warning : root.accent)

  readonly property string todayStr: new Date().toISOString().slice(0, 10)

  function snapshotFreshness() {
    var updatedAt = hostWidget && hostWidget.state ? Date.parse(hostWidget.state.updatedAt || "") : NaN
    return isFinite(updatedAt)
      ? "updated " + Qt.formatDateTime(new Date(updatedAt), "hh:mm")
      : "no successful snapshot yet"
  }
  readonly property int weekPeak: Model.weekPeak(root.week)
  readonly property int mPeak: Model.modelPeak(root.models)
  readonly property real cPeak: Model.costPeak(root.models)
  readonly property int hPeak: Model.hourPeak(root.today ? root.today.tokensByHour : null)
  readonly property var composition: Model.compositionPercents(root.tokenComposition)

  readonly property var compositionColors: [
    root.fg,
    root.accent,
    root.urgent,
    Util.alpha(root.fg, 0.6),
    Util.alpha(root.fg, 0.35),
  ]

  property string selectedModelId: ""

  readonly property var selectedModel: {
    if (!root.selectedModelId) return null
    for (var i = 0; i < root.models.length; i++) {
      if (root.models[i].id === root.selectedModelId) return root.models[i]
    }
    return null
  }
  // A refresh can remove a previously selected model. Clear that stale
  // selection or the main dashboard remains hidden with no detail to show.
  onModelsChanged: {
    if (root.selectedModelId && !root.selectedModel) root.clearSelection()
  }

  function selectModel(id) { root.selectedModelId = id }
  function clearSelection() { root.selectedModelId = "" }

  function alpha(c, a) { return Util.alpha(c, a) }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(680)))

    Kit.PanelKeys {
      anchors.fill: parent
      escapeShortcutDescription: root.selectedModelId ? "Clear the selected model" : "Close the panel"
      onCloseRequested: {
        if (root.selectedModelId) root.clearSelection()
        else root.close()
      }
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()
      additionalShortcutDescriptions: [
        { keys: "Enter / Space", description: "Refresh model data", context: "NanoGPT · shortcut focus" }
      ]

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            glyph: ""
            title: "NanoGPT"
            meta: {
              if (!root.ready) return root.refreshing ? "refreshing…" : "no data yet"
              var p = root.plan
              var parts = []
              if (root.refreshing) parts.push("refreshing")
              if (p.active) {
                parts.push("subscription")
                parts.push(Model.quotaPctLabel(p) + " weekly")
              } else {
                parts.push("pay-as-you-go")
              }
              if (p.routingMode && !p.active) parts.push(p.routingMode)
              parts.push(root.snapshotFreshness())
              return parts.join(" · ")
            }
            foreground: root.fg
            trailingControl: Component {
              Kit.ActionButton {
                focusable: true
                Accessible.role: Accessible.Button
                Accessible.name: text
                text: "Refresh"
                foreground: root.fg
                bordered: true
                onClicked: if (hostWidget) hostWidget.runRefresh()
              }
            }
          }

          Kit.EmptyState {
            visible: !root.ready
            text: "No usage data yet"
            hint: "Send a request through NanoGPT (hermes -z, or the llm-blurb helpers) to populate stats"
            foreground: root.fg
            width: parent.width
          }

          Column {
            width: parent.width
            spacing: Style.spacing.panelGap
            visible: root.ready && !root.selectedModelId

            Rectangle {
              width: parent.width
              height: Style.space(72)
              radius: Style.cornerRadius
              color: root.surface
              border.width: 1
              border.color: root.border

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(12)
                spacing: Style.space(12)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2
                  Text {
                    text: "TODAY"
                    color: _webPalette.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                  }
                  Text {
                    text: Model.formatTokens(root.today.totalTokens || 0)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  Text {
                    text: Model.formatNumber(root.today.prompts || 0) + " prompts · " + Model.formatCost(root.today.estimatedCost || 0)
                    color: root.alpha(root.fg, 0.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2
                  Text {
                    text: "ALL-TIME"
                    color: _webPalette.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                  }
                  Text {
                    text: Model.formatTokens(root.allTime.totalTokens || 0)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  Text {
                    text: Model.formatCost(root.allTime.estimatedCost || 0) + " est. · " + (root.allTime.activeDays || 0) + " active days"
                    color: root.alpha(root.fg, 0.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.plan && root.plan.active === true

              PanelSectionHeader {
                text: "Weekly Quota"
                color: _webPalette.muted
                font.family: root.fontFamily
              }

              Rectangle {
                width: parent.width
                height: Style.space(60)
                radius: Style.cornerRadius
                color: root.surface
                border.width: 1
                border.color: root.border

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  spacing: Style.space(6)

                  RowLayout {
                    width: parent.width
                    Text {
                      text: Model.formatTokens(root.plan.weeklyUsed || 0) + " / " + Model.formatTokens(root.plan.weeklyLimit || 0) + " input tokens"
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      Layout.fillWidth: true
                    }
                    Text {
                      text: Model.quotaPctLabel(root.plan)
                      color: root.quotaTone
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(8)
                    radius: height / 2
                    color: root.track

                    Rectangle {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      height: parent.height
                      radius: parent.radius
                      width: parent.width * root.quotaRatio
                      color: root.quotaTone

                      Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                  }

                  Text {
                    text: {
                      var parts = []
                      var r = Model.formatResetIn(root.plan.resetAt)
                      if (r) parts.push(r)
                      if ((root.plan.dailyImagesLimit || 0) > 0)
                        parts.push("images " + (root.plan.dailyImagesUsed || 0) + "/" + root.plan.dailyImagesLimit + " today")
                      return parts.join("  ·  ")
                    }
                    color: _webPalette.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Tokens by Day"
              color: _webPalette.muted
              font.family: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.week.length > 0

              Repeater {
                model: root.week

                delegate: Item {
                  width: parent.width
                  height: Style.space(28)
                  required property var modelData
                  required property int index

                  readonly property real ratio: root.weekPeak > 0 ? Model.clamp(Number(modelData.totalTokens || 0) / root.weekPeak, 0, 1) : 0
                  readonly property bool isToday: modelData.date === root.todayStr

                  Text {
                    id: dayLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.dayLabel(modelData.date, root.todayStr)
                    color: isToday ? root.fg : root.alpha(root.fg, 0.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: isToday
                    width: Style.space(48)
                  }

                  Rectangle {
                    id: dayTrack
                    anchors.left: dayLabel.right
                    anchors.right: dayValue.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    height: Style.space(6)
                    radius: height / 2
                    color: root.track

                    Rectangle {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      height: parent.height
                      radius: parent.radius
                      width: parent.width * ratio
                      color: isToday ? root.fg : root.alpha(root.fg, 0.5)

                      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                  }

                  Text {
                    id: dayValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatTokens(modelData.totalTokens || 0)
                    color: root.alpha(root.fg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Tokens by Model"
              color: _webPalette.muted
              font.family: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              visible: root.models.length > 0

              Repeater {
                model: root.models

                delegate: Item {
                  width: parent.width
                  height: Style.space(36)
                  required property var modelData
                  required property int index

                  readonly property real share: root.mPeak > 0 ? Model.clamp(Number(modelData.total || 0) / root.mPeak, 0, 1) : 0
                  readonly property bool isSelected: root.selectedModelId === modelData.id

                  Rectangle {
                    id: modelButton
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: isSelected ? root.alpha(root.accent, 0.12) : root.alpha(root.fg, 0.05)
                    border.width: isSelected || activeFocus ? 1 : 0
                    border.color: activeFocus ? _webPalette.accent : root.alpha(root.accent, 0.3)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: (modelData.id || "Model") + ", " + Model.formatTokens(modelData.total || 0)
                      + " tokens, " + Model.formatCost(modelData.cost || 0)
                    Accessible.description: isSelected ? "Selected model. Activate to view details." : "Activate to view model details."
                    Accessible.focusable: true
                    Accessible.onPressAction: root.selectModel(modelData.id)
                    Keys.onReturnPressed: { root.selectModel(modelData.id); event.accepted = true }
                    Keys.onEnterPressed: { root.selectModel(modelData.id); event.accepted = true }
                    Keys.onSpacePressed: { root.selectModel(modelData.id); event.accepted = true }

                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: parent.width * share
                      radius: Style.cornerRadius
                      color: root.alpha(root.fg, 0.12)

                      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    MarqueeText {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.id || ""
                      focusableOnOverflow: false
                      color: root.fg
                      textFont.family: root.fontFamily
                      textFont.pixelSize: Style.font.body
                      textFont.bold: isSelected
                      requestedElide: Text.ElideRight
                      width: parent.width * 0.55
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.formatTokens(modelData.total || 0) + "  ·  " + Model.formatCost(modelData.cost || 0)
                      color: root.alpha(root.fg, 0.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: { modelButton.forceActiveFocus(); root.selectModel(modelData.id) }
                    }
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Token Composition"
              color: _webPalette.muted
              font.family: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: root.composition.length > 0

              Rectangle {
                width: parent.width
                height: Style.space(12)
                radius: height / 2
                color: root.track

                Row {
                  anchors.fill: parent
                  spacing: 0

                  Repeater {
                    model: root.composition

                    delegate: Rectangle {
                      height: parent.height
                      width: root.composition.length > 0 && index < root.composition.length
                        ? parent.width * modelData.pct : 0
                      color: index < root.compositionColors.length ? root.compositionColors[index] : root.fg
                      radius: index === 0 ? parent.height / 2 : (index === root.composition.length - 1 ? parent.height / 2 : 0)

                      Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                  }
                }
              }

              GridLayout {
                width: parent.width
                columns: 3
                rowSpacing: Style.space(4)
                columnSpacing: Style.space(8)

                Repeater {
                  model: root.composition

                  delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Rectangle {
                      width: Style.space(8)
                      height: Style.space(8)
                      radius: 2
                      color: index < root.compositionColors.length ? root.compositionColors[index] : root.fg
                    }

                    Text {
                      text: modelData.label
                      color: root.alpha(root.fg, 0.7)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      Layout.fillWidth: true
                    }

                    Text {
                      text: (modelData.pct * 100).toFixed(1) + "%"
                      color: _webPalette.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Cost by Model"
              color: _webPalette.muted
              font.family: root.fontFamily
              visible: root.models.length > 0 && root.cPeak > 0
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              visible: root.models.length > 0 && root.cPeak > 0

              Repeater {
                model: root.models

                delegate: Item {
                  width: parent.width
                  height: Style.space(28)
                  required property var modelData
                  required property int index

                  readonly property real costShare: root.cPeak > 0 ? Model.clamp(Number(modelData.cost || 0) / root.cPeak, 0, 1) : 0

                  MarqueeText {
                    id: costModelLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.id || ""
                    color: root.alpha(root.fg, 0.7)
                    textFont.family: root.fontFamily
                    textFont.pixelSize: Style.font.caption
                    requestedElide: Text.ElideRight
                    width: parent.width * 0.5
                  }

                  Rectangle {
                    id: costTrack
                    anchors.left: costModelLabel.right
                    anchors.right: costValue.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    height: Style.space(5)
                    radius: height / 2
                    color: root.track

                    Rectangle {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      height: parent.height
                      radius: parent.radius
                      width: parent.width * costShare
                      color: root.urgent

                      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                  }

                  Text {
                    id: costValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatCost(modelData.cost || 0)
                    color: root.alpha(root.fg, 0.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            PanelSeparator {
              color: root.border
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              RowLayout {
                width: parent.width
                Text {
                  text: "Total Prompts"
                  color: root.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                }
                Text {
                  text: Model.formatNumber(root.allTime.totalPrompts || 0)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              RowLayout {
                width: parent.width
                Text {
                  text: "Total Tokens"
                  color: root.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                }
                Text {
                  text: Model.formatTokens(root.allTime.totalTokens || 0)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              RowLayout {
                width: parent.width
                visible: (root.allTime.estimatedCost || 0) > 0
                Text {
                  text: "Estimated Cost"
                  color: root.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                }
                Text {
                  text: Model.formatCost(root.allTime.estimatedCost || 0)
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              RowLayout {
                width: parent.width
                Text {
                  text: "Active Days"
                  color: root.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                }
                Text {
                  text: (root.allTime.activeDays || 0) + "  (" + (root.allTime.firstUse || "—") + " → " + (root.allTime.lastUse || "—") + ")"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              RowLayout {
                width: parent.width
                Text {
                  text: "Models Used"
                  color: root.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  Layout.fillWidth: true
                }
                Text {
                  text: String(root.models.length)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.panelGap
            visible: root.ready && root.selectedModelId && root.selectedModel !== null

            Kit.ActionButton {
              focusable: true
              Accessible.role: Accessible.Button
              Accessible.name: text
              text: "← Back"
              foreground: root.fg
              bordered: true
              onClicked: root.clearSelection()
            }

            Rectangle {
              width: parent.width
              height: Style.space(52)
              radius: Style.cornerRadius
              color: root.surface
              border.width: 1
              border.color: root.border

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                MarqueeText {
                  width: parent.width
                  text: root.selectedModel ? root.selectedModel.id : ""
                  color: root.fg
                  textFont.family: root.fontFamily
                  textFont.pixelSize: Style.font.title
                  textFont.bold: true
                  requestedElide: Text.ElideRight
                }
                Text {
                  text: {
                    var m = root.selectedModel
                    if (!m) return ""
                    var parts = []
                    if (m.modelClass) parts.push(m.modelClass)
                    if (m.inputPrice > 0) parts.push("$" + m.inputPrice + "/M in")
                    if (m.outputPrice > 0) parts.push("$" + m.outputPrice + "/M out")
                    if (!parts.length) parts.push(Model.formatNumber(m.messages || 0) + " requests")
                    return parts.join("  ·  ")
                  }
                  color: _webPalette.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            PanelSectionHeader {
              text: "Token Breakdown"
              color: _webPalette.muted
              font.family: root.fontFamily
            }

            Column {
              id: tokenBreakdownCol
              width: parent.width
              spacing: Style.space(8)
              visible: root.selectedModel !== null

              readonly property var mComp: Model.modelCompositionPercents(root.selectedModel)

              Rectangle {
                width: parent.width
                height: Style.space(12)
                radius: height / 2
                color: root.track

                Row {
                  anchors.fill: parent
                  spacing: 0

                  Repeater {
                    model: tokenBreakdownCol.mComp

                    delegate: Rectangle {
                      height: parent.height
                      width: parent.width * modelData.pct
                      color: index < root.compositionColors.length ? root.compositionColors[index] : root.fg
                      radius: index === 0 ? parent.height / 2 : (index === tokenBreakdownCol.mComp.length - 1 ? parent.height / 2 : 0)

                      Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                  }
                }
              }

              GridLayout {
                width: parent.width
                columns: 2
                rowSpacing: Style.space(4)
                columnSpacing: Style.space(8)

                Repeater {
                  model: tokenBreakdownCol.mComp

                  delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Rectangle {
                      width: Style.space(8)
                      height: Style.space(8)
                      radius: 2
                      color: index < root.compositionColors.length ? root.compositionColors[index] : root.fg
                    }

                    Text {
                      text: modelData.label
                      color: root.alpha(root.fg, 0.7)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      Layout.fillWidth: true
                    }

                    Text {
                      text: Model.formatTokens(modelData.value) + "  (" + (modelData.pct * 100).toFixed(1) + "%)"
                      color: _webPalette.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Daily Usage (7 days)"
              color: _webPalette.muted
              font.family: root.fontFamily
            }

            Column {
              id: dailyUsageCol
              width: parent.width
              spacing: Style.space(6)
              visible: root.selectedModel !== null && root.selectedModel && root.selectedModel.recentDays

              readonly property int dPeak: Model.modelDayPeak(root.selectedModel)

              Repeater {
                model: root.selectedModel ? root.selectedModel.recentDays : []

                delegate: Item {
                  width: parent.width
                  height: Style.space(28)
                  required property var modelData
                  required property int index

                  readonly property real ratio: dailyUsageCol.dPeak > 0 ? Model.clamp(Number(modelData.totalTokens || 0) / dailyUsageCol.dPeak, 0, 1) : 0
                  readonly property bool isToday: modelData.date === root.todayStr

                  Text {
                    id: dDayLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.dayLabel(modelData.date, root.todayStr)
                    color: isToday ? root.fg : root.alpha(root.fg, 0.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: isToday
                    width: Style.space(48)
                  }

                  Rectangle {
                    id: dDayTrack
                    anchors.left: dDayLabel.right
                    anchors.right: dDayValue.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    height: Style.space(6)
                    radius: height / 2
                    color: root.track

                    Rectangle {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      height: parent.height
                      radius: parent.radius
                      width: parent.width * ratio
                      color: isToday ? root.accent : root.alpha(root.fg, 0.5)

                      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                  }

                  Text {
                    id: dDayValue
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatTokens(modelData.totalTokens || 0)
                    color: root.alpha(root.fg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Statistics"
              color: _webPalette.muted
              font.family: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              RowLayout {
                width: parent.width
                Text { text: "Requests"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatNumber(root.selectedModel ? root.selectedModel.messages : 0); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }

              RowLayout {
                width: parent.width
                Text { text: "Total Tokens"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatTokens(root.selectedModel ? root.selectedModel.total : 0); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }

              RowLayout {
                width: parent.width
                Text { text: "Avg Tokens / Request"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatTokens(Model.avgTokensPerPrompt(root.selectedModel)); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }

              RowLayout {
                width: parent.width
                visible: (root.selectedModel ? root.selectedModel.cost : 0) > 0
                Text { text: "Estimated Cost"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatCost(root.selectedModel ? root.selectedModel.cost : 0); color: root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }

              RowLayout {
                width: parent.width
                visible: (root.selectedModel ? root.selectedModel.cost : 0) > 0
                Text { text: "Cost / Request"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatCost(Model.costPerPrompt(root.selectedModel)); color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }

              RowLayout {
                width: parent.width
                visible: (root.selectedModel ? root.selectedModel.cost : 0) > 0
                Text { text: "Cost / 1M Tokens"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatCost(Model.costPerMtok(root.selectedModel)); color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }
            }
          }
        }
      }
    }
  }
}
