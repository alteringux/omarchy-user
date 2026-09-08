import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Popup for alteringux.flow. Two tabs:
//   OUTPUT  — the flow's latest envelopes drawn by shape (markdown / series /
//             table / log)
//   CANVAS  — the flow document as a draggable node graph: move a node (snaps
//             to grid, persists to the JSON file), rename it in place, edit its
//             prompt / cmd / jq, drag from one node to another to (dis)connect,
//             add / delete nodes, and Run the whole thing.
//
// All editing goes through hostWidget.* which mutates the parsed doc and lets
// Kit.Store write it back in the on-disk shape (Model.serializeDoc).
Panel {
  id: root
  moduleName: "alteringux.flow"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null
  property int inlineEditors: 0

  readonly property var guard: Kit.BugGuard.create("alteringux.flow", function (argv) { Quickshell.execDetached(argv) })

  readonly property var doc: hostWidget && hostWidget.doc ? hostWidget.doc : ({ id: "", nodes: [] })
  readonly property var runState: hostWidget && hostWidget.runState ? hostWidget.runState : ({ nodes: {}, envelopes: [] })
  readonly property var envelopes: runState && runState.envelopes ? runState.envelopes : []
  readonly property var nodes: doc && doc.nodes ? doc.nodes : []
  readonly property var edges: root.guard.call("edges", function () { return Model.edgeList(root.doc) }, [])
  readonly property var canvasBounds: root.guard.call("bounds", function () { return Model.bounds(root.doc) }, ({ w: 400, h: 300 }))

  property string tab: "output"
  property string selectedId: ""
  readonly property var selectedNode: root.selectedId ? Model.nodeById(root.doc, root.selectedId) : null

  // ---- brief play controls -------------------------------------------------
  readonly property string focusSector: root.hostWidget ? (root.hostWidget.focusSector || "") : ""
  readonly property bool hasBriefText: root.hostWidget && root.hostWidget.briefText && root.hostWidget.briefText.length > 0
  readonly property bool isBrief: String(root.doc.id || "").indexOf("brief") >= 0
  // Sector names come straight from the "Headlines per sector" chart's labels,
  // so the picker always mirrors what the last run actually fetched.
  readonly property var sectorLabels: root.guard.call("sectorLabels", function () {
    for (var i = 0; i < root.envelopes.length; i++) {
      var e = root.envelopes[i]
      if (e && e.shape === "series" && e.data && Array.isArray(e.data.labels) && e.data.labels.length)
        return e.data.labels
    }
    return []
  }, [])

  function speakBrief() { if (root.hostWidget) root.hostWidget.speakBrief() }
  function speakText(t) { if (root.hostWidget) root.hostWidget.speak(t) }
  function stopSpeak() { if (root.hostWidget) root.hostWidget.stopSpeak() }
  function pickSector(name) { if (root.hostWidget) root.hostWidget.setSector(name || "") }

  // Per-sector news mood from the "Sector mood" table envelope. {} until the
  // flow has produced one.
  readonly property var sectorScores: root.guard.call("sectorScores", function () {
    return Model.sectorScoreMap(root.envelopes)
  }, ({}))
  function scoreBadge(sector) {
    return root.guard.call("scoreBadge", function () {
      return Model.scoreBadge(root.sectorScores[sector])
    }, null)
  }
  function scoreSuffix(sector) {
    var b = root.scoreBadge(sector)
    return b ? ("  " + b.text) : ""
  }

  // One brief bullet -> a Text.StyledText string: bold accent hook, plain
  // detail, muted source. All fields entity-escaped.
  function bulletHtml(b) {
    return root.guard.call("bulletHtml", function () {
      var esc = Model.escapeHtml
      var lead = b.lead
        ? ("<b><font color=\"" + Color.accent + "\">" + esc(b.lead) + "</font></b>  ")
        : ""
      var src = b.source
        ? ("  <font color=\"" + Color.muted + "\">" + esc(b.source) + "</font>")
        : ""
      return lead + esc(b.text) + src
    }, (b && b.text) || "")
  }

  function roleColor(role) {
    if (role === "positive") return Kit.Palette.positive
    if (role === "negative") return Kit.Palette.negative
    if (role === "warning") return Kit.Palette.warning
    return Kit.Palette.faint
  }
  function nodeRole(id) {
    var rn = root.runState && root.runState.nodes ? root.runState.nodes[id] : null
    return Model.statusRole(rn ? rn.status : undefined)
  }
  function nodeError(id) {
    var rn = root.runState && root.runState.nodes ? root.runState.nodes[id] : null
    return rn && rn.error ? rn.error : ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(Style.space(540))

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: root.inlineEditors > 0 || bodyField.activeFocus
      onCloseRequested: root.close()

      Column {
        id: content
        anchors.fill: parent
        spacing: Style.spacing.panelGap

        // ---- header: title + tabs + run ------------------------------------
        RowLayout {
          width: content.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "FLOW · " + (root.doc.id || "?")
            foreground: root.barForeground
            Layout.fillWidth: true
          }
          Button {
            text: "Output"
            foreground: root.barForeground
            bordered: true
            enabled: root.tab !== "output"
            onClicked: root.tab = "output"
          }
          Button {
            text: "Canvas"
            foreground: root.barForeground
            bordered: true
            enabled: root.tab !== "canvas"
            onClicked: root.tab = "canvas"
          }
          Button {
            text: "▶ Run"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.runFlow()
          }
        }

        Text {
          visible: !!root.runState.error
          width: content.width
          text: "last run: " + root.runState.error
          color: Kit.Palette.negative
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // ================= OUTPUT =========================================
        Kit.PanelScroll {
          visible: root.tab === "output"
          width: content.width
          height: content.height - y
          contentHeight: outCol.implicitHeight

          Column {
            id: outCol
            width: parent.width
            spacing: Style.space(12)

            // ---- play + sector controls (brief flows only) -----------------
            Column {
              width: outCol.width
              spacing: Style.space(6)
              visible: root.hasBriefText || (root.isBrief && root.sectorLabels.length > 0)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)
                visible: root.hasBriefText

                Button {
                  text: "▶ Speak brief"
                  foreground: root.barForeground
                  bordered: true
                  onClicked: root.speakBrief()
                }
                Button {
                  text: "■ Stop"
                  foreground: root.barForeground
                  bordered: true
                  onClicked: root.stopSpeak()
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.focusSector ? ("focus: " + root.focusSector) : "focus: all sectors"
                  color: Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)
                visible: root.isBrief && root.sectorLabels.length > 0

                Button {
                  text: "★ All"
                  foreground: root.barForeground
                  bordered: true
                  enabled: root.focusSector !== ""
                  onClicked: root.pickSector("")
                }
                Repeater {
                  model: root.sectorLabels
                  delegate: Button {
                    required property var modelData
                    text: modelData + root.scoreSuffix(modelData)
                    foreground: root.barForeground
                    bordered: true
                    enabled: root.focusSector !== modelData
                    onClicked: root.pickSector(modelData)
                  }
                }
              }

              Text {
                width: parent.width
                visible: root.isBrief && root.sectorLabels.length > 0
                text: "Pick a sector to re-run the brief focused on it · ★ All restores every sector"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Kit.EmptyState {
              visible: root.envelopes.length === 0
              text: "No output yet."
              hint: "Hit Run, or run  flow run " + (root.doc.id || "<id>") + "  in a terminal."
              foreground: root.barForeground
            }

            Repeater {
              model: root.envelopes
              delegate: Rectangle {
                id: envCard
                required property var modelData
                readonly property var env: modelData
                readonly property string rendered: root.guard.call("renderEnv", function () {
                  return Model.renderEnvelopeText(modelData)
                }, "")
                // A markdown brief with "## Sector" headings -> speakable sections.
                readonly property var sections: root.guard.call("sections", function () {
                  return (modelData && modelData.shape === "markdown")
                    ? Model.splitSections(rendered) : []
                }, [])
                readonly property bool sectioned: sections.length >= 2
                readonly property bool isTable: env.shape === "table" && env.data
                  && Array.isArray(env.data.columns) && Array.isArray(env.data.rows)
                readonly property var tableCols: envCard.isTable ? env.data.columns : []
                readonly property var tableRows: envCard.isTable ? env.data.rows : []
                // semantic tone -> Kit.Palette colour (shared card vocabulary)
                readonly property string tone: envCard.sectioned ? "accent"
                  : env.shape === "table" ? "warning"
                  : env.shape === "series" ? "positive"
                  : "accent"
                readonly property color accentColor: Kit.Palette.toneColor(envCard.tone)
                width: outCol.width
                height: card.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                clip: true
                color: Kit.Palette.cardBg
                border.width: 1
                border.color: Kit.Palette.cardBorder

                // coloured spine so each card reads as its own block at a glance
                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: Style.space(3)
                  color: envCard.accentColor
                  opacity: 0.9
                }

                Column {
                  id: card
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(12)
                  anchors.topMargin: Style.space(12)
                  spacing: Style.space(7)

                  Kit.SectionHeading {
                    width: parent.width
                    text: (env.meta && env.meta.title) || env.node || ""
                    foreground: envCard.accentColor
                    pixelSize: Style.font.caption
                  }

                  // Non-sectioned: every shape drawn as monospace text
                  // (Model.renderEnvelopeText), same as `flow view` in a
                  // terminal. Markdown/text wrap; series/table/log stay in a
                  // fixed-pitch block.
                  Text {
                    visible: !envCard.sectioned && !envCard.isTable
                    width: parent.width
                    wrapMode: (env.shape === "markdown" || env.shape === "text") ? Text.WordWrap : Text.NoWrap
                    textFormat: Text.PlainText
                    text: envCard.rendered
                    color: root.barForeground
                    font.family: (env.shape === "markdown" || env.shape === "text")
                      ? Style.font.family
                      : "monospace"
                    font.pixelSize: Style.font.bodySmall
                  }

                  // Tables (the "Sector mood" grid) get real cells so the
                  // signed numbers can be tinted green / red / neutral.
                  Grid {
                    visible: envCard.isTable
                    width: parent.width
                    columns: Math.max(1, envCard.tableCols.length)
                    columnSpacing: Style.space(12)
                    rowSpacing: Style.space(4)
                    flow: Grid.LeftToRight

                    Repeater {
                      model: envCard.isTable ? envCard.tableCols : []
                      delegate: Text {
                        required property var modelData
                        text: String(modelData).toUpperCase()
                        color: envCard.accentColor
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 0.4
                      }
                    }
                    Repeater {
                      model: envCard.isTable ? (envCard.tableRows.length * envCard.tableCols.length) : 0
                      delegate: Text {
                        required property int index
                        readonly property int col: index % envCard.tableCols.length
                        readonly property string colName: String(envCard.tableCols[col] || "")
                        readonly property var cell: envCard.tableRows[Math.floor(index / envCard.tableCols.length)][col]
                        readonly property bool numeric: /^[+-]?\d/.test(String(cell))
                          && ["Today", "Δ prev", "7d avg"].indexOf(colName) >= 0
                        readonly property real n: numeric ? parseFloat(String(cell).replace("+", "")) : 0
                        text: (cell === undefined || cell === null) ? "" : String(cell)
                        color: numeric ? Kit.Palette.signColor(n)
                          : (col === 0 ? root.barForeground : Kit.Palette.faint)
                        font.family: (colName === "Trend") ? "monospace" : Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: col === 0 || (numeric && n !== 0)
                      }
                    }
                  }

                  // Sectioned brief: per "## Sector" — an accent heading with a
                  // 🔊 button + mood badge, a hairline rule, then styled bullets
                  // (bold accent hook · detail · muted source). The leading
                  // dateline (heading "") is a small italic accent line.
                  Repeater {
                    model: envCard.sectioned ? envCard.sections : []
                    delegate: Column {
                      id: secCol
                      required property var modelData
                      readonly property var bullets: root.guard.call("bullets", function () {
                        return Model.splitBullets(modelData.body)
                      }, [])
                      width: card.width
                      spacing: Style.space(4)
                      topPadding: modelData.heading ? Style.space(8) : Style.space(2)

                      // ---- dateline (no heading) ----
                      Text {
                        visible: !modelData.heading
                        width: parent.width
                        text: modelData.body.replace(/^_+|_+$/g, "").replace(/\*/g, "")
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.italic: true
                        font.bold: true
                        wrapMode: Text.WordWrap
                      }

                      // ---- section heading row ----
                      RowLayout {
                        width: parent.width
                        spacing: Style.space(6)
                        visible: !!modelData.heading
                        Button {
                          text: "🔊"
                          foreground: root.barForeground
                          bordered: true
                          onClicked: root.speakText(modelData.speakText)
                        }
                        Kit.SectionHeading {
                          text: modelData.heading
                          uppercase: false
                          pixelSize: Style.font.heading
                        }
                        Text {
                          readonly property var badge: root.scoreBadge(modelData.heading)
                          visible: !!badge
                          text: badge ? badge.text : ""
                          color: badge ? root.roleColor(badge.role) : root.barForeground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                      }

                      Rectangle {
                        visible: !!modelData.heading
                        width: parent.width
                        height: 1
                        color: Kit.Palette.hairline
                      }

                      // ---- bullets ---- (skip for the dateline section)
                      Repeater {
                        model: secCol.modelData.heading ? secCol.bullets : []
                        delegate: Kit.Bullet {
                          required property var modelData
                          width: card.width - Style.space(4)
                          styled: true
                          glyph: modelData.kind === "bullet" ? "▪" : ""
                          foreground: modelData.kind === "note" ? Kit.Palette.faint : root.barForeground
                          text: modelData.kind === "note"
                            ? ("<i>" + Kit.Str.escapeHtml(modelData.text) + "</i>")
                            : root.bulletHtml(modelData)
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ================= CANVAS =========================================
        Column {
          visible: root.tab === "canvas"
          width: content.width
          height: content.height - y
          spacing: Style.space(8)

          // add-node palette
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: ["input", "tool", "transform", "prompt", "route", "reduce", "memory", "view"]
              delegate: Button {
                required property var modelData
                text: "+ " + modelData
                foreground: root.barForeground
                bordered: true
                onClicked: if (root.hostWidget) root.hostWidget.addNode(modelData)
              }
            }
          }

          Flickable {
            id: canvasFlick
            width: parent.width
            height: parent.height - y - editStrip.height - Style.space(16)
            clip: true
            contentWidth: root.canvasBounds.w
            contentHeight: root.canvasBounds.h
            boundsBehavior: Flickable.StopAtBounds

            Rectangle {
              anchors.fill: parent
              color: Util.alpha(root.barForeground, 0.03)
            }

            // edges (straight lines as thin rotated rectangles; refresh on
            // node move). Data edges solid, route gates lighter.
            Repeater {
              model: root.edges
              delegate: Item {
                required property var modelData
                readonly property var a: Model.nodeById(root.doc, modelData.fromId)
                readonly property var b: Model.nodeById(root.doc, modelData.toId)
                visible: !!a && !!b
                readonly property real ax: a ? a.x + Model.NODE_W : 0
                readonly property real ay: a ? a.y + Model.NODE_H / 2 : 0
                readonly property real bx: b ? b.x : 0
                readonly property real by: b ? b.y + Model.NODE_H / 2 : 0
                Rectangle {
                  x: parent.ax
                  y: parent.ay
                  width: Math.hypot(parent.bx - parent.ax, parent.by - parent.ay)
                  height: modelData.kind === "gate" ? 1 : 2
                  color: modelData.kind === "gate"
                    ? Util.alpha(root.barForeground, 0.3)
                    : Util.alpha(Color.accent, 0.6)
                  transformOrigin: Item.TopLeft
                  rotation: Math.atan2(parent.by - parent.ay, parent.bx - parent.ax) * 180 / Math.PI
                }
              }
            }

            // nodes
            Repeater {
              model: root.nodes
              delegate: Rectangle {
                id: nodeRect
                required property var modelData
                readonly property var nd: modelData
                readonly property string role: root.nodeRole(nd.id)
                x: nd.x
                y: nd.y
                width: Model.NODE_W
                height: Model.NODE_H
                radius: Style.cornerRadius
                color: root.selectedId === nd.id
                  ? Util.alpha(Color.accent, 0.16)
                  : Util.alpha(root.barForeground, 0.08)
                border.width: root.selectedId === nd.id ? 2 : 1
                border.color: root.roleColor(nodeRect.role)

                MouseArea {
                  anchors.fill: parent
                  drag.target: nodeRect
                  drag.threshold: 4
                  cursorShape: Qt.OpenHandCursor
                  onClicked: root.selectedId = nodeRect.nd.id
                  onReleased: {
                    if (root.hostWidget && (nodeRect.x !== nodeRect.nd.x || nodeRect.y !== nodeRect.nd.y))
                      root.hostWidget.moveNode(nodeRect.nd.id, nodeRect.x, nodeRect.y)
                  }
                }

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: 2
                  Kit.InlineEdit {
                    width: parent.width
                    text: nodeRect.nd.label || nodeRect.nd.id
                    foreground: root.barForeground
                    pixelSize: Style.font.bodySmall
                    bold: true
                    placeholderText: "label"
                    onEditingChanged: root.inlineEditors += editing ? 1 : -1
                    onAccepted: function (value) {
                      if (root.hostWidget) root.hostWidget.setNodeField(nodeRect.nd.id, "label", value)
                    }
                  }
                  Text {
                    text: nodeRect.nd.type + (nodeRect.nd.agent ? " · agent" : "")
                    color: Kit.Palette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    visible: root.nodeError(nodeRect.nd.id).length > 0
                    text: root.nodeError(nodeRect.nd.id)
                    color: Kit.Palette.negative
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- selected-node editor strip ---------------------------------
          Rectangle {
            id: editStrip
            width: parent.width
            visible: !!root.selectedNode
            height: visible ? editCol.implicitHeight + Style.space(20) : 0
            radius: Style.cornerRadius
            color: Util.alpha(root.barForeground, 0.05)
            border.width: 1
            border.color: Util.alpha(root.barForeground, 0.14)

            Column {
              id: editCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              readonly property string fieldKey: {
                if (!root.selectedNode) return ""
                var t = root.selectedNode.type
                if (t === "tool") return "cmd"
                if (t === "transform") return "jq"
                return "prompt"
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(8)
                Text {
                  text: (root.selectedNode ? root.selectedNode.id : "") + "  —  " + editCol.fieldKey
                  color: Kit.Palette.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  Layout.fillWidth: true
                }
                Button {
                  text: "agent"
                  foreground: root.barForeground
                  bordered: true
                  visible: root.selectedNode && (root.selectedNode.type === "prompt" || root.selectedNode.type === "route")
                  onClicked: if (root.hostWidget && root.selectedNode)
                    root.hostWidget.setNodeField(root.selectedNode.id, "agent", !root.selectedNode.agent)
                }
                Button {
                  text: "✕ delete"
                  foreground: root.barForeground
                  bordered: true
                  onClicked: {
                    if (root.hostWidget && root.selectedNode) root.hostWidget.removeNode(root.selectedNode.id)
                    root.selectedId = ""
                  }
                }
              }

              TextField {
                id: bodyField
                width: parent.width
                text: root.selectedNode && editCol.fieldKey ? (root.selectedNode[editCol.fieldKey] || "") : ""
                placeholderText: editCol.fieldKey === "cmd" ? "shell command" : editCol.fieldKey === "jq" ? "jq expression" : "prompt — {{node.field}} pulls upstream output"
                foreground: root.barForeground
                onAccepted: {
                  if (root.hostWidget && root.selectedNode && editCol.fieldKey)
                    root.hostWidget.setNodeField(root.selectedNode.id, editCol.fieldKey, text)
                }
              }
              Text {
                width: parent.width
                text: "Enter to save this field · drag a node to move (snaps + saves) · double-click a label to rename"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
