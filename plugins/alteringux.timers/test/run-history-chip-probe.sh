#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
probe_config="$(mktemp -d)"
test_modules="$(mktemp -d)"
trap 'rm -rf -- "$probe_config" "$test_modules"' EXIT

mkdir -p "$test_modules/qs/Ui" "$test_modules/qs/Commons"
cat > "$test_modules/qs/Ui/qmldir" <<'EOF'
module qs.Ui
Button 1.0 Button.qml
EOF
cat > "$test_modules/qs/Ui/Button.qml" <<'EOF'
import QtQuick

Item {
  id: root
  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property color foreground: "white"
  property real fontSize: 12
  property real horizontalPadding: 4
  property real verticalPadding: 2
  property bool focusable: true
  property bool bordered: false
  signal clicked()
  activeFocusOnTab: focusable
  implicitWidth: label.implicitWidth + horizontalPadding * 2
  implicitHeight: label.implicitHeight + verticalPadding * 2
  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: root.foreground
    font.pixelSize: root.fontSize
  }
  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
EOF
cat > "$test_modules/qs/Commons/qmldir" <<'EOF'
module qs.Commons
singleton Style 1.0 Style.qml
EOF
cat > "$test_modules/qs/Commons/Style.qml" <<'EOF'
pragma Singleton
import QtQuick

QtObject {
  readonly property int cornerRadius: 5
  readonly property var font: ({ family: "monospace", body: 12 })
  function space(value) { return value }
}
EOF

QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME="" \
  QML_IMPORT_PATH="$test_modules" XDG_CONFIG_HOME="$probe_config" \
  /usr/lib/qt6/bin/qmltestrunner -input "$test_dir/tst_history_chip.qml"
