import QtQuick
import Quickshell.Io

// Runs key-helper while `active` and relays its NDJSON events. Turning
// `active` off stops the helper (SIGTERM), which ends whatever it runs (a
// registration waiting for a touch, a download) on its way out.
Item {
  id: client

  property bool active: false
  readonly property bool running: proc.running

  signal event(var message)
  // The helper ended while still wanted (python missing, a crash).
  signal lost()

  onActiveChanged: proc.running = active

  // Starts the helper again after it was lost; it reports the key on start.
  function restart() {
    if (active && !proc.running) proc.running = true
  }

  function send(command) {
    if (proc.running) proc.write(JSON.stringify(command) + "\n")
  }

  Process {
    id: proc
    command: ["python3", "-I", String(Qt.resolvedUrl("key-helper")).replace(/^file:\/\//, "")]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var message
        try {
          message = JSON.parse(line)
        } catch (e) {
          return
        }
        if (message && typeof message.type === "string") client.event(message)
      }
    }
    onExited: function(exitCode) {
      if (client.active) client.lost()
    }
  }
}
