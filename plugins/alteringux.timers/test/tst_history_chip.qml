import QtQuick
import QtTest
import ".." as Timers

TestCase {
  id: suite
  name: "TimerHistoryChip"
  when: windowShown
  visible: true
  width: 420
  height: 100
  property int starts: 0
  property int forgets: 0
  readonly property string savedLabel: "Review long archived timer label FINAL_LABEL_MARKER"

  Timers.TimerHistoryChip {
    id: chip
    x: 12
    y: 12
    label: suite.savedLabel
    maxWidth: 260
    maxTextWidth: 120
    onStartRequested: suite.starts++
    onForgetRequested: suite.forgets++
  }

  function findNamed(item, name) {
    if (item.objectName === name) return item
    for (let i = 0; i < item.children.length; i++) {
      const match = findNamed(item.children[i], name)
      if (match) return match
    }
    return null
  }

  function init() {
    starts = 0
    forgets = 0
    chip.visible = true
  }

  function test_startActionIsNamedAndTabFocusable() {
    const start = findNamed(chip, "timer-history-start")
    verify(start !== null)
    compare(start.Accessible.role, Accessible.Button)
    compare(start.Accessible.name, "Start timer from history label " + savedLabel)
    verify(start.activeFocusOnTab)
    start.Accessible.pressAction()
    compare(starts, 1)
    chip.visible = false
    start.Accessible.pressAction()
    compare(starts, 1)
  }

  function checkKeyboardActivation(key) {
    const start = findNamed(chip, "timer-history-start")
    verify(start !== null)
    start.forceActiveFocus()
    tryCompare(start, "activeFocus", true)
    keyClick(key)
    compare(starts, 1)
  }

  function test_startActionRespondsToReturn() { checkKeyboardActivation(Qt.Key_Return) }
  function test_startActionRespondsToKeypadEnter() { checkKeyboardActivation(Qt.Key_Enter) }
  function test_startActionRespondsToSpace() { checkKeyboardActivation(Qt.Key_Space) }

  function test_startMouseClickDoesNotConsumeForgetAction() {
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(starts, 1)
    const forget = findNamed(chip, "timer-history-forget")
    verify(forget !== null)
    compare(forget.Accessible.role, Accessible.Button)
    compare(forget.Accessible.name, "Forget timer label " + savedLabel)
    mouseClick(forget, forget.width / 2, forget.height / 2)
    compare(forgets, 1)
  }

  function test_completeLabelRemainsASeparateReaderControl() {
    const label = findNamed(chip, "timer-history-label")
    verify(label !== null)
    compare(label.text, savedLabel)
    compare(label.Accessible.name, savedLabel)
    verify(label.hasOverflow)
    verify(label.activeFocusOnTab)
    verify(chip.width <= chip.maxWidth)
  }
}
