import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SecurityKeyModel.js" as Model

// FIDO2/U2F for sudo and polkit: the keys registered in the user's own
// pam_u2f list and the button that registers the key plugged in.
// SecurityKey.qml runs the commands, asking for the PIN first (PinDialog).
Section {
  id: fido

  property var strings: null
  property var credentials: []
  property var device: null
  // SecurityKeyModel.pamState(): kind "ok", "shared" or "missing".
  property var pam: ({ kind: "ok", path: "" })
  property int sharedCount: 0
  property bool busy: false
  property bool running: false
  // The remove button waiting for confirmation (Model.removeId), or "".
  property string pending: ""
  property string statusText: ""
  property string statusTone: "info"
  property color urgent: Commons.Color.urgent

  signal registerRequested()
  signal removeRequested(int index)
  signal cancelRequested()

  function t(key, fallback) { return fido.strings ? fido.strings.t(key, fallback) : (fallback || key) }

  function submit() {
    if (fido.busy || !fido.device) return
    fido.registerRequested()
  }

  // Back to the register button once the PIN dialog closes.
  function focusAction() {
    if (registerButton.visible) registerButton.forceActiveFocus()
  }

  // Alt+1-9 lands on the remove button of that key, so Enter confirms too.
  function focusRemove(index) {
    var row = credentialRows.itemAt(index)
    if (row) row.removeButton.forceActiveFocus()
  }

  glyph: "󰌆"
  title: t("securityKey.fido.title")
  subtitle: t("securityKey.fido.subtitle")

  Text {
    width: parent.width
    visible: fido.credentials.length === 0
    textFormat: Text.PlainText
    text: fido.t("securityKey.fido.none")
    color: fido.foreground
    opacity: 0.7
    font.family: fido.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    id: credentialRows
    model: fido.credentials

    Item {
      required property var modelData
      required property int index
      readonly property alias removeButton: removeButton
      width: parent ? parent.width : 0
      height: removeButton.implicitHeight

      Text {
        anchors.left: parent.left
        anchors.right: removeButton.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "󰌋  " + fido.t("securityKey.fido.credential", "Key %1").arg(Model.ltr(modelData.label + "…"))
        horizontalAlignment: Text.AlignLeft
        color: fido.foreground
        font.family: fido.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Button {
        id: removeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        focusable: true
        bordered: true
        enabled: !fido.busy
        iconText: "󰩺"
        text: index < 9 ? Model.shortcut(removeLabel, "Alt+" + (index + 1)) : removeLabel
        readonly property bool asking: fido.pending === Model.removeId("fido", index)
        readonly property string removeLabel: asking ? fido.t("securityKey.fido.confirmRemove") : fido.t("securityKey.fido.remove")
        selected: asking
        foreground: asking ? fido.urgent : fido.foreground
        accent: fido.accent
        fontFamily: fido.fontFamily
        onClicked: fido.removeRequested(index)
      }
    }
  }

  Flow {
    width: parent.width
    spacing: Style.spacing.controlGap
    visible: !!fido.device

    Button {
      id: registerButton
      visible: !fido.running
      focusable: true
      bordered: true
      enabled: !fido.busy
      iconText: "󰌆"
      text: Model.shortcut(fido.credentials.length > 0 ? fido.t("securityKey.fido.registerAnother") : fido.t("securityKey.fido.register"), "Alt+R")
      foreground: fido.foreground
      accent: fido.accent
      fontFamily: fido.fontFamily
      onClicked: fido.submit()
    }

    Button {
      visible: fido.running
      focusable: true
      bordered: true
      text: Model.shortcut(fido.t("securityKey.cancel"), "Esc")
      foreground: fido.foreground
      accent: fido.accent
      fontFamily: fido.fontFamily
      onClicked: fido.cancelRequested()
    }
  }

  Text {
    width: parent.width
    visible: !!fido.device && fido.device.clientPin === true && fido.device.pinRetries >= 0 && fido.device.pinRetries < 8
    textFormat: Text.PlainText
    text: fido.t("securityKey.pinRetries", "%1 PIN tries left").arg(fido.device ? fido.device.pinRetries : 0)
    color: fido.urgent
    font.family: fido.fontFamily
    font.pixelSize: Style.font.caption
  }

  StatusLine {
    width: parent.width
    text: fido.statusText
    tone: fido.statusTone
    running: fido.running
    foreground: fido.foreground
    accent: fido.accent
    urgent: fido.urgent
  }

  Text {
    width: parent.width
    visible: fido.pam.kind !== "ok"
    textFormat: Text.PlainText
    text: fido.pam.kind === "shared"
      ? fido.t("securityKey.fido.pam.shared", "sudo and polkit read keys from %1 (yours there: %2), not from your own list: an administrator has to switch pam_u2f to per-user lists before the keys registered here work there.").arg(Model.ltr(fido.pam.path)).arg(Commons.I18n.formatNumber(Math.max(0, fido.sharedCount)))
      : fido.t("securityKey.fido.pam.missing")
    wrapMode: Text.Wrap
    horizontalAlignment: Text.AlignLeft
    color: fido.foreground
    opacity: 0.7
    font.family: fido.fontFamily
    font.pixelSize: Style.font.caption
  }
}
