import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "../alteringux.kit" as Kit

// One match card: two team rows (home/away), score or kick-off time, league
// tag. Used for live matches (score + status), upcoming (time + venue) and
// results (final score). Shape follows stocks' MoverCard — translucent card,
// no Kit.Card body slot needed for this simple row layout.
Rectangle {
  id: root

  required property var match
  property bool isLive: false
  property bool isResult: false
  property string homeBadge: ""
  property string awayBadge: ""
  property var favouriteNames: []
  property color barForeground: Color.foreground
  property color accentColor: Color.accent
  property var prediction: null

  signal detailsRequested(var match)
  signal openRequested(string url)

  readonly property bool favTouch: Model.matchTouchesFavourite(match, favouriteNames)
  readonly property bool live: !isResult && !Model.matchEnded(match && match.status)
    && (isLive || (match && Model.matchStarted(match.status)))

  function homeLabel(m) {
    return m.homeTeam || (m.sport === "Fighting" ? m.eventName : "") || "TBA"
  }

  function awayLabel(m) {
    return m.awayTeam || (m.sport === "Fighting" && m.eventName ? "Fight card" : "TBA")
  }

  function kickoffLabel(m) {
    if (m.sport === "Fighting" && (!m.strTimestamp || m.strTime === "00:00:00"))
      return "TBD"
    return Model.formatMatchTimeOfDay(m) || Model.formatMatchDate(m.dateEvent)
  }

  Layout.preferredHeight: cardCol.implicitHeight + Style.space(16)
  radius: Style.cornerRadius
  clip: true
  color: Util.alpha(root.barForeground, favTouch ? 0.09 : 0.05)
  border.width: 1
  border.color: Util.alpha(root.barForeground, favTouch ? 0.28 : 0.14)

  Column {
    id: cardCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        text: Model.sportGlyph(root.match && root.match.sport)
        color: root.accentColor
        opacity: 0.9
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        text: (root.match && root.match.league) || ""
        width: parent.width - x
        elide: Text.ElideRight
        color: root.barForeground
        opacity: 0.5
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    // home row
    Row {
      width: parent.width
      spacing: Style.space(6)
      Image {
        id: homeBadgeImage
        source: root.homeBadge
        visible: source !== ""
        asynchronous: true
        sourceSize.width: Style.space(24)
        sourceSize.height: Style.space(24)
        width: Style.space(24)
        height: Style.space(24)
        fillMode: Image.PreserveAspectFit
      }
      Text {
        text: root.homeLabel(root.match || {})
        width: parent.width - scoreText.width - homeBadgeImage.width - parent.spacing * 2
        elide: Text.ElideRight
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: root.favTouch || root.live
      }
      Text {
        id: scoreText
        text: {
          var m = root.match || {}
          if (root.isResult || root.live)
            return Model.formatScore(m.homeScore, m.awayScore)
          return root.kickoffLabel(m)
        }
        color: {
          var m = root.match || {}
          if (!root.live && !root.isResult) return root.accentColor
          var hs = m.homeScore, as_ = m.awayScore
          if (hs === null || hs === undefined || as_ === null || as_ === undefined) return root.barForeground
          return hs >= as_ ? root.accentColor : root.barForeground
        }
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    // away row
    Row {
      width: parent.width
      spacing: Style.space(6)
      Image {
        id: awayBadgeImage
        source: root.awayBadge
        visible: source !== ""
        asynchronous: true
        sourceSize.width: Style.space(24)
        sourceSize.height: Style.space(24)
        width: Style.space(24)
        height: Style.space(24)
        fillMode: Image.PreserveAspectFit
      }
      Text {
        text: root.awayLabel(root.match || {})
        width: parent.width - awayBadgeImage.width - parent.spacing
        elide: Text.ElideRight
        color: root.barForeground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: root.favTouch || root.live
      }
      Text {
        id: scoreText2
        text: {
          var m = root.match || {}
          if (root.isResult || root.live)
            return ""
          return (m.strTimestamp && !isNaN(Date.parse(m.strTimestamp))) ? "" : ""
        }
        visible: false
      }
    }

    // status line
    Text {
      visible: root.live || root.isResult || !!(root.match && root.match.venue)
      text: {
        var m = root.match || {}
        if (root.live) return Model.formatMatchTime(m.status, m.elapsed) || "in play"
        if (root.isResult) return "final"
        return m.venue || ""
      }
      color: root.live ? Kit.Palette.positive : root.barForeground
      opacity: root.live ? 1.0 : 0.5
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: root.live
    }
    Column {
      visible: !!root.prediction
      spacing: Style.space(1)

      Text {
        text: root.prediction && root.prediction.predictedWinner
          ? "🤖 Model pick: " + root.prediction.predictedWinner
            + (root.prediction.confidence !== null ? " (" + Math.round(root.prediction.confidence * 100) + "%)" : "")
          : "🤖 Prediction unavailable"
        color: root.prediction && root.prediction.predictedWinner ? root.accentColor : Kit.Palette.warning
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        visible: !!(root.prediction && (root.prediction.reason || root.prediction.error))
        text: (root.prediction && (root.prediction.reason || root.prediction.error)) || ""
        width: parent.width
        elide: Text.ElideRight
        color: root.barForeground
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      spacing: Style.space(8)
      visible: !!root.match

      Text {
        text: "▶ Highlights"
        color: root.accentColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openRequested(Model.matchHighlightsUrl(root.match))
        }
      }

      Text {
        visible: !!(root.match && root.match.videoUrl)
        text: "🎬 Official video"
        color: root.accentColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openRequested(root.match.videoUrl || "")
        }
      }

      Text {
        text: "🔎 Official coverage"
        color: root.barForeground
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openRequested(Model.matchCoverageUrl(root.match))
        }
      }

      Text {
        text: "ⓘ Details"
        color: root.barForeground
        opacity: 0.65
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.detailsRequested(root.match)
        }
      }
    }
  }
}
