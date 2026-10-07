import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// Transport panel for cliamp. Everything acts on hostWidget (the BarWidget),
// which owns the status poll and shells out to `cliamp ...`.
Panel {
  id: root
  moduleName: "alteringux.cliamp"
  ipcTarget: ""

  property var anchorItem: null
  property var hostWidget: null

  readonly property var status: hostWidget ? hostWidget.status : Model.emptyStatus()
  readonly property bool running: status && status.running === true
  readonly property bool playing: status && status.playing === true
  readonly property var bands: hostWidget ? hostWidget.bands : []

  readonly property var guard: Kit.BugGuard.create("alteringux.cliamp", function (argv) { Quickshell.execDetached(argv) })

  // Visualizer modes. Seeded with the built-ins and refreshed from
  // `cliamp vis list` whenever the panel opens (cliamp may add modes).
  property var visModes: ["Bars", "BarsDot", "BarsOutline", "Wave", "Scope",
                          "ClassicPeak", "Pulse", "Heartbeat", "Matrix", "None"]

  Process {
    id: visListProc
    command: ["/usr/bin/cliamp", "vis", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var names = []
        var lines = String(text).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var n = lines[i].replace(/^[*\s]+/, "").trim()
          if (n.length) names.push(n)
        }
        if (names.length) root.visModes = names
      }
    }
  }

  onOpenedChanged: if (opened && !visListProc.running) visListProc.running = true

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
      blocked: visDropdown.popupOpen

      onCloseRequested: root.close()
      onActivateRequested: if (root.hostWidget) root.hostWidget.playPause()
      onDeleteRequested: if (root.hostWidget) root.hostWidget.stopPlayback()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Kit.PanelHead {
          glyph: "\uf001"   // nf-fa-music
          title: "cliamp"
          meta: Model.stateMeta(root.status)
          foreground: root.barForeground
        }

        // Now playing.
        Text {
          visible: root.running
          width: content.width
          text: root.status.label && root.status.label.length ? root.status.label : "—"
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        // Wave synthesiser — a wider mirror of the bar strip.
        Row {
          id: bigViz
          visible: root.running
          width: content.width
          height: Style.space(44)
          spacing: Math.max(1, (content.width - Model.BAND_COUNT * Style.spaceReal(10)) / (Model.BAND_COUNT - 1))

          Repeater {
            model: Model.BAND_COUNT
            delegate: Rectangle {
              required property int index
              width: Style.spaceReal(10)
              radius: width / 2
              color: root.barForeground
              opacity: root.playing ? 0.9 : 0.35
              anchors.verticalCenter: parent.verticalCenter
              height: Math.max(Style.spaceReal(3),
                               (root.bands[index] || 0) * bigViz.height)
              Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
          }
        }

        // Progress. Click to seek (best-effort; disabled for live streams
        // with no known total).
        Rectangle {
          visible: root.running
          width: content.width
          height: Style.space(6)
          radius: height / 2
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.18)

          Rectangle {
            height: parent.height
            radius: parent.radius
            width: Math.max(parent.height, parent.width * Model.progressFraction(root.status.position, root.status.total))
            color: root.barForeground
            opacity: root.playing ? 0.9 : 0.5
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
          }

          MouseArea {
            anchors.fill: parent
            enabled: root.status.total > 0
            onClicked: function (mouse) {
              if (root.hostWidget && root.status.total > 0)
                root.hostWidget.seekTo(mouse.x / width * root.status.total)
            }
          }
        }

        Text {
          visible: root.running && root.status.total > 0
          width: content.width
          text: Model.formatTime(root.status.position) + "  /  " + Model.formatTime(root.status.total)
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator {}

        // Transport.
        Row {
          spacing: Style.space(8)

          Button {
            text: "Prev"
            foreground: root.barForeground
            bordered: true
            enabled: root.running
            onClicked: if (root.hostWidget) root.hostWidget.prev()
          }
          Button {
            text: root.playing ? "Pause" : "Play"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.playPause()
          }
          Button {
            text: "Next"
            foreground: root.barForeground
            bordered: true
            enabled: root.running
            onClicked: if (root.hostWidget) root.hostWidget.next()
          }
          Button {
            text: "Stop"
            foreground: root.barForeground
            bordered: true
            enabled: root.running
            onClicked: if (root.hostWidget) root.hostWidget.stopPlayback()
          }
        }

        // Volume — cliamp adjusts in dB, relative.
        Row {
          spacing: Style.space(8)
          visible: root.running

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Volume"
             color: root.barForeground
             opacity: 0.6
             font.family: Style.font.family
             font.pixelSize: Style.font.bodySmall
          }
          Button {
            text: "-2 dB"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.nudgeVolume(-2)
          }
          Button {
            text: "+2 dB"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.nudgeVolume(2)
          }
        }

        PanelSeparator { visible: root.running }

        Toggle {
          width: content.width
          activeFocusOnTab: false
          visible: root.running
          label: "Shuffle"
          description: root.status.shuffle ? "On" : "Off"
          checked: root.status.shuffle
          foreground: root.barForeground
          onClicked: if (root.hostWidget) root.hostWidget.toggleShuffle()
        }

        Row {
          spacing: Style.space(8)
          visible: root.running

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Repeat"
             color: root.barForeground
             opacity: 0.6
             font.family: Style.font.family
             font.pixelSize: Style.font.bodySmall
          }
          Button {
            text: root.status.repeat && root.status.repeat.length ? root.status.repeat : "Off"
            foreground: root.barForeground
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.cycleRepeat()
          }
        }

        // Visualiser mode.
        Kit.MetaText {
          visible: root.running
          width: content.width
          content: "Visualiser"
          foreground: root.barForeground
        }

        Dropdown {
          id: visDropdown
          visible: root.running
          width: content.width
          showLabel: false
          activeFocusOnTab: false
          options: root.visModes
          value: root.status.visualizer || "Bars"
          foreground: root.barForeground
          onChanged: function (v) { if (root.hostWidget) root.hostWidget.setVis(v) }
        }

        // Not running: offer to start it.
        Kit.EmptyState {
          visible: !root.running
          width: content.width
          foreground: root.barForeground
          text: "cliamp isn't running"
          hint: "Start it in a terminal to control playback from here."
        }

        Button {
          visible: !root.running
          text: "Launch cliamp"
          foreground: root.barForeground
          bordered: true
          onClicked: if (root.hostWidget) root.hostWidget.launch()
        }

        Text {
          text: "Space: play/pause  ·  X: stop  ·  Esc: close"
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
