import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "../alteringux.kit" as Kit

// Bottom Bar service: a persistent layer-shell strip on the bottom edge of
// every monitor (same PanelWindow contract as alteringux.newsbar — themed,
// per-screen, reserves space with an exclusion zone). Its job is to host bar
// widgets the top bar has run out of horizontal room for.
//
// It loads the real BarWidget.qml of each hosted plugin straight from that
// plugin's own directory and hands it a BarShim in place of the shell's Bar.
// The widget's label, wheel/click handlers, IpcHandler and its KeyboardPanel
// popup all work unchanged — the popup is its own Overlay-layer surface that
// positions itself off `bar.position` ("bottom" here).
//
// Because these widgets are instantiated HERE, they must NOT also appear in
// shell.json's top-bar layout, or their IpcHandlers double-register.
Item {
  id: root

  // Injected by the omarchy-shell host for service plugins.
  property string omarchyPath: ""
  property var shell: null
  property var pluginRegistry: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginsDir: home + "/.config/omarchy/plugins"
  readonly property int barSize: Math.max(20, Style.bar.sizeHorizontal)

  // Hosted widgets. `src` is the plugin's real bar-widget entry point; loading
  // it by absolute path keeps its relative imports ("Model.js",
  // "../alteringux.kit") resolving against the plugin dir.
  //
  // Two zones: `leftSpecs` pack from the left edge; `rightSpecs` pack against
  // the right edge (like alteringux.newsbar's split), so a wide marquee like
  // countdown gets the whole right side of the strip to itself.
  readonly property var leftSpecs: [
    { id: "alteringux.pomodoro",  src: root.pluginsDir + "/alteringux.pomodoro/BarWidget.qml" },
    { id: "alteringux.stopwatch", src: root.pluginsDir + "/alteringux.stopwatch/BarWidget.qml" },
    { id: "alteringux.timers",    src: root.pluginsDir + "/alteringux.timers/BarWidget.qml" },
    { id: "alteringux.grip",      src: root.pluginsDir + "/alteringux.grip/BarWidget.qml" },
    { id: "alteringux.stocks",    src: root.pluginsDir + "/alteringux.stocks/BarWidget.qml" },
    { id: "alteringux.score",     src: root.pluginsDir + "/alteringux.score/BarWidget.qml" },
    { id: "alteringux.conductor", src: root.pluginsDir + "/alteringux.conductor/BarWidget.qml" }
  ]
  readonly property var rightSpecs: [
    { id: "alteringux.flow",      src: root.pluginsDir + "/alteringux.flow/BarWidget.qml" },
    { id: "alteringux.cliamp",    src: root.pluginsDir + "/alteringux.cliamp/BarWidget.qml" },
    { id: "alteringux.countdown", src: root.pluginsDir + "/alteringux.countdown/BarWidget.qml" }
  ]
  readonly property var widgetSpecs: root.leftSpecs.concat(root.rightSpecs)

  property var widgetStates: ({})

  function noteWidget(id, loaded) {
    var next = {}
    for (var k in root.widgetStates) next[k] = root.widgetStates[k]
    next[id] = loaded
    root.widgetStates = next
  }

  readonly property var guard: Kit.BugGuard.create("alteringux.bottombar", function (argv) { Quickshell.execDetached(argv) })

  // ---- hide flags ------------------------------------------------------
  // Presence of a flag file = hidden. We track our own (`bottombar-off`) and
  // the top bar's (`bar-off`, flipped by `omarchy toggle bar`) so hiding the
  // top bar hides this one too. FileView can't watch a not-yet-existing
  // file, so watch the parent toggles directory + a slow re-probe (same
  // caveat the stock Bar.qml and alteringux.newsbar document).
  readonly property string togglesDir: home + "/.local/state/omarchy/toggles"
  readonly property string ownFlagPath: togglesDir + "/bottombar-off"
  readonly property string topBarFlagPath: togglesDir + "/bar-off"
  property bool ownHidden: false
  property bool topBarHidden: false
  readonly property bool hidden: ownHidden || topBarHidden

  function setHidden(value) {
    var next = value === true
    root.ownHidden = next
    Quickshell.execDetached(["bash", "-c", next
      ? "mkdir -p " + togglesDir + " && touch " + ownFlagPath
      : "rm -f " + ownFlagPath])
  }

  Process {
    id: hiddenProbe
    running: false
    command: ["bash", "-c",
      "own=no; top=no; " +
      "[[ -f " + root.ownFlagPath + " ]] && own=yes; " +
      "[[ -f " + root.topBarFlagPath + " ]] && top=yes; " +
      "echo \"$own $top\""]
    stdout: SplitParser { onRead: function (line) {
      var p = String(line).trim().split(/\s+/)
      root.ownHidden = p[0] === "yes"
      root.topBarHidden = p[1] === "yes"
    } }
  }

  FileView {
    path: root.togglesDir
    watchChanges: true
    printErrors: false
    onFileChanged: hiddenProbe.running = true
  }

  Timer {
    interval: 3000
    repeat: true
    running: true
    onTriggered: if (!hiddenProbe.running) hiddenProbe.running = true
  }

  Component.onCompleted: hiddenProbe.running = true

  IpcHandler {
    target: "alteringux.bottombar"

    function ping(): string { return "ok" }
    function show(): void { root.setHidden(false) }
    function hide(): void { root.setHidden(true) }
    function toggle(): void { root.setHidden(!root.ownHidden) }
    function status(): string {
      return root.guard.call("ipc.status", function () {
        return JSON.stringify({
          hidden: root.hidden,
          ownHidden: root.ownHidden,
          topBarHidden: root.topBarHidden,
          widgets: root.widgetSpecs.map(function (w) {
            var s = root.widgetStates[w.id]
            if (s === true) return w.id
            if (s === false) return w.id + " (failed)"
            return w.id + " (pending)"
          })
        })
      }, "{}")
    }
  }

  // ------------------------------------------------------------- the bar(s)
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData

        screen: modelData
        visible: !root.hidden
        exclusionMode: ExclusionMode.Auto
        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "alteringux-bottombar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors { bottom: true; left: true; right: true }
        implicitHeight: root.barSize

        BarShim {
          id: shim
          barSize: root.barSize
        }

        Rectangle {
          anchors.fill: parent
          color: Color.bar.background

          // Hairline along the top edge, echoing the top bar's weight.
          Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Qt.rgba(Color.bar.text.r, Color.bar.text.g, Color.bar.text.b, 0.12)
          }

          // One hosted bar widget. The Loader gives the widget its height
          // (full bar) and takes its width from the widget's own
          // implicitWidth, exactly as a top-bar ModuleSlot would. Shared by
          // both zones — it reads `shim` from this file's scope.
          Component {
            id: widgetSlot

            Loader {
              required property var modelData
              height: parent ? parent.height : root.barSize
              width: item ? Math.max(1, item.implicitWidth) : 0
              asynchronous: false
              source: modelData.src

              onLoaded: {
                if (!item) return
                if ("bar" in item) item.bar = shim
                root.noteWidget(modelData.id, true)
              }
              // Loader has no dedicated "load failed" signal — Loader.Error
              // is one of the four Loader.status values, so watch for it via
              // onStatusChanged instead (an onLoadingFailed handler doesn't
              // exist on this type and is a hard QML load-time error).
              onStatusChanged: if (status === Loader.Error) root.noteWidget(modelData.id, false)
            }
          }

          // Left zone: pack from the left edge.
          Row {
            id: hostRow
            anchors {
              left: parent.left; top: parent.top; bottom: parent.bottom
              leftMargin: Style.space(8)
            }
            spacing: 0

            Repeater {
              model: root.leftSpecs
              delegate: widgetSlot
            }
          }

          // Right zone: pack against the right edge.
          Row {
            id: tailRow
            anchors {
              right: parent.right; top: parent.top; bottom: parent.bottom
              rightMargin: Style.space(8)
            }
            spacing: 0

            Repeater {
              model: root.rightSpecs
              delegate: widgetSlot
            }
          }
        }
      }
    }
  }
}
