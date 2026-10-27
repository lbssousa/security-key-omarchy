import QtQuick
import qs.Commons
import qs.Ui

// The key's PIN: hidden as typed, never kept once the command took it
// (PinDialog clears it). Enter submits. Alt+key never reaches the text.
TextField {
  id: field

  Keys.onPressed: function(event) {
    if (event.modifiers & Qt.AltModifier) event.accepted = true
  }

  password: true
  maximumLength: 63
  inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
  width: Style.space(180)
}
