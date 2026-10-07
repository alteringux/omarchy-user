import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The custom-pattern builder. Takes over the panel body rather than opening a
// second surface, and previews the pattern with the same Model.orbScale the
// real guides use — so what you watch here is exactly what you will breathe.
//
// Validation is Model.validateCustom's, surfaced next to the field that broke
// rather than as a lump at the bottom, and Save stays disabled while invalid.
Column {
  id: root

  property var hostWidget: null
  property color foreground: Color.foreground

  // Empty for a new pattern; a custom technique's id to edit it in place.
  property string editingId: ""

  signal closed()

  spacing: Style.space(10)

  readonly property var config: hostWidget ? hostWidget.config : Model.defaultConfig()

  // ---- the draft -------------------------------------------------------
  property string draftName: ""
  property string draftTone: "info"
  property int draftCycles: 8
  property var draftPhases: []

  readonly property var candidate: ({
    id: root.editingId,
    name: root.draftName,
    tone: root.draftTone,
    defaultCycles: root.draftCycles,
    phases: root.draftPhases
  })

  readonly property var validation: Model.validateCustom(root.candidate)
  readonly property bool valid: root.validation.ok
  // The normalised technique is what drives the preview, so the preview shows
  // the pattern as it will actually be stored, not as it was typed.
  readonly property var preview: root.validation.technique

  readonly property int cycleSeconds: Model.cycleSeconds(root.preview)

  function errorsFor(prefix) {
    var out = []
    var errors = root.validation.errors
    for (var i = 0; i < errors.length; i++) if (errors[i].indexOf(prefix) === 0) out.push(errors[i])
    return out
  }

  Component.onCompleted: root.load()

  function load() {
    var existing = root.editingId ? Model.techniqueById(root.editingId, root.config) : null
    if (existing) {
      root.draftName = existing.name
      root.draftTone = existing.tone || "info"
      root.draftCycles = existing.defaultCycles || 8
      root.draftPhases = JSON.parse(JSON.stringify(existing.phases || []))
    } else {
      root.draftName = ""
      root.draftTone = "info"
      root.draftCycles = 8
      root.draftPhases = [
        { kind: Model.PHASE.INHALE, seconds: 4, label: "Inhale" },
        { kind: Model.PHASE.EXHALE, seconds: 6, label: "Exhale" }
      ]
    }
  }

  // Most people want an existing pattern with different numbers, not a blank
  // form, so offer that as the starting point rather than making them retype it.
  function seedFrom(id) {
    var source = Model.techniqueById(id, root.config)
    if (!source) return
    root.draftName = source.name + " (mine)"
    root.draftTone = source.tone || "info"
    root.draftCycles = source.defaultCycles || 8
    root.draftPhases = JSON.parse(JSON.stringify(source.phases))
  }

  // Reassigning the whole array is what makes the bindings that read it
  // re-evaluate; mutating in place would leave the preview stale.
  function replacePhases(next) { root.draftPhases = next }

  function setPhase(index, key, value) {
    var next = JSON.parse(JSON.stringify(root.draftPhases))
    if (index < 0 || index >= next.length) return
    next[index][key] = value
    if (key === "kind" && !next[index].label) next[index].label = Model.phaseLabel(value)
    root.replacePhases(next)
  }

  function addPhase() {
    var next = JSON.parse(JSON.stringify(root.draftPhases))
    next.push({ kind: Model.PHASE.HOLD_IN, seconds: 4, label: Model.phaseLabel(Model.PHASE.HOLD_IN) })
    root.replacePhases(next)
  }

  function removePhase(index) {
    var next = []
    for (var i = 0; i < root.draftPhases.length; i++) if (i !== index) next.push(root.draftPhases[i])
    root.replacePhases(JSON.parse(JSON.stringify(next)))
  }

  function movePhase(index, delta) {
    var target = index + delta
    if (target < 0 || target >= root.draftPhases.length) return
    var next = JSON.parse(JSON.stringify(root.draftPhases))
    var held = next[index]
    next[index] = next[target]
    next[target] = held
    root.replacePhases(next)
  }

  function save() {
    if (!root.valid || !root.hostWidget) return
    root.hostWidget.saveCustomTechnique(root.validation.technique)
    root.closed()
  }

  property int inlineEditors: 0
  function anyFieldFocused() {
    if (root.inlineEditors > 0) return true
    if (cyclesField.field && cyclesField.field.activeFocus) return true
    for (var i = 0; i < phaseRepeater.count; i++) {
      var item = phaseRepeater.itemAt(i)
      if (item && item.fieldFocused) return true
    }
    return false
  }

  function toneColor(tone) {
    if (tone === "positive") return Kit.Palette.positive
    if (tone === "negative") return Kit.Palette.negative
    if (tone === "warning") return Kit.Palette.warning
    if (tone === "info") return Kit.Palette.info
    return root.foreground
  }

  // ---- name -------------------------------------------------------------
  Kit.InlineEdit {
    width: parent.width
    text: root.draftName
    foreground: root.foreground
    pixelSize: Style.font.title
    bold: true
    placeholderText: "Name your pattern"
    onEditingChanged: root.inlineEditors += editing ? 1 : -1
    onAccepted: function (value) { root.draftName = value }
  }

  Repeater {
    model: root.errorsFor("Give the pattern").concat(root.errorsFor("That name"))
    Text {
      required property var modelData
      width: parent.width
      text: modelData
      color: Kit.Palette.negative
      wrapMode: Text.WordWrap
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // ---- live preview ------------------------------------------------------
  // Runs the draft on a loop of its own so the pattern can be watched while
  // it is being edited, independently of any real session.
  Item {
    width: parent.width
    height: Style.space(110)

    property double tick: 0
    Timer {
      interval: 32
      repeat: true
      running: root.visible && root.cycleSeconds > 0
      onTriggered: parent.tick = (parent.tick + 32) % Math.max(1, root.cycleSeconds * 1000)
    }

    readonly property var pos: root.cycleSeconds > 0
      ? Model.resolve({ state: "RUNNING", cycles: 1, savedAtMs: 0, elapsedMs: tick }, root.preview, 0)
      : null

    Rectangle {
      anchors.centerIn: parent
      visible: parent.pos !== null
      width: Style.space(80) * (parent.pos ? parent.pos.orbScale : Model.SCALE_MIN)
      height: width
      radius: width / 2
      color: {
        var c = root.toneColor(root.draftTone)
        return Qt.rgba(c.r, c.g, c.b, 0.24)
      }
      border.width: 1.5
      border.color: root.toneColor(root.draftTone)
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      text: parent.pos ? parent.pos.phaseLabel : "Add a phase to preview it"
      color: parent.pos ? root.foreground : Kit.Palette.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // ---- derived readout ---------------------------------------------------
  Text {
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: {
      if (root.cycleSeconds <= 0) return ""
      return root.preview.pattern + "  ·  " + Model.formatDuration(root.cycleSeconds) + " per cycle"
        + "  ·  " + Model.formatDuration(root.cycleSeconds * root.draftCycles) + " total"
    }
    color: Kit.Palette.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.1
  }

  // ---- phases ------------------------------------------------------------
  Kit.SectionHeading { width: parent.width; text: "Phases" }

  Repeater {
    id: phaseRepeater
    model: root.draftPhases

    Column {
      id: phaseRow
      required property var modelData
      required property int index
      readonly property bool fieldFocused: secondsField.field && secondsField.field.activeFocus

      width: parent.width
      spacing: Style.space(3)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(16)
          text: String(phaseRow.index + 1)
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Dropdown {
          id: kindDrop
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(124)
          showLabel: false
          options: [
            Model.PHASE.INHALE, Model.PHASE.HOLD_IN, Model.PHASE.EXHALE, Model.PHASE.HOLD_OUT,
            Model.PHASE.INHALE_TOP, Model.PHASE.RETENTION, Model.PHASE.RECOVERY,
            Model.PHASE.SWITCH, Model.PHASE.POWER_BREATHS
          ]
          value: phaseRow.modelData.kind
          onValueChanged: if (value !== phaseRow.modelData.kind) root.setPhase(phaseRow.index, "kind", value)
        }

        NumberField {
          id: secondsField
          anchors.verticalCenter: parent.verticalCenter
          label: ""
          value: Math.round(phaseRow.modelData.seconds || 0)
          from: 1
          to: 300
          foreground: root.foreground
          onModified: function (v) { root.setPhase(phaseRow.index, "seconds", v) }
        }

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""                    // fa-angle-up
          tooltipText: "Move up"
          foreground: root.foreground
          onClicked: root.movePhase(phaseRow.index, -1)
        }
        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""                    // fa-angle-down
          tooltipText: "Move down"
          foreground: root.foreground
          onClicked: root.movePhase(phaseRow.index, 1)
        }
        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""                    // fa-times
          tooltipText: "Remove this phase"
          foreground: Kit.Palette.negative
          onClicked: root.removePhase(phaseRow.index)
        }
      }

      // The error for this exact phase, next to this exact phase.
      Repeater {
        model: root.errorsFor("Phase " + (phaseRow.index + 1))
        Text {
          required property var modelData
          width: phaseRow.width
          text: modelData
          color: Kit.Palette.negative
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    Button {
      text: "  Add phase"
      bordered: true
      foreground: root.foreground
      onClicked: root.addPhase()
    }
  }

  Repeater {
    model: root.errorsFor("Add at least").concat(root.errorsFor("One cycle is"))
    Text {
      required property var modelData
      width: parent.width
      text: modelData
      color: Kit.Palette.negative
      wrapMode: Text.WordWrap
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // ---- cycles and tone ---------------------------------------------------
  NumberField {
    id: cyclesField
    label: "Cycles"
    value: root.draftCycles
    from: 1
    to: 99
    foreground: root.foreground
    onModified: function (v) { root.draftCycles = v }
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(60)
      text: "Colour"
      color: root.foreground
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: ["info", "positive", "warning", "negative", "neutral"]
      Rectangle {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(22)
        height: width
        radius: width / 2
        color: root.toneColor(modelData)
        opacity: root.draftTone === modelData ? 1 : 0.35
        border.width: root.draftTone === modelData ? 2 : 0
        border.color: root.foreground

        MouseArea {
          anchors.fill: parent
          onClicked: root.draftTone = modelData
        }
      }
    }
  }

  // ---- start from a built-in --------------------------------------------
  Column {
    width: parent.width
    visible: root.editingId === ""
    spacing: Style.space(4)

    Text {
      width: parent.width
      text: "Or start from an existing pattern"
      color: Kit.Palette.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width
      spacing: Style.space(5)

      Repeater {
        model: Model.TECHNIQUES
        Button {
          required property var modelData
          text: modelData.name
          bordered: true
          fontSize: Style.font.caption
          foreground: root.toneColor(modelData.tone)
          onClicked: root.seedFrom(modelData.id)
        }
      }
    }
  }

  PanelSeparator { width: parent.width; foreground: root.foreground }

  // ---- commit ------------------------------------------------------------
  Row {
    width: parent.width
    spacing: Style.space(8)

    Button {
      text: "Save"
      bordered: true
      foreground: root.valid ? Kit.Palette.positive : Kit.Palette.faint
      opacity: root.valid ? 1 : 0.5
      onClicked: root.save()
    }
    Button {
      text: "Cancel"
      bordered: true
      foreground: root.foreground
      onClicked: root.closed()
    }
    Button {
      text: "Delete"
      bordered: true
      visible: root.editingId !== ""
      foreground: Kit.Palette.negative
      onClicked: {
        if (root.hostWidget) root.hostWidget.deleteCustomTechnique(root.editingId)
        root.closed()
      }
    }
  }
}
