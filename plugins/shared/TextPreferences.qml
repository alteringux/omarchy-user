pragma Singleton
import QtQuick
import QtCore

QtObject {
  property alias animateTruncatedText: persisted.animateTruncatedText
  // Enrollment is separate from implementing the policy. No observer is
  // enabled merely by loading a panel or opening manual shortcut help.
  property alias suggestRecoveryShortcuts: persisted.suggestRecoveryShortcuts

  function sync() {
    persisted.setValue("animateTruncatedText", persisted.animateTruncatedText)
    persisted.setValue("suggestRecoveryShortcuts", persisted.suggestRecoveryShortcuts)
    persisted.sync()
  }

  property Settings storage: Settings {
    id: persisted
    category: "Accessibility"
    // QtCore StandardPaths returns a URL; adding another file:// corrupts it.
    location: StandardPaths.writableLocation(StandardPaths.ConfigLocation)
      + "/omarchy/plugin-accessibility.ini"
    property bool animateTruncatedText: true
    property bool suggestRecoveryShortcuts: false
  }
}
