import QtQuick
import qs.Commons
import qs.Commons as Commons

// What a section is doing or how its last action went. While `running`,
// the line pulses (the key is waiting for a touch, gpg is fetching).
Text {
  id: line

  // "info", "success" or "error".
  property string tone: "info"
  property bool running: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent

  visible: text !== ""
  textFormat: Text.PlainText
  wrapMode: Text.Wrap
  horizontalAlignment: Text.AlignLeft
  color: tone === "error" ? urgent : tone === "success" || running ? accent : foreground
  font.family: Style.font.menuFamily
  font.pixelSize: Style.font.bodySmall

  SequentialAnimation on opacity {
    running: line.running && !Style.reduceMotion
    loops: Animation.Infinite
    onRunningChanged: if (!running) line.opacity = 1
    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
  }
}
