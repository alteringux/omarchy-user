import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

Panel {
  id: root
  moduleName: "alteringux.featherless"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var guard: Kit.BugGuard.create("alteringux.featherless", function(argv) { Quickshell.execDetached(argv) })

  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color track: Style.selectedFillFor(root.fg, Color.accent)
  readonly property color surface: Util.alpha(root.fg, 0.05)
  readonly property color border: Util.alpha(root.fg, 0.14)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool ready: hostWidget ? hostWidget.ready : false
  readonly property var plan: hostWidget ? hostWidget.plan : {}
  readonly property var today: hostWidget ? hostWidget.today : {}
  readonly property var week: hostWidget ? hostWidget.week : []
  readonly property var allTime: hostWidget ? hostWidget.allTime : {}
  readonly property var models: hostWidget ? hostWidget.models : []
  readonly property var tokenComposition: hostWidget ? hostWidget.tokenComposition : {}
  readonly property bool refreshing: hostWidget ? hostWidget.refreshing : false

  readonly property string todayStr: new Date().toISOString().slice(0, 10)
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

  function selectModel(id) { root.selectedModelId = id }
  function clearSelection() { root.selectedModelId = "" }

  function alpha(c, a) { return Util.alpha(c, a) }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(680)))

    PanelKeyCatcher {
      anchors.fill: parent
      onCloseRequested: {
        if (root.selectedModelId) root.clearSelection()
        else root.close()
      }
      onActivateRequested: if (hostWidget) hostWidget.runRefresh()

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            glyph: "\uf0d0"
            title: "Featherless"
            meta: {
              if (!root.ready) return root.refreshing ? "refreshing…" : "no data yet"
              var p = root.plan
              var parts = []
              if (p.name) parts.push(p.name)
              if (p.concurrency) parts.push(p.concurrency + " concurrent")
              return parts.length ? parts.join(" · ") : "usage analytics"
            }
            foreground: root.fg
            trailingControl: Component {
              Button {
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
            hint: "Run a Featherless model through opencode to populate stats"
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
                    color: root.alpha(root.fg, 0.5)
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
                    color: root.alpha(root.fg, 0.5)
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

            PanelSectionHeader {
              text: "Tokens by Day"
              color: root.alpha(root.fg, 0.5)
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
              color: root.alpha(root.fg, 0.5)
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
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: isSelected ? root.alpha(root.accent, 0.12) : root.alpha(root.fg, 0.05)
                    border.width: isSelected ? 1 : 0
                    border.color: root.alpha(root.accent, 0.3)

                    Rectangle {
                      anchors.left: parent.left
                      anchors.top: parent.top
                      anchors.bottom: parent.bottom
                      width: parent.width * share
                      radius: Style.cornerRadius
                      color: root.alpha(root.fg, 0.12)

                      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.shortModelName(modelData.id || "")
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: isSelected
                      elide: Text.ElideRight
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
                      onClicked: root.selectModel(modelData.id)
                    }
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Token Composition"
              color: root.alpha(root.fg, 0.5)
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
                      color: root.alpha(root.fg, 0.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Usage by Hour (Today)"
              color: root.alpha(root.fg, 0.5)
              font.family: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              visible: root.today && root.today.tokensByHour && root.today.tokensByHour.length > 0

              Item {
                width: parent.width
                height: Style.space(80)

                readonly property var hours: root.today ? root.today.tokensByHour : []

                Row {
                  anchors.fill: parent
                  spacing: 1

                  Repeater {
                    model: parent.hours

                    delegate: Item {
                      width: parent.width / 24 - 1
                      height: parent.height
                      required property var modelData
                      required property int index

                      readonly property real ratio: root.hPeak > 0 ? Model.clamp(Number(modelData || 0) / root.hPeak, 0, 1) : 0

                      Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: parent.height * ratio
                        color: ratio > 0.7 ? root.accent : (ratio > 0 ? root.alpha(root.fg, 0.5) : root.alpha(root.fg, 0.1))
                        radius: 1

                        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                      }
                    }
                  }
                }
              }

              Row {
                width: parent.width
                spacing: 0

                Repeater {
                  model: 24

                  delegate: Text {
                    width: parent.width / 24
                    horizontalAlignment: Text.AlignHCenter
                    text: index % 6 === 0 ? String(index) : ""
                    color: root.alpha(root.fg, 0.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Cost by Model"
              color: root.alpha(root.fg, 0.5)
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
                  height: Style.space(28)
                  required property var modelData
                  required property int index

                  readonly property real costShare: root.cPeak > 0 ? Model.clamp(Number(modelData.cost || 0) / root.cPeak, 0, 1) : 0

                  Text {
                    id: costModelLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.shortModelName(modelData.id || "")
                    color: root.alpha(root.fg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
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

            Button {
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

                Text {
                  text: Model.shortModelName(root.selectedModel ? root.selectedModel.id : "")
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  text: {
                    var m = root.selectedModel
                    if (!m) return ""
                    var parts = []
                    if (m.modelClass) parts.push(m.modelClass)
                    if (m.inputPrice > 0) parts.push("$" + m.inputPrice + "/M in")
                    if (m.outputPrice > 0) parts.push("$" + m.outputPrice + "/M out")
                    return parts.join("  ·  ")
                  }
                  color: root.alpha(root.fg, 0.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            PanelSectionHeader {
              text: "Token Breakdown"
              color: root.alpha(root.fg, 0.5)
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
                      color: root.alpha(root.fg, 0.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Daily Usage (7 days)"
              color: root.alpha(root.fg, 0.5)
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
                    text: Model.formatTokens(modelData.totalTokens || 0) + "  ·  " + Model.formatCost(modelData.estimatedCost || 0)
                    color: root.alpha(root.fg, 0.7)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            PanelSectionHeader {
              text: "Statistics"
              color: root.alpha(root.fg, 0.5)
              font.family: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              RowLayout {
                width: parent.width
                Text { text: "Messages"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatNumber(root.selectedModel ? root.selectedModel.messages : 0); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }

              RowLayout {
                width: parent.width
                Text { text: "Sessions"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatNumber(root.selectedModel ? root.selectedModel.sessions : 0); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }

              RowLayout {
                width: parent.width
                Text { text: "Total Tokens"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatTokens(root.selectedModel ? root.selectedModel.total : 0); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }

              RowLayout {
                width: parent.width
                Text { text: "Avg Tokens / Message"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatTokens(Model.avgTokensPerPrompt(root.selectedModel)); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }

              RowLayout {
                width: parent.width
                Text { text: "Estimated Cost"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatCost(root.selectedModel ? root.selectedModel.cost : 0); color: root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }

              RowLayout {
                width: parent.width
                Text { text: "Cost / Message"; color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption; Layout.fillWidth: true }
                Text { text: Model.formatCost(Model.costPerPrompt(root.selectedModel)); color: root.alpha(root.fg, 0.6); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              }

              RowLayout {
                width: parent.width
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