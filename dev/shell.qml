import QtQuick
import Quickshell

// `just dev`: the overlay in its own Quickshell instance, open at once;
// closing it (Escape) ends the instance.
ShellRoot {
  SecurityKey {
    id: overlay
    Component.onCompleted: overlay.open("{}")
    onOpenedChanged: if (!opened) Qt.quit()
  }
}
