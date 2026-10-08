import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../alteringux.kit" as Kit
import "../shared"

Item {
  property QtObject _webPalette: Kit.Palette {}
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool preparingSession: false
  property string selection: ""
  property var words: []
  property int wordIndex: 0
  property int currentSyllableIndex: 0
  // Keep the passage's large rich-text document out of the 35 ms progress
  // updates. The focus word remains syllable-synced; this view updates at a
  // size-aware cadence so long selections cannot monopolize the UI thread.
  property int displayedWordIndex: 0
  property int displayedSyllableIndex: 0
  property int syllableTotal: 1
  property var currentSyllableRanges: []
  property bool colourCursorEnabled: true
  // Focus-word cursor style: "pivot" (Spritz ORP letter) or "syllables" (legacy).
  property string cursorStyle: "pivot"
  // How many words the focus area shows: 1, 3 or 5 (current word centred).
  property int contextWords: 1
  property bool loopEnabled: false
  property bool voiceEnabled: false
  property string codeMode: "auto"
  property bool sessionCodeMode: false
  property bool paused: false
  property real speed: 1.0
  // WPM is the user-facing speed control; speed stays the timing multiplier
  // (100 wpm = 1.0x). Arrow buttons step by 10 wpm; the inline input accepts
  // direct entry. Both funnel through setWpm().
  readonly property int wpm: Math.round(root.speed * 100)
  property real progress: 0
  property double wordStartedAt: 0
  property double sessionStartedAt: 0
  property int liveElapsedMs: 0
  property int sessionWordsRead: 0
  property int sessionSymbolsRead: 0
  property bool sessionRecorded: false
  property bool pendingStatsRecord: false
  property bool pendingSettingsSave: false
  property string message: ""
  property bool speechComplete: true
  property bool speechErrorShown: false
  property int speechGeneration: 0
  property var pendingSpeech: null

  readonly property string home: Quickshell.env("HOME") || "/home/alteringux"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/omarchy/"
  readonly property string piperBin: root.home + "/.local/bin/piper-tts"
  readonly property string transportBin: root.home + "/.local/bin/omarchy-wordstep-transport"
  readonly property color background: _webPalette.menuBackground
  readonly property color foreground: _webPalette.menuText
  readonly property color accent: _webPalette.accent
  readonly property color border: _webPalette.menuBorder
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property string tag: (manifest && manifest.id) || "alteringux.wordstep"
  readonly property var currentWord: wordIndex >= 0 && wordIndex < words.length ? words[wordIndex] : null
  readonly property int currentSpokenSyllableCount: root.currentWord
    ? root.syllableRanges(root.currentWord.speechText || root.currentWord.text).length : 0
  readonly property bool finished: words.length > 0 && wordIndex >= words.length
  readonly property var stats: root.statsWithLiveSession(statsStore.value)

  function close() {
    if (!root.opened) return
    root.recordSession()
    root.saveSettings()
    root.opened = false
    progressTimer.stop()
    root.stopSpeech()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.tag)
  }

  function open(payloadJson) {
    if (root.opened) {
      root.recordSession()
      root.saveSettings()
      root.opened = false
      progressTimer.stop()
      root.stopSpeech()
    }
    root.startSession(payloadJson)
  }

  function startSession(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var nextText = (payload.text || "").toString().trim()
    if (!nextText) {
      root.message = "Select text first, then use the shortcut."
      return
    }

    root.preparingSession = true
    root.selection = nextText
    root.sessionCodeMode = root.shouldUseCodeMode(nextText, root.codeMode)
    root.words = root.tokenize(nextText, root.sessionCodeMode)
    root.wordIndex = 0
    root.currentSyllableIndex = 0
    root.displayedWordIndex = 0
    root.displayedSyllableIndex = 0
    root.progress = 0
    root.paused = false
    root.currentSyllableRanges = []
    root.message = ""
    root.sessionStartedAt = Date.now()
    root.sessionWordsRead = 0
    root.sessionSymbolsRead = 0
    root.sessionRecorded = false
    root.speechErrorShown = false
    root.pendingStatsRecord = false
    root.opened = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      passageFlick.contentY = 0
      passageText.cursorPosition = root.currentWord ? root.currentWord.start : root.selection.length
      if (passageFlick && typeof passageFlick.keepCurrentWordVisible === "function")
        passageFlick.keepCurrentWordVisible(passageText.cursorRectangle)
    })
    root.startCurrentWord()
    root.preparingSession = false
  }

  function parseSettings(raw) {
    var saved = ({})
    try { saved = raw ? JSON.parse(raw) : ({}) } catch (e) { saved = ({}) }
    if (!saved || typeof saved !== "object") saved = ({})
    var speed = Number(saved.speed)
    if (!isFinite(speed)) speed = 1.0
    var codeMode = ["auto", "on", "off"].indexOf(saved.codeMode) >= 0 ? saved.codeMode : "auto"
    return {
      schemaVersion: 1,
      colourCursorEnabled: saved.colourCursorEnabled !== false,
      cursorStyle: saved.cursorStyle === "syllables" ? "syllables" : "pivot",
      contextWords: [1, 3, 5].indexOf(Number(saved.contextWords)) >= 0 ? Number(saved.contextWords) : 1,
      loopEnabled: saved.loopEnabled === true,
      voiceEnabled: saved.voiceEnabled === true,
      speed: Math.max(0.5, Math.min(18, Math.round(speed * 10) / 10)),
      codeMode: codeMode
    }
  }

  function restoreSettings(saved) {
    if (!saved) return
    root.colourCursorEnabled = saved.colourCursorEnabled !== false
    root.cursorStyle = saved.cursorStyle === "syllables" ? "syllables" : "pivot"
    var savedContext = Number(saved.contextWords)
    root.contextWords = [1, 3, 5].indexOf(savedContext) >= 0 ? savedContext : 1
    root.loopEnabled = saved.loopEnabled === true
    root.voiceEnabled = saved.voiceEnabled === true
    var speed = Number(saved.speed)
    if (!isFinite(speed)) speed = 1.0
    root.speed = Math.max(0.5, Math.min(18, Math.round(speed * 10) / 10))
    root.codeMode = ["auto", "on", "off"].indexOf(saved.codeMode) >= 0 ? saved.codeMode : "auto"
  }

  function saveSettings() {
    if (!settingsStore.loaded) {
      root.pendingSettingsSave = true
      return
    }
    settingsStore.value = {
      schemaVersion: 1,
      colourCursorEnabled: root.colourCursorEnabled,
      cursorStyle: root.cursorStyle,
      contextWords: root.contextWords,
      loopEnabled: root.loopEnabled,
      voiceEnabled: root.voiceEnabled,
      speed: root.speed,
      codeMode: root.codeMode
    }
    settingsStore.save()
    root.pendingSettingsSave = false
  }

  function emptyStats() {
    return { schemaVersion: 1, sessions: 0, words: 0, symbols: 0, timeMs: 0, days: [] }
  }

  function statsWithLiveSession(saved) {
    var previous = saved || root.emptyStats()
    if (!root.sessionStartedAt || root.sessionRecorded) return previous
    var days = (previous.days || []).slice()
    var today = root.dateKey(new Date())
    var index = -1
    for (var i = 0; i < days.length; i++) {
      if (days[i].date === today) { index = i; break }
    }
    var daily = index >= 0 ? days[index] : { sessions: 0, words: 0, symbols: 0, timeMs: 0 }
    daily = {
      date: today,
      sessions: root.nonNegativeInt(daily.sessions) + 1,
      words: root.nonNegativeInt(daily.words) + root.sessionWordsRead,
      symbols: root.nonNegativeInt(daily.symbols) + root.sessionSymbolsRead,
      timeMs: root.nonNegativeInt(daily.timeMs) + root.liveElapsedMs
    }
    if (index >= 0) days[index] = daily
    else days.push(daily)
    return {
      schemaVersion: 1,
      sessions: root.nonNegativeInt(previous.sessions) + 1,
      words: root.nonNegativeInt(previous.words) + root.sessionWordsRead,
      symbols: root.nonNegativeInt(previous.symbols) + root.sessionSymbolsRead,
      timeMs: root.nonNegativeInt(previous.timeMs) + root.liveElapsedMs,
      days: days.slice(-60)
    }
  }

  function nonNegativeInt(value) {
    return Math.max(0, Math.floor(Number(value) || 0))
  }

  function parseStats(raw) {
    var saved = ({})
    try { saved = raw ? JSON.parse(raw) : ({}) } catch (e) { saved = ({}) }
    if (!saved || typeof saved !== "object") saved = ({})
    var days = []
    if (Array.isArray(saved.days)) {
      for (var i = 0; i < saved.days.length; i++) {
        var day = saved.days[i]
        if (!day || typeof day.date !== "string") continue
        days.push({
          date: day.date,
          sessions: root.nonNegativeInt(day.sessions),
          words: root.nonNegativeInt(day.words),
          symbols: root.nonNegativeInt(day.symbols),
          timeMs: root.nonNegativeInt(day.timeMs)
        })
      }
    }
    return {
      schemaVersion: 1,
      sessions: root.nonNegativeInt(saved.sessions),
      words: root.nonNegativeInt(saved.words),
      symbols: root.nonNegativeInt(saved.symbols),
      timeMs: root.nonNegativeInt(saved.timeMs),
      days: days.slice(-60)
    }
  }

  function dateKey(date) {
    var month = String(date.getMonth() + 1)
    var day = String(date.getDate())
    if (month.length < 2) month = "0" + month
    if (day.length < 2) day = "0" + day
    return date.getFullYear() + "-" + month + "-" + day
  }

  function recentDays() {
    var source = root.stats.days || []
    var labels = ["S", "M", "T", "W", "T", "F", "S"]
    var result = []
    for (var offset = 6; offset >= 0; offset--) {
      var date = new Date()
      date.setHours(12, 0, 0, 0)
      date.setDate(date.getDate() - offset)
      var key = root.dateKey(date)
      var words = 0
      for (var i = 0; i < source.length; i++) {
        if (source[i].date === key) { words = source[i].words; break }
      }
      result.push({ date: key, label: labels[date.getDay()], words: words })
    }
    return result
  }

  function maxRecentWords() {
    var days = root.recentDays()
    var maximum = 0
    for (var i = 0; i < days.length; i++) maximum = Math.max(maximum, days[i].words)
    return Math.max(1, maximum)
  }

  function formatDuration(timeMs) {
    var minutes = Math.floor(root.nonNegativeInt(timeMs) / 60000)
    var hours = Math.floor(minutes / 60)
    if (hours) return hours + "h " + (minutes % 60) + "m"
    return minutes + "m"
  }

  function formatLiveDuration(timeMs) {
    var seconds = Math.floor(root.nonNegativeInt(timeMs) / 1000)
    var minutes = Math.floor(seconds / 60)
    if (minutes) return minutes + "m " + (seconds % 60) + "s"
    return seconds + "s"
  }

  function shouldUseCodeMode(text, mode) {
    if (mode === "on") return true
    if (mode === "off") return false
    if (/^\s*(const|let|var|function|return|class|import|export|def|async|public|private)\b/m.test(text))
      return true
    if (/^\s*(if|elif|else|for|while|try|except|catch|switch)\s*(\(|\w+\s*(=|in|of|:))/m.test(text))
      return true
    if (/^\s*(select|insert|update|delete)\b/i.test(text))
      return true
    if (/=>|===?|!==?|<=|>=|\+\+|--|&&|\|\||:=|->|[{};]/.test(text)) return true
    if (/\b[A-Za-z_$][A-Za-z0-9_$]*_[A-Za-z0-9_$]+\b/.test(text)) return true
    if (/\b[A-Za-z_$][A-Za-z0-9_$]*\([^\n)]*\)\s*[;{]/.test(text)) return true
    var lines = text.split("\n")
    if (lines.length > 1) {
      var indented = 0
      for (var i = 0; i < lines.length; i++)
        if (/^\s{2,}\S/.test(lines[i])) indented++
      if (indented >= 2) return true
    }
    return false
  }

  function codeSymbolSpeech(symbol) {
    var names = {
      "...": "ellipsis", "===": "strictly equals", "!==": "strictly not equals",
      "==": "equals equals", "!=": "not equals", "<=": "less than or equal to",
      ">=": "greater than or equal to", "=>": "arrow", "->": "arrow",
      "++": "increment", "--": "decrement", "&&": "and", "||": "or",
      "??": "null coalescing", "?.": "optional dot", "+=": "plus equals",
      "-=": "minus equals", "*=": "times equals", "/=": "divided by equals",
      "**": "to the power of", "//": "double slash", ".": "dot", ",": "comma",
      ":": "colon", ";": "semicolon", "(": "open parenthesis", ")": "close parenthesis",
      "{": "open brace", "}": "close brace", "[": "open bracket", "]": "close bracket",
      "<": "less than", ">": "greater than", "+": "plus", "-": "minus",
      "*": "asterisk", "/": "slash", "=": "equals", "!": "exclamation mark",
      "?": "question mark", "|": "pipe", "&": "ampersand", "%": "percent",
      "^": "caret", "~": "tilde", "_": "underscore", "$": "dollar sign",
      "@": "at sign", "#": "hash", "`": "backtick", "'": "single quote",
      "\"": "double quote", "\\": "backslash"
    }
    return names[symbol] || (/^[\x00-\x7F]+$/.test(symbol) ? symbol : "")
  }

  function appendCodeIdentifier(tokens, text, start) {
    var partStart = 0
    for (var i = 1; i < text.length; i++) {
      var previous = text.charAt(i - 1)
      var current = text.charAt(i)
      var next = i + 1 < text.length ? text.charAt(i + 1) : ""
      var lowerOrDigitToUpper = /[a-z0-9]/.test(previous) && /[A-Z]/.test(current)
      var acronymEnd = /[A-Z]/.test(previous) && /[A-Z]/.test(current) && /[a-z]/.test(next)
      if (lowerOrDigitToUpper || acronymEnd) {
        var part = text.slice(partStart, i)
        tokens.push({ text: part, start: start + partStart, end: start + i,
          speakable: true, speechText: part, kind: "word" })
        partStart = i
      }
    }
    var lastPart = text.slice(partStart)
    tokens.push({ text: lastPart, start: start + partStart, end: start + text.length,
      speakable: true, speechText: lastPart, kind: "word" })
  }

  function tokenize(text, codeMode) {
    var tokens = []
    // Avoid Unicode property escapes: this embedded JS engine silently returns
    // no matches for them. Keep surrogate pairs together as one visible token.
    var matcher = codeMode
      ? /(?:[A-Za-z]+['’][A-Za-z]+)|\.\.\.|[A-Za-z0-9]+|===|!==|=>|->|==|!=|<=|>=|\+\+|--|&&|\|\||\?\?|\?\.|\+=|-=|\*=|\/=|\*\*|\/\/|[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\s]/g
      : /[A-Za-z0-9_]+(?:['’\-][A-Za-z0-9_]+)*|[\uD800-\uDBFF][\uDC00-\uDFFF]|[^\sA-Za-z0-9_]/g
    var match
    while ((match = matcher.exec(text)) !== null) {
      var token = match[0]
      if (codeMode && /^[A-Za-z0-9]+$/.test(token)) {
        appendCodeIdentifier(tokens, token, match.index)
        continue
      }
      var isWord = !codeMode && /^[A-Za-z0-9_]/.test(token)
      if (token === "'" || token === "’") {
        // Root-cause fix for fragmented contractions (i | ' | ll): when the
        // matcher emits a bare apostrophe sandwiched between letters, merge it
        // with the previous and following letter runs so [A-Za-z]+'[A-Za-z]+
        // stays a single word token.
        var prev = tokens.length ? tokens[tokens.length - 1] : null
        var rest = text.slice(match.index + 1).match(/^[A-Za-z]+/)
        if (prev && prev.end === match.index && /[A-Za-z]$/.test(prev.text) && rest) {
          var joined = prev.text + token + rest[0]
          prev.text = joined
          prev.end = match.index + 1 + rest[0].length
          prev.speakable = true
          prev.speechText = joined
          prev.kind = "word"
          matcher.lastIndex = prev.end
          continue
        }
        // Leading-apostrophe elisions ('tis, 'n): bind the apostrophe to the
        // letter run that follows. Code mode keeps bare quotes as symbols.
        if (!codeMode && rest && (!prev || prev.end !== match.index)) {
          var lead = { text: token + rest[0], start: match.index,
            end: match.index + 1 + rest[0].length, speakable: true,
            speechText: rest[0], kind: "word" }
          tokens.push(lead)
          matcher.lastIndex = lead.end
          continue
        }
      }
      tokens.push({ text: token, start: match.index, end: match.index + token.length,
        speakable: isWord, speechText: codeMode ? root.codeSymbolSpeech(token) : (isWord ? token : ""),
        kind: isWord ? "word" : "symbol" })
    }
    return tokens
  }

  function applyCodeMode(offset) {
    root.sessionCodeMode = root.shouldUseCodeMode(root.selection, root.codeMode)
    root.words = root.tokenize(root.selection, root.sessionCodeMode)
    var index = 0
    while (index < root.words.length && root.words[index].end <= offset) index++
    root.wordIndex = Math.min(index, root.words.length)
    root.currentSyllableIndex = 0
    root.progress = 0
    root.startCurrentWord()
  }

  function cycleCodeMode() {
    root.codeMode = root.codeMode === "auto" ? "on" : (root.codeMode === "on" ? "off" : "auto")
    root.saveSettings()
    if (!root.opened) return
    var offset = root.currentWord ? root.currentWord.start : 0
    root.applyCodeMode(offset)
  }

  function recordSession() {
    if (root.sessionRecorded || !root.sessionStartedAt) return
    if (!statsStore.loaded) {
      root.pendingStatsRecord = true
      return
    }
    // stats includes a live view of this session; commit against the saved
    // totals so ending a session never counts its live values twice.
    var previous = statsStore.value || root.emptyStats()
    var elapsed = Math.max(0, Date.now() - root.sessionStartedAt)
    var today = root.dateKey(new Date())
    var days = (previous.days || []).slice()
    var index = -1
    for (var i = 0; i < days.length; i++) {
      if (days[i].date === today) { index = i; break }
    }
    var daily = index >= 0 ? days[index] : { date: today, sessions: 0, words: 0, symbols: 0, timeMs: 0 }
    daily = {
      date: today,
      sessions: root.nonNegativeInt(daily.sessions) + 1,
      words: root.nonNegativeInt(daily.words) + root.sessionWordsRead,
      symbols: root.nonNegativeInt(daily.symbols) + root.sessionSymbolsRead,
      timeMs: root.nonNegativeInt(daily.timeMs) + elapsed
    }
    if (index >= 0) days[index] = daily
    else days.push(daily)
    statsStore.value = {
      schemaVersion: 1,
      sessions: previous.sessions + 1,
      words: previous.words + root.sessionWordsRead,
      symbols: previous.symbols + root.sessionSymbolsRead,
      timeMs: previous.timeMs + elapsed,
      days: days.slice(-60)
    }
    statsStore.save()
    root.sessionRecorded = true
    root.pendingStatsRecord = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function htmlEscape(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;")
      .replace(/>/g, "&gt;").replace(/\"/g, "&quot;").replace(/'/g, "&#39;")
  }

  function colourSpan(value, colour, bold, underline) {
    // Qt rich text drops CSS text-decoration in style attributes, so the
    // underline is a real <u> tag wrapping the span.
    var span = "<span style=\"color:\" + colour + (bold ? \";font-weight:700\" : \"\") + \">"
      + root.htmlEscape(value) + "</span>"
    return underline ? "<u>" + span + "</u>" : span
  }



  function codepointLength(value) {
    var count = 0
    for (var i = 0; i < value.length; i++, count++) {
      var c = value.charCodeAt(i)
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < value.length) i++
    }
    return count
  }

  function syllableRanges(value) {
    var length = root.codepointLength(value)
    var apos = value.indexOf("'")
    var curly = value.indexOf("’")
    var cut = apos > 0 ? apos : (curly > 0 ? curly : -1)
    if (cut > 0 && cut < length - 1 && /^[A-Za-z+''’]+$/.test(value))
      return [{ start: 0, end: cut + 1 }, { start: cut + 1, end: length }]
    if (!/^[A-Za-z]+(?:['’\-][A-Za-z]+)*$/.test(value)) return [{ start: 0, end: length }]
    var lower = value.toLowerCase()
    var nuclei = []
    for (var i = 0; i < lower.length; i++) {
      if (/[aeiouy]/.test(lower.charAt(i))) {
        var start = i
        while (i + 1 < lower.length && /[aeiouy]/.test(lower.charAt(i + 1))) i++
        nuclei.push({ start: start, end: i + 1 })
      }
    }
    if (nuclei.length > 1 && /e$/.test(lower) && !/[^aeiouy]le$/.test(lower)
        && nuclei[nuclei.length - 1].start === lower.length - 1)
      nuclei.pop() // final silent e, as in "make" or "time"
    if (nuclei.length <= 1) return [{ start: 0, end: length }]

    var boundaries = [0]
    var onsets = ["bl", "br", "ch", "cl", "cr", "dr", "fl", "fr", "gl", "gr", "ph", "pl",
      "pr", "qu", "sc", "sh", "sk", "sl", "sm", "sn", "sp", "st", "sw", "th", "tr",
      "tw", "wh", "wr", "spl", "spr", "scr", "shr", "squ", "str", "thr"]
    for (var n = 1; n < nuclei.length; n++) {
      var consonants = lower.slice(nuclei[n - 1].end, nuclei[n].start)
      var onsetLength = 0
      for (var o = 0; o < onsets.length; o++) {
        if (consonants.endsWith(onsets[o]))
          onsetLength = Math.max(onsetLength, onsets[o].length)
      }
      boundaries.push(!consonants.length ? nuclei[n].start
        : (onsetLength ? nuclei[n].start - onsetLength : nuclei[n].start - 1))
    }
    if (/[^aeiouy]le$/.test(lower)) boundaries[boundaries.length - 1] = lower.length - 3
    boundaries.push(length)

    var ranges = []
    for (var b = 0; b + 1 < boundaries.length; b++) {
      var from = Math.max(0, Math.min(length, boundaries[b]))
      var to = Math.max(from + 1, Math.min(length, boundaries[b + 1]))
      if (ranges.length && from < ranges[ranges.length - 1].end) from = ranges[ranges.length - 1].end
      if (to > from) ranges.push({ start: from, end: to })
    }
    return ranges.length ? ranges : [{ start: 0, end: length }]
  }

  function syllableAt(codepointIndex) {
    var ranges = root.currentSyllableRanges
    for (var i = 0; i < ranges.length; i++)
      if (codepointIndex >= ranges[i].start && codepointIndex < ranges[i].end) return i
    return Math.max(0, ranges.length - 1)
  }

  function pivotIndex(value) {
    // Spritz-style optimal recognition point: the letter the eye rests on.
    var length = root.codepointLength(value)
    if (length <= 1) return 0
    if (length <= 5) return 1
    if (length <= 9) return 2
    if (length <= 13) return 3
    return 4
  }

  function utf16OffsetAtCodepoint(value, cpIndex) {
    var codepoints = 0
    for (var i = 0; i < value.length; i++) {
      if (codepoints >= cpIndex) return i
      codepoints++
      var c = value.charCodeAt(i)
      if (c >= 0xD800 && c <= 0xDBFF) i++
    }
    return value.length
  }

  function contrastForeground(base) {
    // Inverted colour via the palette's own WCAG 4.5:1 search — same
    // machinery the rest of the shell uses — so text on the accent backdrop
    // is guaranteed readable for every theme. Falls back to a pure
    // black/white luminance distance pick if the palette is unavailable.
    // Pure black/white by WCAG contrast-ratio distance against the backdrop
    // (not a tint): ratio > 1 means white wins, else black.
    var ratioWhite = _webPalette.contrastRatio(Qt.rgba(1, 1, 1, 1), base)
    var ratioBlack = _webPalette.contrastRatio(Qt.rgba(0, 0, 0, 1), base)
    return ratioWhite >= ratioBlack
      ? Qt.rgba(1, 1, 1, 1)
      : Qt.rgba(0, 0, 0, 1)
  }

  function isRepeatedCharToken(value) {
    var chars = root.wordCodepoints(String(value || ""))
    if (chars.length < 3) return false
    for (var i = 1; i < chars.length; i++)
      if (chars[i] !== chars[0]) return false
    return true
  }

  function skipRepeatedRun(fromIndex) {
    // Skip a run of identical punctuation tokens ("---", ".", "=", "·", ...) so
    // the reader doesn't stall on the same glyph word after word.
    var index = fromIndex
    while (index < root.words.length) {
      var word = root.words[index]
      if (!word) break
      var text = String(word.text)
      if (!/^[\s]*$/.test(text) && !root.isRepeatedCharToken(text)) break
      index++
    }
    return index
  }

  function contextWindow() {
    var half = Math.floor((root.contextWords - 1) / 2)
    var from = Math.max(0, root.wordIndex - half)
    var to = Math.min(root.words.length - 1, root.wordIndex + half)
    var window = []
    for (var i = from; i <= to; i++) {
      window.push({ index: i, text: root.words[i].text,
        state: i < root.wordIndex ? "past" : (i === root.wordIndex ? "current" : "future") })
    }
    return window
  }

  function wordCodepoints(word) {
    var chars = []
    for (var i = 0; i < word.length; i++) {
      var c = word.charCodeAt(i)
      if (c >= 0xD800 && c <= 0xDBFF && i + 1 < word.length) {
        chars.push(word.slice(i, i + 2))
        i++
      } else chars.push(word.charAt(i))
    }
    return chars
  }



  function charSyllableColour(word, cpIndex) {
    // Colour for a codepoint of the current word during the syllable sweep.
    // The word sits on an accent backdrop, so chars use contrast colours.
    var strong = root.contrastForeground(root.accent)
    var dim = Qt.rgba(strong.r, strong.g, strong.b, 0.55)
    if (!root.colourCursorEnabled) return strong
    var ranges = root.currentSyllableRanges
    var active = Math.max(0, Math.min(root.currentSyllableIndex, ranges.length - 1))
    for (var k = 0; k < ranges.length; k++) {
      if (cpIndex >= ranges[k].start && cpIndex < ranges[k].end)
        return k < active ? dim : (k === active ? strong : root.contrastForeground(root.accent))
    }
    return root.contrastForeground(root.accent)
  }

  function setContextWords(count) {
    var next = [1, 3, 5].indexOf(count) >= 0 ? count : 1
    if (root.contextWords === next) return
    root.contextWords = next
    root.saveSettings()
  }

  function setCursorStyle(style) {
    var next = style === "syllables" ? "syllables" : "pivot"
    if (root.cursorStyle === next) return
    root.cursorStyle = next
    root.saveSettings()
  }

  function renderWordLegacy(value, activeSyllable) {
    var ranges = root.currentSyllableRanges
    var range = ranges[Math.max(0, Math.min(activeSyllable, ranges.length - 1))]
    if (!root.colourCursorEnabled || !range || ranges.length === 1)
      return root.colourSpan(value, root.accent.toString(), true)
    var past = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.60).toString()
    return root.colourSpan(value.slice(0, range.start), past, true)
      + root.colourSpan(value.slice(range.start, range.end), root.accent.toString(), true)
      + root.htmlEscape(value.slice(range.end))
  }

  function pivotChip(value) {
    // Qt rich text cannot thicken <u>, so the pivot letter sits on an accent
    // background chip: the classic Spritz "thick line" look.
    return "<span style=\"background-color:" + root.accent.toString() + "; color:"
      + root.background.toString() + "\">" + root.htmlEscape(value) + "</span>"
  }

  function renderWord(value) {
    // Syllable colour sweep (past dim accent, current accent, future plain)
    // with the ORP pivot letter highlighted on an accent chip.
    var pivotCp = root.pivotIndex(value)
    var pivotStart = root.utf16OffsetAtCodepoint(value, pivotCp)
    var pivotEnd = root.utf16OffsetAtCodepoint(value, pivotCp + 1)
    var ranges = root.currentSyllableRanges.length ? root.currentSyllableRanges
      : root.syllableRanges(value)
    var active = Math.max(0, Math.min(root.currentSyllableIndex, ranges.length - 1))
    var past = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.60).toString()
    var html = ""
    for (var k = 0; k < ranges.length; k++) {
      var from = Math.min(value.length, Math.max(0, ranges[k].start))
      var to = Math.min(value.length, Math.max(from, ranges[k].end))
      if (to <= from) continue
      // Split this syllable around the pivot letter when it overlaps.
      var mid = Math.max(from, Math.min(to, pivotStart))
      var midEnd = Math.max(from, Math.min(to, pivotEnd))
      var segs = []
      if (mid > from) segs.push({ start: from, end: mid })
      if (midEnd > mid) segs.push({ start: mid, end: midEnd, pivot: true })
      if (to > midEnd) segs.push({ start: midEnd, end: to })
      for (var g = 0; g < segs.length; g++) {
        var seg = value.slice(segs[g].start, segs[g].end)
        if (segs[g].pivot) {
          html += root.pivotChip(seg)
          continue
        }
        if (k < active) html += root.colourSpan(seg, past, true)
        else if (k === active) html += root.colourSpan(seg, root.accent.toString(), true)
        else html += root.htmlEscape(seg)
      }
    }
    return html
  }

  function passageSpan(value, colour) {
    // Keep a handful of format runs instead of one QTextDocument span per
    // character. Stable font weight also keeps line wrapping fixed while reading.
    return "<span style=\"color:" + colour + "\">" + root.htmlEscape(value) + "</span>"
  }

  function renderPassage() {
    if (root.preparingSession) return ""
    var word = root.displayedWordIndex >= 0 && root.displayedWordIndex < root.words.length
      ? root.words[root.displayedWordIndex] : null
    var base = root.foreground.toString()
    var past = Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.60).toString()
    var html = "<p style=\"white-space:pre-wrap;margin:0\">"
    if (!word) {
      return html + root.passageSpan(root.selection, root.finished ? past : base) + "</p>"
    }
    html += root.passageSpan(root.selection.slice(0, word.start), past)
    var ranges = root.syllableRanges(word.text)
    var syllable = Math.min(root.displayedSyllableIndex, ranges.length - 1)
    var range = ranges[syllable]
    if (!root.colourCursorEnabled || !range || ranges.length === 1) {
      html += root.passageSpan(word.text, root.accent.toString())
    } else {
      // Multiple syllables are only produced for ASCII words, so their
      // codepoint offsets equal the TextEdit's UTF-16 offsets.
      html += root.passageSpan(word.text.slice(0, range.start), past)
      html += root.passageSpan(word.text.slice(range.start, range.end), root.accent.toString())
      html += root.passageSpan(word.text.slice(range.end), base)
    }
    return html + root.passageSpan(root.selection.slice(word.end), base) + "</p>"
  }

  function estimatedWordMs() {
    if (!root.currentWord) return 500
    var syllables = root.currentSpokenSyllableCount
    return Math.max(360, Math.min(5000, (syllables * 370 + 150) / root.speed))
  }

  function startCurrentWord() {
    progressTimer.stop()
    if (!root.opened || !root.currentWord || root.paused) return
    root.currentSyllableIndex = 0
    root.currentSyllableRanges = root.syllableRanges(root.currentWord.text)
    root.syllableTotal = Math.max(1, root.currentSyllableRanges.length)
    root.progress = 0
    root.wordStartedAt = 0
    root.wordStartedAt = Date.now()
    progressTimer.start()
    root.speakCurrentWord()
  }

  function setVoiceEnabled(enabled) {
    root.voiceEnabled = enabled === true
    root.saveSettings()
    if (!root.voiceEnabled) root.stopSpeech()
    else root.speakCurrentWord()
  }

  function stopSpeech() {
    root.pendingSpeech = null
    root.speechComplete = true
    if (speechProcess.running && speechProcess.jobTag)
      Quickshell.execDetached([root.piperBin, "--stop", "--tag", speechProcess.jobTag])
  }

  function speakCurrentWord() {
    var word = root.currentWord
    if (!root.voiceEnabled || !root.opened || !word || !word.speakable
        || !String(word.speechText || "").trim()) {
      root.pendingSpeech = null
      root.speechComplete = true
      if (speechProcess.running && speechProcess.jobTag)
        Quickshell.execDetached([root.piperBin, "--stop", "--tag", speechProcess.jobTag])
      return
    }
    root.speechGeneration++
    var request = {
      wordIndex: root.wordIndex,
      tag: "alteringux-wordstep-" + Math.floor(root.sessionStartedAt) + "-" + root.speechGeneration,
      text: String(word.speechText).trim()
    }
    root.speechComplete = false
    if (root.paused) {
      root.pendingSpeech = request
      if (speechProcess.running && speechProcess.jobTag)
        Quickshell.execDetached([root.piperBin, "--stop", "--tag", speechProcess.jobTag])
      return
    }
    if (speechProcess.running) {
      root.pendingSpeech = request
      Quickshell.execDetached([root.piperBin, "--stop", "--tag", speechProcess.jobTag])
      return
    }
    root.beginSpeech(request)
  }

  function beginSpeech(request) {
    if (!request || !root.opened || !root.voiceEnabled || root.paused
        || request.wordIndex !== root.wordIndex) {
      root.speechComplete = true
      return
    }
    speechProcess.jobTag = request.tag
    speechProcess.wordIndex = request.wordIndex
    speechProcess.command = [root.piperBin, "--tag", request.tag, "--", request.text]
    speechProcess.running = true
  }

  function setSpeechTransport(action) {
    if (!speechProcess.running || !speechProcess.jobTag) return
    Quickshell.execDetached([root.transportBin, action, speechProcess.jobTag])
  }

  function captureProgress() {
    if (root.paused || !root.wordStartedAt || !root.currentWord) return
    var duration = root.estimatedWordMs()
    root.progress = Math.min(1, Math.max(0, (Date.now() - root.wordStartedAt) / duration))
    root.currentSyllableIndex = Math.min(root.syllableTotal - 1,
      Math.floor(root.progress * root.syllableTotal))
  }

  function updateProgress() {
    if (root.paused || !root.wordStartedAt || !root.currentWord) return
    root.captureProgress()
    if (root.progress >= 1) {
      if (!root.speechComplete) {
        root.currentSyllableIndex = root.syllableTotal - 1
        return
      }
      progressTimer.stop()
      root.advance(1)
    }
  }

  function finishOrLoop() {
    if (root.loopEnabled && root.opened && root.words.length > 0) {
      root.wordIndex = 0
      root.currentSyllableIndex = 0
      root.progress = 0
      root.message = "Looping"
      root.startCurrentWord()
      return
    }
    root.currentSyllableIndex = 0
    root.progress = 1
    root.message = "Finished"
    root.recordSession()
  }

  function advance(delta) {
    var next = Math.max(0, Math.min(root.words.length, root.wordIndex + delta))
    if (next === root.wordIndex && delta !== 1) return
    if (delta > 0 && root.currentWord) {
      if (root.currentWord.kind === "word") root.sessionWordsRead++
      else root.sessionSymbolsRead++
    }
    var landed = next
    if (landed < root.words.length && root.isRepeatedCharToken(root.words[landed].text)) {
      var after = root.skipRepeatedRun(landed)
      if (after !== landed) {
        console.log("[WORDSTEP-EDGE] skipped repeated-char run: " + root.words[landed].text.charAt(0)
          + " x" + (after - landed) + " tokens at index " + landed)
        if (delta > 0) {
          var skipped = after - landed
          if (root.currentWord && root.currentWord.kind === "word") root.sessionWordsRead += 0
          root.sessionSymbolsRead += skipped
        }
        landed = after
      }
    }
    root.wordIndex = landed
    if (root.wordIndex >= root.words.length) {
      root.finishOrLoop()
      return
    }
    root.startCurrentWord()
  }

  function jumpToWord(index) {
    var next = Math.max(0, Math.min(root.words.length - 1, Math.floor(Number(index))))
    if (!isFinite(next) || next < 0 || !root.words.length) return
    root.currentSyllableIndex = 0
    var targetWord = root.words[next]
    root.currentSyllableRanges = targetWord ? root.syllableRanges(targetWord.text) : []
    root.syllableTotal = Math.max(1, root.currentSyllableRanges.length)
    root.progress = 0
    root.wordStartedAt = 0
    root.message = ""
    root.wordIndex = next
    if (!root.paused) root.startCurrentWord()
  }

  function jumpToPosition(position) {
    var offset = Math.max(0, Math.min(root.selection.length, Math.floor(Number(position) || 0)))
    var target = -1
    var nearestDistance = Number.MAX_VALUE
    for (var i = 0; i < root.words.length; i++) {
      var word = root.words[i]
      if (offset >= word.start && offset < word.end) {
        target = i
        break
      }
      var distance = offset < word.start ? word.start - offset : offset - word.end
      if (distance < nearestDistance) {
        nearestDistance = distance
        target = i
      }
    }
    if (target >= 0) {
      root.jumpToWord(target)
      root.message = "Jumped to step " + (target + 1) + " of " + root.words.length
    }
  }

  function togglePause() {
    if (!root.opened || root.finished) return
    if (!root.paused) root.captureProgress()
    root.paused = !root.paused
    if (root.paused) {
      progressTimer.stop()
      root.setSpeechTransport("pause")
    } else {
      root.wordStartedAt = Date.now() - root.progress * root.estimatedWordMs()
      progressTimer.start()
      if (root.pendingSpeech && root.pendingSpeech.wordIndex === root.wordIndex) {
        if (!speechProcess.running) {
          var request = root.pendingSpeech
          root.pendingSpeech = null
          root.beginSpeech(request)
        }
      } else root.setSpeechTransport("resume")
    }
  }

  function setWpm(nextWpm) {
    root.setSpeed(Number(nextWpm) / 100)
  }

  function setSpeed(nextSpeed) {
    var next = Math.max(0.5, Math.min(18, Math.round(nextSpeed * 10) / 10))
    if (next === root.speed) return
    root.captureProgress()
    root.speed = next
    root.saveSettings()
    if (!root.paused && root.currentWord) {
      root.wordStartedAt = Date.now() - root.progress * root.estimatedWordMs()
      progressTimer.start()
    }
  }

  function setColourCursorEnabled(enabled) {
    root.colourCursorEnabled = enabled
    root.saveSettings()
  }

  function setLoopEnabled(enabled) {
    var next = enabled === true || enabled === "true"
    if (root.loopEnabled === next) return
    root.loopEnabled = next
    root.saveSettings()
    if (next && root.finished) {
      root.sessionStartedAt = Date.now()
      root.liveElapsedMs = 0
      root.sessionWordsRead = 0
      root.sessionSymbolsRead = 0
      root.sessionRecorded = false
      root.pendingStatsRecord = false
      root.wordIndex = 0
      root.currentSyllableIndex = 0
      root.progress = 0
      root.message = "Looping"
      root.startCurrentWord()
    } else if (!next && root.message === "Looping") {
      root.message = ""
    }
  }

  Kit.Store {
    id: settingsStore
    dir: root.stateDir
    fileName: "wordstep-settings.json"
    seedOnCreate: true
    parse: function(raw) { return root.parseSettings(raw) }
    onLoadedChanged: {
      if (!loaded) return
      if (root.pendingSettingsSave) root.saveSettings()
      else root.restoreSettings(value)
    }
  }

  Kit.Store {
    id: statsStore
    dir: root.stateDir
    fileName: "wordstep-stats.json"
    seedOnCreate: true
    parse: function(raw) { return root.parseStats(raw) }
    onLoadedChanged: {
      if (loaded && root.pendingStatsRecord) root.recordSession()
    }
  }

  Timer {
    id: progressTimer
    interval: 35
    repeat: true
    onTriggered: root.updateProgress()
  }

  Timer {
    id: passageHighlightTimer
    interval: Math.max(100, Math.min(500, Math.ceil(root.selection.length / 200)))
    repeat: false
    onTriggered: {
      root.displayedWordIndex = root.wordIndex
      root.displayedSyllableIndex = root.currentSyllableIndex
    }
  }

  Timer {
    id: metricsTimer
    interval: 1000
    repeat: true
    running: root.opened && root.sessionStartedAt > 0 && !root.sessionRecorded
    onTriggered: root.liveElapsedMs = Math.max(0, Date.now() - root.sessionStartedAt)
  }

  Connections {
    target: root
    function onWordIndexChanged() { passageHighlightTimer.restart() }
    function onCurrentSyllableIndexChanged() { passageHighlightTimer.restart() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-wordstep"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: _webPalette.menuScrim }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(860), panel.width - Style.space(64))
      height: Math.min(Style.space(580), panel.height - Style.space(64))
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Shortcut {
          sequence: "Escape"
          context: Qt.WindowShortcut
          enabled: root.opened && !footerText.detailsVisible && !statusText.detailsVisible && !wpmField.field.activeFocus
          onActivated: root.close()
        }
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Space) {
            root.togglePause()
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.advance(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.advance(-1)
            event.accepted = true
          }
        }
      }

      Kit.PanelScroll {
        id: readerScroll
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        contentHeight: readerContent.implicitHeight

      Column {
        id: readerContent
        width: readerScroll.width
        spacing: Style.spacing.md

        Row {
          width: parent.width
          height: Style.space(34)
          spacing: Style.spacing.sm
          MarqueeText {
            id: statusText
            width: Math.max(0, parent.width - closeButton.width - codeModeButton.width - Style.spacing.md * 2)
            text: "Wordstep  ·  " + (root.finished ? "Complete" : "Reading")
              + (root.sessionCodeMode ? "  ·  Code" : "")
            color: root.foreground
            textFont.family: root.fontFamily
            textFont.pixelSize: Style.font.heading
            textFont.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Kit.ActionButton {
            id: codeModeButton
            focusable: true
            Accessible.name: "Code reading mode: " + root.codeMode
            Accessible.role: Accessible.Button
            text: "Code: " + root.codeMode.toUpperCase()
            foreground: root.sessionCodeMode ? root.accent : root.foreground
            bordered: true
            onClicked: root.cycleCodeMode()
          }
          Kit.ActionButton {
            id: closeButton
            focusable: true
            Accessible.name: "Close WordStep"
            Accessible.role: Accessible.Button
            text: "Esc  ×"
            foreground: root.foreground
            bordered: true
            onClicked: root.close()
          }
        }

        Item {
          id: focusCard
          width: parent.width
          height: Math.max(Style.space(54), Math.min(Style.space(108), focusWord.implicitHeight))

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.055)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
          }

          Rectangle {
            width: Style.space(3)
            height: Style.space(28)
            radius: Style.space(2)
            color: root.accent
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
          }

          Item {
            id: focusWord
            anchors.fill: parent
            anchors.leftMargin: Style.space(30)
            anchors.rightMargin: Style.space(20)

            Accessible.name: root.currentWord ? root.currentWord.text : "Reading complete"

            Text {
              anchors.centerIn: parent
              visible: !root.currentWord
              text: root.finished ? "Finished" : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }

            Row {
              anchors.centerIn: parent
              spacing: Style.space(14)

              Repeater {
                model: root.currentWord ? root.contextWindow() : []

                Row {
                  required property var modelData
                  property bool isCurrent: modelData.state === "current"
                  spacing: 0

                  Text {
                    visible: !isCurrent
                    text: modelData.text
                    color: modelData.state === "past"
                      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
                      : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Item {
                    visible: isCurrent
                    width: currentWordRow.width + Style.space(16)
                    height: currentWordRow.height + Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter

                    // Full accent backdrop makes the current word pop. The
                    // word itself always draws in a luminance-picked contrast
                    // colour so it is visible on any accent (see
                    // contrastForeground and charSyllableColour).
                    Rectangle {
                      anchors.fill: parent
                      color: root.accent
                      radius: Style.space(2)
                    }

                    // Pivot underline: a thick bar beneath the ORP letter.
                    // Guarded charWidths reads so binding resets on model
                    // change can never throw (the old crash aborted rendering
                    // of the whole current word).
                    Rectangle {
                      x: {
                        var row = currentWordRow
                        var widths = row && row.charWidths ? row.charWidths : []
                        var pivotCp = root.pivotIndex(modelData.text)
                        var w = 0
                        for (var i = 0; i < pivotCp && i < widths.length; i++)
                          w += widths[i] || 0
                        return Style.space(8) + w
                      }
                      width: (currentWordRow && currentWordRow.charWidths
                        ? currentWordRow.charWidths : [])[root.pivotIndex(modelData.text)] || 0
                      height: Style.space(4)
                      anchors.bottom: parent.bottom
                      color: root.contrastForeground(root.accent)
                      radius: Style.space(1)
                      visible: root.cursorStyle === "pivot" && width > 0
                    }

                    Row {
                      id: currentWordRow
                      x: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 0

                      // Per-codepoint widths; reset when the model changes.
                      // All readers use (charWidths || [])[i] || 0 so a reset
                      // mid-binding just yields 0 instead of a TypeError.
                      property var charWidths: []
                      onCharWidthsChanged: {
                        if (!Array.isArray(charWidths)) charWidths = []
                      }

                      Repeater {
                        // Chars of the current word; each coloured by syllable sweep.
                        model: root.currentWord ? root.wordCodepoints(modelData.text) : []

                        Text {
                          required property string modelData
                          required property int index
                          property color sweepColour: root.charSyllableColour(modelData, index)
                          text: modelData
                          color: sweepColour
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.display
                          font.bold: true
                          Component.onCompleted: Qt.callLater(function() {
                            var row = currentWordRow
                            if (!row || index < 0) return
                            var widths = Array.isArray(row.charWidths) ? row.charWidths.slice() : []
                            widths[index] = width
                            row.charWidths = widths
                          })
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Item {
          id: passageViewport
          width: parent.width
          // readerContent sizes itself from its children. Reading its height
          // here makes the passage and column depend on each other's height.
          height: Math.max(Style.space(80), readerScroll.height - Style.space(34 + 82 + 30 + 46 + 108 + 22) - readerContent.spacing * 6)
          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.085)
          }

          Flickable {
            id: passageFlick
            anchors.fill: parent
            anchors.margins: Style.space(8)
            clip: true
            contentWidth: passageText.width
            contentHeight: Math.max(height, passageText.height)
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds

            function keepCurrentWordVisible(rect) {
              var targetY = rect.y + Math.max(rect.height, 1) / 2 - height / 2
              var nextY = Math.max(0, Math.min(Math.max(0, contentHeight - height), targetY))
              if (Math.abs(contentY - nextY) > 0.5) contentY = nextY
            }

            function syncCurrentWord() {
              if (typeof keepCurrentWordVisible !== "function") return
              passageText.cursorPosition = root.currentWord ? root.currentWord.start : root.selection.length
              keepCurrentWordVisible(passageText.cursorRectangle)
            }

            TextEdit {
              id: passageText
              x: 0
              y: 0
              width: Math.max(1, passageFlick.width - Style.space(10))
              height: Math.max(passageFlick.height, implicitHeight)
              text: root.renderPassage()
              textFormat: TextEdit.RichText
              textMargin: 0
              topPadding: Math.max(0, (passageFlick.height - Style.font.heading) / 2)
              bottomPadding: Math.max(0, (passageFlick.height - Style.font.heading) / 2)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: TextEdit.WordWrap
              readOnly: true
              focus: false
              activeFocusOnPress: false
              cursorVisible: false
              selectByMouse: false
              selectByKeyboard: false
              Accessible.name: root.selection
              // Coalesce text/layout changes once per event-loop turn. Cursor
              // geometry must not queue more scrolling during a scroll update.
              onTextChanged: Qt.callLater(passageFlick.syncCurrentWord)
              onWidthChanged: Qt.callLater(passageFlick.syncCurrentWord)
            }

            MouseArea {
              id: passageClickArea
              anchors.fill: passageText
              z: 1
              acceptedButtons: Qt.LeftButton
              preventStealing: false
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                var point = passageText.mapFromItem(passageClickArea, mouse.x, mouse.y)
                root.jumpToPosition(passageText.positionAt(point.x, point.y))
              }
            }

            ScrollBar.vertical: ScrollBar {
              id: passageScrollBar
              policy: ScrollBar.AsNeeded
              visible: size > 0 && size < 1
              enabled: visible
              interactive: visible
              width: Style.space(10)
            }
          }
        }

        Row {
          width: parent.width
          height: Style.space(30)
          spacing: Style.spacing.sm
          Text {
            text: root.finished ? "Complete" : "Step " + Math.min(root.wordIndex + 1, root.words.length) + " of " + root.words.length
            color: root.finished ? _webPalette.positive : _webPalette.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
          Rectangle {
            width: Math.max(Style.space(60), parent.width - 110)
            height: Style.space(4)
            radius: Style.space(2)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
              width: parent.width * (root.finished ? 1 : Math.max(0, Math.min(1,
                (root.wordIndex + root.progress) / Math.max(1, root.words.length))))
              height: parent.height
              radius: parent.radius
              color: root.accent
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.sm
          Kit.ActionButton { text: "‹"; focusable: true; Accessible.name: "Previous word"; enabled: root.wordIndex > 0; onClicked: root.advance(-1) }
          Kit.ActionButton { text: root.paused ? "Resume" : "Pause"; focusable: true; Accessible.name: text + " reading"; onClicked: root.togglePause() }
          Kit.ActionButton { text: "›"; focusable: true; Accessible.name: "Next word"; enabled: !root.finished; onClicked: root.advance(1) }
          Kit.ActionButton {
            focusable: true
            Accessible.name: text
            text: root.colourCursorEnabled ? "Colour cursor on" : "Colour cursor off"
            Accessible.role: Accessible.CheckBox
            Accessible.checked: root.colourCursorEnabled
            Accessible.onToggleAction: root.setColourCursorEnabled(!root.colourCursorEnabled)
            foreground: root.colourCursorEnabled ? root.accent : root.foreground
            bordered: root.colourCursorEnabled
            onClicked: root.setColourCursorEnabled(!root.colourCursorEnabled)
          }
          Kit.ActionButton {
            focusable: true
            Accessible.name: "Cursor style: " + (root.cursorStyle === "syllables" ? "syllables" : "pivot letter")
            text: root.cursorStyle === "syllables" ? "Syllables" : "Pivot"
            foreground: root.cursorStyle === "syllables" ? root.accent : root.foreground
            bordered: root.cursorStyle === "syllables"
            onClicked: root.setCursorStyle(root.cursorStyle === "syllables" ? "pivot" : "syllables")
          }
          Kit.ActionButton {
            focusable: true
            Accessible.name: "Words shown: " + root.contextWords
            text: root.contextWords + " word" + (root.contextWords > 1 ? "s" : "")
            onClicked: root.setContextWords(root.contextWords === 1 ? 3 : (root.contextWords === 3 ? 5 : 1))
          }
          Kit.ActionButton {
            focusable: true
            Accessible.name: text
            text: root.loopEnabled ? "Loop on" : "Loop off"
            Accessible.role: Accessible.CheckBox
            Accessible.checked: root.loopEnabled
            Accessible.onToggleAction: root.setLoopEnabled(!root.loopEnabled)
            foreground: root.loopEnabled ? root.accent : root.foreground
            bordered: root.loopEnabled
            onClicked: root.setLoopEnabled(!root.loopEnabled)
          }
          Kit.ActionButton {
            focusable: true
            Accessible.name: root.voiceEnabled ? "Voice on" : "Voice off"
            Accessible.role: Accessible.CheckBox
            Accessible.checked: root.voiceEnabled
            Accessible.onToggleAction: root.setVoiceEnabled(!root.voiceEnabled)
            text: root.voiceEnabled ? "Voice on" : "Voice off"
            foreground: root.voiceEnabled ? root.accent : root.foreground
            bordered: root.voiceEnabled
            onClicked: root.setVoiceEnabled(!root.voiceEnabled)
          }
          Item { width: 1; height: 1 }
          NumberField {
            id: wpmField
            label: ""
            from: 50
            to: 1800
            stepSize: 10
            value: root.wpm
            onModified: function(value) { root.setWpm(value) }
          }
        }

        Item {
          width: parent.width
          height: Style.space(108)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          }

          Column {
            anchors.fill: parent
            spacing: Style.space(4)

            Row {
              width: parent.width
              height: Style.space(34)
              spacing: Style.space(8)

              Column {
                width: (parent.width - parent.spacing * 3) / 4
                Text {
                  width: parent.width
                  text: String(root.stats.sessions)
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  width: parent.width
                  text: "SESSIONS"
                  color: _webPalette.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }
              }
              Column {
                width: (parent.width - parent.spacing * 3) / 4
                Text {
                  width: parent.width
                  text: String(root.stats.words)
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  width: parent.width
                  text: "WORDS"
                  color: _webPalette.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }
              }
              Column {
                width: (parent.width - parent.spacing * 3) / 4
                Text {
                  width: parent.width
                  text: String(root.stats.symbols)
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  width: parent.width
                  text: "SYMBOLS"
                  color: _webPalette.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }
              }
              Column {
                width: (parent.width - parent.spacing * 3) / 4
                Text {
                  width: parent.width
                  text: root.sessionStartedAt && !root.sessionRecorded
                    ? root.formatLiveDuration(root.stats.timeMs) : root.formatDuration(root.stats.timeMs)
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  width: parent.width
                  text: "TIME"
                  color: _webPalette.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }

            Text {
              width: parent.width
              height: Style.space(14)
              text: "WORDS · LAST 7 DAYS"
              color: _webPalette.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Row {
              width: parent.width
              height: Style.space(54)
              spacing: Style.space(8)
              Repeater {
                model: root.recentDays()
                delegate: Column {
                  width: (parent.width - parent.spacing * 6) / 7
                  spacing: Style.space(2)
                  Item {
                    width: parent.width
                    height: Style.space(36)
                    Rectangle {
                      width: Style.space(14)
                      height: parent.height
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      radius: Style.space(3)
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                    }
                    Rectangle {
                      width: Style.space(14)
                      height: modelData.words > 0
                        ? Math.max(Style.space(4), parent.height * modelData.words / root.maxRecentWords())
                        : Style.space(2)
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottom: parent.bottom
                      radius: Style.space(3)
                      color: modelData.words > 0 ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.24)
                    }
                  }
                  Text {
                    width: parent.width
                    height: Style.space(14)
                    text: modelData.label
                    color: _webPalette.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignHCenter
                  }
                }
              }
            }
          }
        }

        Rectangle {
          visible: !!root.message
          width: parent.width
          height: Style.space(22)
          radius: root.message ? Style.cornerRadius : 0
          color: root.message ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10) : "transparent"
          border.width: root.message ? 1 : 0
          border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)

          MarqueeText {
            id: footerText
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            text: root.message
            requestedTextFormat: Text.PlainText
            color: root.message ? root.accent : _webPalette.muted
            requestedElide: Text.ElideRight
            textFont.family: root.fontFamily
            textFont.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }

        Text {
          id: shortcutHint
          width: parent.width
          text: root.finished ? "Click to seek  ·  ←: previous word  ·  Esc: close"
            : "Click to seek  ·  ←/→: step  ·  Space: pause/resume  ·  Esc: close"
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: _webPalette.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
        }
      }
      }
    }
  }

  Process {
    id: speechProcess
    running: false
    property string jobTag: ""
    property int wordIndex: -1
    onExited: function(exitCode) {
      var next = root.pendingSpeech
      root.pendingSpeech = null
      if (next && root.opened && root.voiceEnabled && next.wordIndex === root.wordIndex) {
        if (root.paused) {
          root.pendingSpeech = next
          root.speechComplete = false
        } else {
          root.beginSpeech(next)
        }
        return
      }
      if (speechProcess.wordIndex !== root.wordIndex) return
      if (exitCode !== 0 && !root.speechErrorShown && root.opened
          && root.voiceEnabled && !root.paused) {
        root.speechErrorShown = true
        root.message = "Voice playback failed. Check Piper, its voice model, and audio output."
      }
      root.speechComplete = true
      if (root.opened && root.voiceEnabled && !root.paused && root.progress >= 1) {
        progressTimer.stop()
        root.advance(1)
      }
    }
  }
}
