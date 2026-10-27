import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SecurityKeyModel.js" as Model

// Resident SSH keys: downloads the key handles stored on the security key
// (ssh-keygen -K) into ~/.ssh, and lists the ones there, each with its
// remove button (the key itself keeps them). Shown for keys that keep
// resident credentials, and while ~/.ssh holds such keys.
Section {
  id: ssh

  property var strings: null
  property var device: null
  property var present: []
  // Alt+N numbering goes on from the registered keys above.
  property int indexOffset: 0
  // The remove button waiting for confirmation (Model.removeId), or "".
  property string pending: ""
  property bool busy: false
  property bool running: false
  property string statusText: ""
  property string statusTone: "info"
  property color urgent: Commons.Color.urgent

  signal importRequested()
  signal removeRequested(string name)
  signal cancelRequested()

  function t(key, fallback) { return ssh.strings ? ssh.strings.t(key, fallback) : (fallback || key) }

  function submit() {
    if (ssh.busy || !ssh.device) return
    ssh.importRequested()
  }

  // Alt+N lands on the remove button of that key, so Enter confirms too.
  function focusRemove(index) {
    var row = keyRows.itemAt(index)
    if (row) row.removeButton.forceActiveFocus()
  }

  // Back to the import button once the PIN dialog closes.
  function focusAction() {
    if (importButton.visible) importButton.forceActiveFocus()
  }

  glyph: "󰣀"
  title: t("securityKey.ssh.title")
  subtitle: t("securityKey.ssh.subtitle")

  Repeater {
    id: keyRows
    model: ssh.present

    Item {
      required property var modelData
      required property int index
      readonly property alias removeButton: removeButton
      readonly property int number: ssh.indexOffset + index
      readonly property bool asking: ssh.pending === Model.removeId("ssh", modelData)
      readonly property string removeLabel: asking ? ssh.t("securityKey.fido.confirmRemove") : ssh.t("securityKey.fido.remove")
      width: parent ? parent.width : 0
      height: removeButton.implicitHeight

      Text {
        anchors.left: parent.left
        anchors.right: removeButton.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "󰣀  " + Model.ltr("~/.ssh/" + modelData)
        horizontalAlignment: Text.AlignLeft
        color: ssh.foreground
        font.family: ssh.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }

      Button {
        id: removeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        focusable: true
        bordered: true
        enabled: !ssh.busy
        iconText: "󰩺"
        text: number < 9 ? Model.shortcut(removeLabel, "Alt+" + (number + 1)) : removeLabel
        selected: asking
        foreground: asking ? ssh.urgent : ssh.foreground
        accent: ssh.accent
        fontFamily: ssh.fontFamily
        onClicked: ssh.removeRequested(modelData)
      }
    }
  }

  Flow {
    width: parent.width
    visible: !!ssh.device
    spacing: Style.spacing.controlGap

    Button {
      id: importButton
      visible: !ssh.running
      focusable: true
      bordered: true
      enabled: !ssh.busy
      iconText: "󰇚"
      text: Model.shortcut(ssh.t("securityKey.ssh.import"), "Alt+S")
      foreground: ssh.foreground
      accent: ssh.accent
      fontFamily: ssh.fontFamily
      onClicked: ssh.submit()
    }

    Button {
      visible: ssh.running
      focusable: true
      bordered: true
      text: Model.shortcut(ssh.t("securityKey.cancel"), "Esc")
      foreground: ssh.foreground
      accent: ssh.accent
      fontFamily: ssh.fontFamily
      onClicked: ssh.cancelRequested()
    }
  }

  StatusLine {
    width: parent.width
    text: ssh.statusText
    tone: ssh.statusTone
    running: ssh.running
    foreground: ssh.foreground
    accent: ssh.accent
    urgent: ssh.urgent
  }

  Text {
    width: parent.width
    visible: ssh.present.length > 0
    textFormat: Text.PlainText
    text: ssh.t("securityKey.ssh.touchNote")
    wrapMode: Text.Wrap
    horizontalAlignment: Text.AlignLeft
    color: ssh.foreground
    opacity: 0.6
    font.family: ssh.fontFamily
    font.pixelSize: Style.font.caption
  }
}
