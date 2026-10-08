import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

Panel {
  id: root
  moduleName: "alteringux.skilldashboard"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null
  property bool productOnly: false
  property string expandedSkillId: ""
  property string pendingRemoveId: ""

  readonly property var state: hostWidget ? hostWidget.state : Model.defaults()
  readonly property var rows: productOnly
    ? state.skills.filter(function(skill) {
        return skill.id === "product-teardown"
          || (skill.name || "").toLowerCase().indexOf("product-teardown") >= 0
      })
    : state.skills

  function open() { root.controller.show() }
  function close() {
    root.pendingRemoveId = ""
    root.expandedSkillId = ""
    root.controller.hide()
  }
  function toggle() { root.opened ? root.close() : root.open() }
  function act(verb, skill) {
    if (hostWidget) hostWidget.runSkillAction(verb, skill)
  }

  Kit.KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Kit.PanelKeys {
      id: keyCatcher
      anchors.fill: parent
      shortcutContext: "Skill Dashboard · shortcut focus"
      onCloseRequested: root.close()

      Kit.PanelScroll {
        anchors.fill: parent
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          Kit.PanelHead {
            title: "Skill Dashboard"
            meta: root.hostWidget && root.hostWidget.refreshing
              ? "Refreshing"
              : (root.state.generatedAt || "Not refreshed")
            foreground: root.barForeground
            trailingControl: Component {
              Kit.ActionButton {
                text: root.hostWidget && root.hostWidget.refreshing ? "Refreshing…" : "Refresh"
                enabled: !root.hostWidget || !root.hostWidget.refreshing
                Accessible.name: "Refresh skill dashboard"
                Accessible.description: "Reload local skill usage and lifecycle state."
                onClicked: if (root.hostWidget) root.hostWidget.runRefresh()
              }
            }
          }

          RowLayout {
            width: parent.width

            Text {
              Layout.fillWidth: true
              text: (root.state.summary.total || 0) + " skills · "
                + (root.state.summary.actionNeeded || 0) + " need action"
              color: root.barForeground
              wrapMode: Text.WordWrap
            }

            Kit.ActionButton {
              text: root.productOnly ? "All skills" : "Product teardown"
              Accessible.name: root.productOnly
                ? "Show all skills"
                : "Filter to the product-teardown skill"
              onClicked: {
                root.pendingRemoveId = ""
                root.expandedSkillId = ""
                root.productOnly = !root.productOnly
              }
            }
          }

          Text {
            visible: !!(root.hostWidget && root.hostWidget.actionStatus)
            width: content.width
            text: root.hostWidget ? root.hostWidget.actionStatus : ""
            color: root.hostWidget && root.hostWidget.actionFailed
              ? Kit.Palette.negative : Kit.Palette.faint
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          Text {
            visible: !!(root.hostWidget && root.hostWidget.refreshStatus)
            width: content.width
            text: root.hostWidget ? root.hostWidget.refreshStatus : ""
            color: Kit.Palette.negative
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          Repeater {
            model: root.rows

            delegate: ColumnLayout {
              id: skillRow
              required property var modelData
              property string skillName: modelData.name || modelData.id
              property bool actionsExpanded: root.expandedSkillId === modelData.id
              width: content.width
              spacing: Style.space(4)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  text: skillRow.skillName
                  color: root.barForeground
                  elide: Text.ElideRight
                  Accessible.role: Accessible.StaticText
                  Accessible.name: text
                }

                Text {
                  text: modelData.status === "removed" ? "removed · recoverable"
                    : (modelData.stale ? "stale" : ((modelData.uses || 0) + " uses"))
                  color: modelData.status === "removed" ? Kit.Palette.warning
                    : (modelData.stale ? Color.urgent : Kit.Palette.faint)
                  Accessible.role: Accessible.StaticText
                  Accessible.name: text
                }

                Kit.ActionButton {
                  visible: modelData.owned && modelData.status === "removed"
                  text: "Restore"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: "Restore " + skillRow.skillName
                  Accessible.description: "Move this skill back to its original user-owned location."
                  onClicked: root.act("restore", modelData)
                }

                Kit.ActionButton {
                  visible: modelData.owned && modelData.status !== "removed"
                  text: skillRow.actionsExpanded ? "Done" : "Actions"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: (skillRow.actionsExpanded ? "Hide" : "Show")
                    + " lifecycle actions for " + skillRow.skillName
                  onClicked: {
                    root.pendingRemoveId = ""
                    root.expandedSkillId = skillRow.actionsExpanded ? "" : modelData.id
                  }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                visible: modelData.status !== "removed"

                Text {
                  Layout.fillWidth: true
                  text: modelData.lastAt
                    ? "Last used " + new Date(modelData.lastAt).toLocaleDateString()
                    : "Never used"
                  color: Kit.Palette.faint
                  Accessible.role: Accessible.StaticText
                  Accessible.name: text
                }

                Text {
                  text: modelData.owned ? "User owned" : "Managed"
                  color: Kit.Palette.faint
                  Accessible.role: Accessible.StaticText
                  Accessible.name: text
                }
              }

              Flow {
                Layout.fillWidth: true
                visible: skillRow.actionsExpanded && modelData.owned
                  && modelData.status !== "removed"
                spacing: Style.space(6)

                Kit.ActionButton {
                  visible: modelData.status === "active" && modelData.stale
                    && !modelData.acknowledgedAt
                  text: "Acknowledge"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: "Acknowledge stale skill " + skillRow.skillName
                  onClicked: root.act("acknowledge", modelData)
                }

                Kit.ActionButton {
                  visible: modelData.status === "active"
                  text: "Disable"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: "Disable skill " + skillRow.skillName
                  onClicked: root.act("disable", modelData)
                }

                Kit.ActionButton {
                  visible: modelData.status === "disabled"
                  text: "Enable"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: "Enable skill " + skillRow.skillName
                  onClicked: root.act("enable", modelData)
                }

                Kit.ActionButton {
                  visible: modelData.status !== "deprecated"
                    && modelData.status !== "removed"
                  text: "Deprecate"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: "Deprecate skill " + skillRow.skillName
                  onClicked: root.act("deprecate", modelData)
                }

                Kit.ActionButton {
                  visible: modelData.status !== "removed"
                  text: root.pendingRemoveId === modelData.id ? "Confirm remove" : "Remove"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: root.pendingRemoveId === modelData.id
                    ? "Confirm removal of " + skillRow.skillName
                    : "Remove skill " + skillRow.skillName
                  Accessible.description: root.pendingRemoveId === modelData.id
                    ? "Moves this user-owned skill to recoverable trash."
                    : "Requires a second activation. The skill can be restored afterward."
                  onClicked: {
                    if (root.pendingRemoveId === modelData.id) {
                      root.pendingRemoveId = ""
                      root.act("remove", modelData)
                    } else {
                      root.pendingRemoveId = modelData.id
                    }
                  }
                }

                Kit.ActionButton {
                  visible: root.pendingRemoveId === modelData.id
                  text: "Cancel"
                  enabled: !root.hostWidget || !root.hostWidget.actionRunning
                  Accessible.name: "Cancel removal of " + skillRow.skillName
                  onClicked: root.pendingRemoveId = ""
                }
              }

              Rectangle {
                Layout.fillWidth: true
                height: Style.spacing.hairline
                color: Kit.Palette.muted
                opacity: 0.35
              }
            }
          }

          Kit.EmptyState {
            visible: root.rows.length === 0
            width: content.width
            text: "No matching skills."
            hint: root.productOnly ? "Choose All skills to clear the filter." : "Refresh to discover local skills."
            foreground: root.barForeground
          }
        }
      }
    }
  }
}
