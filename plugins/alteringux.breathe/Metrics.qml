import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// The metrics block of the breathe panel: what you actually did, rendered so
// it can be read at a glance rather than parsed. Every figure comes from a
// pure reducer in Model.js over the watched stats/history stores, so this file
// only decides how to draw them.
//
// It is a Column so the host panel can drop it straight into its own content
// column and let implicitHeight do the work.
Column {
  id: root

  property var hostWidget: null
  property color foreground: Color.foreground

  readonly property var stats: hostWidget ? hostWidget.stats : Model.defaultStats()
  readonly property var history: hostWidget ? hostWidget.history : Model.defaultHistory()
  readonly property var config: hostWidget ? hostWidget.config : Model.defaultConfig()
  property double nowMs: Date.now()

  readonly property var week: Model.dailyBuckets(root.stats, 7, root.nowMs)
  readonly property var streak: Model.streakOf(root.stats)
  readonly property var lifetime: Model.totals(root.stats)
  readonly property var breakdown: Model.techniqueBreakdown(root.history, 30, root.nowMs, root.config)
  readonly property var heatmap: Model.hourHeatmap(root.history, 30, root.nowMs)
  readonly property var completion: Model.completionRate(root.history, 30, root.nowMs)
  readonly property var suggestion: Model.suggestTechnique(root.history, root.stats, root.nowMs, root.config)

  readonly property var todayBucket: root.week.length ? root.week[root.week.length - 1] : { sessions: 0, seconds: 0, cycles: 0 }
  readonly property int weekSeconds: {
    var total = 0
    for (var i = 0; i < root.week.length; i++) total += root.week[i].seconds
    return total
  }
  readonly property bool hasData: root.lifetime.sessions > 0

  // Re-derive when the day rolls over or a session lands, so an open panel
  // does not keep showing yesterday's "today".
  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  readonly property color dim: Qt.darker(root.foreground, 1.4)

  function toneColor(tone) {
    if (tone === "positive") return Kit.Palette.positive
    if (tone === "negative") return Kit.Palette.negative
    if (tone === "warning") return Kit.Palette.warning
    if (tone === "info") return Kit.Palette.info
    return root.foreground
  }

  spacing: Style.space(12)

  // ---- nothing yet -------------------------------------------------------
  Kit.EmptyState {
    width: parent.width
    visible: !root.hasData
    foreground: root.foreground
    text: "No sessions yet"
    hint: "Pick a technique above — box breathing for eight cycles takes about two minutes."
  }

  // ---- the headline numbers ---------------------------------------------
  Row {
    width: parent.width
    visible: root.hasData
    spacing: Style.space(8)

    Repeater {
      model: [
        { label: "Today",     value: Model.formatDuration(root.todayBucket.seconds),
          sub: root.todayBucket.sessions + (root.todayBucket.sessions === 1 ? " session" : " sessions"),
          tint: root.foreground },
        { label: "This week", value: Model.formatDuration(root.weekSeconds),
          sub: "7 days", tint: root.foreground },
        { label: "Streak",    value: root.streak.current + "d",
          sub: "best " + root.streak.best + "d",
          tint: root.streak.current > 0 ? Kit.Palette.positive : root.dim }
      ]

      Rectangle {
        required property var modelData
        width: (root.width - Style.space(16)) / 3
        height: tile.implicitHeight + Style.space(18)
        radius: Style.cornerRadius
        color: Kit.Palette.cardBg
        border.width: 1
        border.color: Kit.Palette.cardBorder

        Column {
          id: tile
          anchors.centerIn: parent
          width: parent.width - Style.space(16)
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: modelData.label.toUpperCase()
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: modelData.value
            color: modelData.tint
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: modelData.sub
            color: Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // ---- the last seven days ----------------------------------------------
  Column {
    width: parent.width
    visible: root.hasData
    spacing: Style.space(6)

    Kit.SectionHeading {
      width: parent.width
      text: "Last 7 days"
    }

    Row {
      id: weekRow
      width: parent.width
      height: Style.space(56)
      spacing: Style.space(6)

      // Addressed by id rather than through `parent`: a Repeater reparents its
      // delegates to its own parent, so `parent.parent` here happens to work
      // but silently depends on that. An id says what is meant.
      readonly property int peak: {
        var max = 1
        for (var i = 0; i < root.week.length; i++) max = Math.max(max, root.week[i].seconds)
        return max
      }

      Repeater {
        model: root.week
        Item {
          required property var modelData
          required property int index
          width: (weekRow.width - Style.space(6) * 6) / 7
          height: weekRow.height

          // Bars grow from the baseline, so an empty day is a visible gap
          // rather than a missing column.
          Rectangle {
            anchors.bottom: dayLabel.top
            anchors.bottomMargin: Style.space(4)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            radius: Style.cornerRadius > 0 ? Math.min(3, Style.cornerRadius) : 0
            height: Math.max(2, (weekRow.height - Style.space(18)) * (modelData.seconds / weekRow.peak))
            color: modelData.seconds > 0 ? Kit.Palette.info : Kit.Palette.faint
            opacity: modelData.seconds > 0 ? (index === 6 ? 1 : 0.75) : 0.3

            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          }

          Text {
            id: dayLabel
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            // Single letter: seven three-letter labels wrap badly in a narrow
            // panel, and the shape of the week is what is being read here.
            text: new Date(modelData.date + "T00:00:00").toLocaleDateString(Qt.locale(), "ddd").charAt(0)
            color: index === 6 ? root.foreground : Kit.Palette.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: index === 6
          }
        }
      }
    }
  }

  // ---- which techniques ---------------------------------------------------
  Column {
    width: parent.width
    visible: root.hasData && root.breakdown.length > 0
    spacing: Style.space(6)

    Kit.SectionHeading {
      width: parent.width
      text: "Techniques · 30 days"
    }

    Repeater {
      model: root.breakdown.slice(0, 6)

      Item {
        required property var modelData
        width: parent.width
        height: Style.space(30)

        Text {
          id: techName
          anchors.left: parent.left
          anchors.top: parent.top
          width: parent.width * 0.42
          text: modelData.name
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          anchors.right: parent.right
          anchors.top: parent.top
          text: Model.formatDuration(modelData.seconds) + " · " + Math.round(modelData.pct * 100) + "%"
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // A proportional bar in the technique's own tone, so the colour that
        // identifies a technique in the picker identifies it here too.
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          height: Math.max(3, Style.spaceReal(3))
          radius: height / 2
          color: Kit.Palette.faint
          opacity: 0.28
        }
        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          height: Math.max(3, Style.spaceReal(3))
          width: Math.max(3, parent.width * modelData.pct)
          radius: height / 2
          color: root.toneColor(modelData.tone)
          Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }
      }
    }
  }

  // ---- when ---------------------------------------------------------------
  Column {
    width: parent.width
    visible: root.hasData
    spacing: Style.space(6)

    Kit.SectionHeading {
      width: parent.width
      text: "When you breathe"
    }

    // Twenty-four cells, one per hour. This is the figure that turns a nudge
    // schedule from a guess into a decision, which is why it earns the space.
    Row {
      id: hourRow
      width: parent.width
      spacing: 2

      readonly property int peak: {
        var max = 1
        for (var i = 0; i < root.heatmap.length; i++) max = Math.max(max, root.heatmap[i])
        return max
      }

      Repeater {
        model: 24
        Rectangle {
          required property int index
          readonly property int count: root.heatmap[index] || 0
          width: (hourRow.width - 2 * 23) / 24
          height: Style.space(18)
          radius: Style.cornerRadius > 0 ? 2 : 0
          color: count > 0 ? Kit.Palette.info : Kit.Palette.faint
          opacity: count > 0 ? (0.25 + 0.75 * (count / hourRow.peak)) : 0.14
        }
      }
    }

    Row {
      width: parent.width
      Repeater {
        model: ["00", "06", "12", "18", ""]
        Text {
          required property var modelData
          width: parent.width / 5
          text: modelData
          color: Kit.Palette.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---- finishing and lifetime ---------------------------------------------
  Column {
    width: parent.width
    visible: root.hasData
    spacing: Style.space(4)

    Kit.SectionHeading {
      width: parent.width
      text: "Overall"
    }

    Repeater {
      model: [
        { label: "Finished",  value: root.completion.total > 0
            ? Math.round(root.completion.pct * 100) + "%  (" + root.completion.completed + " of " + root.completion.total + ")"
            : "—" },
        { label: "Sessions",  value: String(root.lifetime.sessions) },
        { label: "Cycles",    value: String(root.lifetime.cycles) },
        { label: "Time",      value: Model.formatDuration(root.lifetime.seconds) }
      ]

      Item {
        required property var modelData
        width: parent.width
        height: Style.space(20)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.label
          color: root.foreground
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.value
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }
  }

  // ---- a hint, not a nag ---------------------------------------------------
  Rectangle {
    width: parent.width
    visible: root.suggestion !== null
    height: suggestionRow.implicitHeight + Style.space(18)
    radius: Style.cornerRadius
    color: Kit.Palette.cardBg
    border.width: 1
    border.color: Kit.Palette.cardBorder

    Row {
      id: suggestionRow
      anchors.centerIn: parent
      width: parent.width - Style.space(20)
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ""                     // fa-lightbulb-o
        color: Kit.Palette.warning
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }

      Column {
        width: parent.width - Style.space(70)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: root.suggestion ? root.suggestion.reason : ""
          color: root.foreground
          wrapMode: Text.WordWrap
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Button {
        anchors.verticalCenter: parent.verticalCenter
        text: "Try"
        bordered: true
        foreground: root.foreground
        onClicked: {
          if (root.hostWidget && root.suggestion) {
            root.hostWidget.usage.record("suggestion:accept")
            root.hostWidget.startSession(root.suggestion.techniqueId, 0, false)
          }
        }
      }
    }
  }
}
