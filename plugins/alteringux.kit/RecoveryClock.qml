import QtQuick
import Quickshell.Io

// Linux boot time is independent of wall-clock corrections. Read only on
// eligible input/dismissal; no periodic animation, helper process or logging.
Item {
  id: root
  property bool readFailed: false
  visible: false
  function nowMs() {
    readFailed = false
    uptime.reload()
    const match = /^([0-9]+(?:\.[0-9]+)?)\s/.exec(uptime.text())
    return !readFailed && match ? Number(match[1]) * 1000 : NaN
  }
  FileView {
    id: uptime
    path: "/proc/uptime"
    preload: false
    blockAllReads: true
    printErrors: false
    onLoadFailed: root.readFailed = true
  }
}
