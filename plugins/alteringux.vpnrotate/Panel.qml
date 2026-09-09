import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Control panel for the Proton VPN rotator. Every action is delegated to
// hostWidget (the BarWidget), which owns the status file and the calls out to
// ~/.local/bin/protonvpn-rotate.
Panel {
  id: root
  moduleName: "alteringux.vpnrotate"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var st: hostWidget ? hostWidget.st : Model.parseState("")
  readonly property var cfg: hostWidget ? hostWidget.cfg : Model.defaultConfig()
  readonly property bool connected: st && st.connected
  readonly property bool busy: hostWidget ? hostWidget.busy : false
  readonly property int secsToRotate: hostWidget ? hostWidget.secsToRotate : -1

  readonly property var guard: Kit.BugGuard.create("alteringux.vpnrotate", function (argv) { Quickshell.execDetached(argv) })

  readonly property var presets: Model.intervalPresets()
  readonly property string killSwitchError: hostWidget ? hostWidget.killSwitchError : ""

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened && root.anchorItem !== null
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent

      onCloseRequested: root.close()
      onActivateRequested: {
        if (!root.hostWidget || root.busy) return
        if (root.connected) root.hostWidget.runDisconnect()
        else root.hostWidget.runConnect()
      }
      onDeleteRequested: if (root.hostWidget && root.connected && !root.busy) root.hostWidget.runDisconnect()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Kit.PanelHead {
          glyph: root.hostWidget ? root.hostWidget.icon : ""   // nf-fa-shield / sync / warning, live from the bar widget
          title: "Proton VPN"
          meta: Model.summaryLine(root.st)
          foreground: root.barForeground
        }

        // ── status detail (hint role: sentences + wrapping, per ADR 0005) ──
        Text {
          width: content.width
          visible: text.length > 0
          text: {
            if (!root.st) return ""
            if (root.st.error) return "The rotator script reported a failure. Check ~/.local/state/omarchy/vpnrotate.log"
            if (root.connected) {
              var bits = []
              if (root.st.org) bits.push(root.st.org)
              if (root.st.since > 0 && root.hostWidget) bits.push("up " + Model.shortAgo(root.st.since, root.hostWidget.nowSec).replace(" ago", ""))
              if (root.st.lastRotate > 0 && root.st.lastRotate !== root.st.since && root.hostWidget) bits.push("rotated " + Model.shortAgo(root.st.lastRotate, root.hostWidget.nowSec))
              return bits.join("  ·  ")
            }
            return ""
          }
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // Next-rotation readout + thin progress bar (only meaningful while
        // auto-rotate is armed and the tunnel is up).
        Text {
          width: content.width
          visible: root.cfg.autoRotate
          text: {
            if (!root.connected) return "Auto-rotate armed — will start after you connect"
            if (root.busy) return "Rotating…"
            if (root.secsToRotate < 0) return ""
            return "Next rotation in " + Model.formatCountdown(root.secsToRotate)
          }
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          width: content.width
          height: Style.space(6)
          radius: height / 2
          color: Util.alpha(root.barForeground, 0.18)
          visible: root.cfg.autoRotate && root.connected && root.secsToRotate >= 0

          Rectangle {
            height: parent.height
            radius: parent.radius
            width: {
              var total = root.cfg.intervalSec
              if (!(total > 0)) return 0
              var done = Math.max(0, total - Math.max(0, root.secsToRotate))
              return Math.max(parent.height, parent.width * (done / total))
            }
            color: root.barForeground
            opacity: 0.9
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
          }
        }

        PanelSeparator {}

        // ── connect / rotate ─────────────────────────────────────────────
        Row {
          spacing: Style.space(8)

          Button {
            text: root.connected ? "Disconnect" : "Connect"
            foreground: root.barForeground
            bordered: true
            enabled: root.hostWidget && !root.busy
            onClicked: {
              if (!root.hostWidget) return
              if (root.connected) root.hostWidget.runDisconnect()
              else root.hostWidget.runConnect()
            }
          }
          Button {
            text: "Rotate now"
            foreground: root.barForeground
            bordered: true
            enabled: root.hostWidget && root.connected && !root.busy
            onClicked: if (root.hostWidget) root.hostWidget.runRotate()
          }
        }

        Text {
          width: content.width
          text: "Each rotation drops open connections for a few seconds while the tunnel re-handshakes."
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator {}

        // ── auto-rotate ──────────────────────────────────────────────────
        Toggle {
          width: content.width
          activeFocusOnTab: false
          label: "Auto-rotate"
          description: root.cfg.autoRotate
            ? ("Switches server every " + Model.prettyInterval(root.cfg.intervalSec))
            : "Off — rotate manually with the button above"
          checked: root.cfg.autoRotate
          foreground: root.barForeground
          onClicked: if (root.hostWidget) root.hostWidget.toggleAutoRotate()
        }

        Text {
          width: content.width
          text: "Interval"
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        Row {
          spacing: Style.space(6)

          Repeater {
            model: root.presets
            Button {
              required property var modelData
              text: modelData.label
              foreground: root.barForeground
              bordered: root.cfg.intervalSec === modelData.sec
              onClicked: if (root.hostWidget) root.hostWidget.setIntervalSec(modelData.sec)
            }
          }
        }

        Text {
          width: content.width
          text: "A new interval takes effect on the next cycle. Proton's free tier shares a small IP pool, so this beats simple per-IP limits but not blocks on the whole VPN range."
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator {}

        // ── kill switch ──────────────────────────────────────────────────
        Toggle {
          width: content.width
          activeFocusOnTab: false
          label: "Kill switch"
          description: root.cfg.killSwitch
            ? "Internet is blocked if the tunnel drops or a reconnect fails — no real-IP leak, brief offline until it recovers"
            : "If the tunnel drops, traffic falls back to your real IP"
          checked: root.cfg.killSwitch
          foreground: root.barForeground
          onClicked: if (root.hostWidget) root.hostWidget.toggleKillSwitch()
        }

        Text {
          width: content.width
          visible: root.killSwitchError.length > 0
          text: root.killSwitchError
          color: Kit.Palette.negative
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator {}

        Text {
          text: "Enter: connect/disconnect  ·  Del: disconnect  ·  Esc: close"
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
