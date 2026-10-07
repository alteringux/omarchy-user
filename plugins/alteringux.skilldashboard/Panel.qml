import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit
Panel {
  id: root; moduleName: "alteringux.skilldashboard"; ipcTarget: ""; property var anchorItem: null; property var hostWidget: null; property bool productOnly: false
  readonly property var state: hostWidget ? hostWidget.state : Model.defaults()
  readonly property var rows: productOnly ? state.skills.filter(function (s) { return s.id === "product-teardown" || (s.name || "").toLowerCase().indexOf("product-teardown") >= 0 }) : state.skills
  function act(verb, skill) { if (hostWidget) hostWidget.runSkillAction(verb, skill) }
  KeyboardPanel { id: panel; anchorItem: root.anchorItem; owner: root; bar: root.bar; open: root.opened
    Kit.PanelScroll { anchors.fill: parent; contentHeight: content.implicitHeight
      Column { id: content; width: parent.width; spacing: Style.spacing.panelGap
        Kit.PanelHead { title: "Skill Dashboard"; meta: root.state.generatedAt || "not refreshed"; foreground: root.barForeground; trailingControl: Component { Button { text: "Refresh"; foreground: root.barForeground; bordered: true; onClicked: if (hostWidget) hostWidget.runRefresh() } } }
        RowLayout { width: parent.width; Text { text: (root.state.summary.total || 0) + " skills · " + (root.state.summary.actionNeeded || 0) + " need action"; color: root.barForeground; Layout.fillWidth: true }; Button { text: root.productOnly ? "All skills" : "Product teardown"; foreground: root.barForeground; bordered: true; onClicked: root.productOnly = !root.productOnly } }
        Repeater { model: root.rows; delegate: RowLayout { required property var modelData; width: content.width; Text { text: modelData.name || modelData.id; color: root.barForeground; Layout.fillWidth: true; elide: Text.ElideRight }; Text { text: modelData.stale ? "stale" : ((modelData.uses || 0) + " uses"); color: modelData.stale ? Color.urgent : Kit.Palette.faint }; Button { visible: modelData.owned && modelData.status === "active"; text: "Ack"; foreground: root.barForeground; bordered: true; onClicked: root.act("acknowledge", modelData) }; Button { visible: modelData.owned && modelData.status === "active"; text: "Disable"; foreground: root.barForeground; bordered: true; onClicked: root.act("disable", modelData) }; Button { visible: modelData.owned && modelData.status === "disabled"; text: "Enable"; foreground: root.barForeground; bordered: true; onClicked: root.act("enable", modelData) }; Button { visible: modelData.owned && modelData.status !== "deprecated"; text: "Deprecate"; foreground: root.barForeground; bordered: true; onClicked: root.act("deprecate", modelData) }; Button { visible: modelData.owned; text: "Remove"; foreground: root.barForeground; bordered: true; onClicked: root.act("remove", modelData) } } }
        Text { visible: root.rows.length === 0; text: "No matching skills."; color: Kit.Palette.faint }
      }
    }
  }
}
