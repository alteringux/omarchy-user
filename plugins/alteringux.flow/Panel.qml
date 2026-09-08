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
  // Every canvas edit (move/rename/add/remove/toggleEdge) reassigns `doc` to a
  // freshly cloned object, so the node Repeater below destroys and recreates
  // every delegate on each edit — there's no stable per-node identity to diff
  // against. A delegate destroyed mid-edit skips InlineEdit's own
  // commit()/cancel(), so its onEditingChanged decrement never fires and
  // inlineEditors is left stuck above 0 forever, permanently blocking Esc /
  // close on the whole panel. Reset it here, at the one moment we know every
  // live editor is about to die anyway.
  onNodesChanged: root.inlineEditors = 0
  readonly property var edges: root.guard.call("edges", function () { return Model.edgeList(root.doc) }, [])
  readonly property var canvasBounds: root.guard.call("bounds", function () { return Model.bounds(root.doc) }, ({ w: 400, h: 300 }))

  property string tab: "output"
  property string selectedId: ""
  readonly property var selectedNode: root.selectedId ? Model.nodeById(root.doc, root.selectedId) : null

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

        // Deferred by docs/adr/0005-panel-text-hierarchy.md pending concurrent
        // work on this plugin; prepended now per the pomodoro precedent it
        // names. The toolbar row below keeps its own PanelSectionHeader —
        // PanelHero's single trailingControl can't hold four buttons.
        Kit.PanelHead {
          title: "Flow"
          meta: root.doc.id || ""
          foreground: root.barForeground
        }

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

        // Model.parseRunState already carries finishedAt; nothing showed it.
        // A silent stale "last run: (no output)" gives no clue how old that
        // output is.
        Text {
          visible: !root.runState.error && !!root.runState.finishedAt
          width: content.width
          text: "last run: " + root.runState.finishedAt
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // ================= OUTPUT =========================================
        Flickable {
          visible: root.tab === "output"
          width: content.width
          height: content.height - y
          clip: true
          contentHeight: outCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: outCol
            width: parent.width
            spacing: Style.space(12)

            Kit.EmptyState {
              visible: root.envelopes.length === 0
              text: "No output yet."
              hint: "Hit Run, or run  flow run " + (root.doc.id || "<id>") + "  in a terminal."
              foreground: root.barForeground
            }

            Repeater {
              model: root.envelopes
              delegate: Rectangle {
                required property var modelData
                readonly property var env: modelData
                width: outCol.width
                height: card.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: Util.alpha(root.barForeground, 0.05)
                border.width: 1
                border.color: Util.alpha(root.barForeground, 0.14)

                Column {
                  id: card
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(12)
                  spacing: Style.space(6)

                  Text {
                    width: parent.width
                    text: ((env.meta && env.meta.title) || env.node || "") + "  ·  " + (env.shape || "")
                    color: Kit.Palette.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  // Every shape drawn as monospace text (Model.renderEnvelopeText),
                  // the same output `flow view` prints in a terminal — no fragile
                  // nested layouts. Markdown/text wrap; series/table/log are
                  // pre-aligned so they stay in a fixed-pitch block.
                  Text {
                    width: parent.width
                    wrapMode: (env.shape === "markdown" || env.shape === "text") ? Text.WordWrap : Text.NoWrap
                    textFormat: Text.PlainText
                    text: root.guard.call("renderEnv", function () { return Model.renderEnvelopeText(env) }, "")
                    color: root.barForeground
                    font.family: (env.shape === "markdown" || env.shape === "text")
                      ? Style.font.family
                      : "monospace"
                    font.pixelSize: Style.font.bodySmall
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
                text: "Enter to save this field · drag a node to move (snaps + saves) · click a label to rename"
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
