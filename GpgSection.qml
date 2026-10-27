import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SecurityKeyModel.js" as Model

// The OpenPGP key stored on the card: who it belongs to, whether gpg knows
// it (missing / public only / linked to the card) and trusts it, and the
// buttons that import it, trust it and take it out of the keyring again
// (the key stays on the card). Shown only for keys with an OpenPGP
// applet.
Section {
  id: gpg

  property var strings: null
  property var card: null
  // "missing", "public" or "ready".
  property string keyState: ""
  property bool trusted: false
  // The remove button waiting for confirmation (Model.removeId), or "".
  property string pending: ""
  property bool busy: false
  property bool running: false
  property string statusText: ""
  property string statusTone: "info"
  property color urgent: Commons.Color.urgent

  readonly property bool canImport: keyState === "missing" || keyState === "public"
  readonly property bool canTrust: keyState !== "" && keyState !== "missing" && !trusted
  readonly property bool canRemove: keyState === "public" || keyState === "ready"
  readonly property bool asking: pending === "gpg"

  signal importRequested()
  signal trustRequested()
  signal removeRequested()

  // Alt+D lands on the remove button, so Enter confirms too.
  function focusRemove() {
    if (removeButton.visible) removeButton.forceActiveFocus()
  }

  function t(key, fallback) { return gpg.strings ? gpg.strings.t(key, fallback) : (fallback || key) }

  glyph: "󰷖"
  title: t("securityKey.gpg.title")
  subtitle: t("securityKey.gpg.subtitle")

  Column {
    width: parent.width
    spacing: Style.spacing.xxs

    Text {
      width: parent.width
      visible: !!gpg.card && gpg.card.holder !== ""
      textFormat: Text.PlainText
      text: gpg.card ? gpg.t("securityKey.gpg.holder", "Holder: %1").arg(gpg.card.holder) : ""
      horizontalAlignment: Text.AlignLeft
      color: gpg.foreground
      font.family: gpg.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: !!gpg.card && gpg.card.fingerprints.length > 0
      textFormat: Text.PlainText
      text: gpg.card && gpg.card.fingerprints.length > 0 ? Model.formatFingerprint(gpg.card.fingerprints[0]) : ""
      horizontalAlignment: Text.AlignLeft
      color: gpg.foreground
      opacity: 0.7
      font.family: gpg.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: {
        var parts = []
        if (Model.keyStateKey(gpg.keyState) !== "") parts.push(gpg.t(Model.keyStateKey(gpg.keyState)))
        if (gpg.trusted) parts.push(gpg.t("securityKey.gpg.trusted"))
        if (gpg.card && gpg.card.serial) parts.push(gpg.t("securityKey.gpg.serial", "Card %1").arg(gpg.card.serial))
        return parts.join(" · ")
      }
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignLeft
      color: gpg.keyState === "ready" ? gpg.accent : gpg.foreground
      font.family: gpg.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Flow {
    width: parent.width
    spacing: Style.spacing.controlGap
    visible: gpg.canImport || gpg.canTrust || gpg.canRemove

    Button {
      visible: gpg.canImport
      focusable: true
      bordered: true
      enabled: !gpg.busy
      iconText: "󰇚"
      text: Model.shortcut(gpg.keyState === "public" ? gpg.t("securityKey.gpg.link") : gpg.t("securityKey.gpg.import"), "Alt+I")
      foreground: gpg.foreground
      accent: gpg.accent
      fontFamily: gpg.fontFamily
      onClicked: gpg.importRequested()
    }

    Button {
      visible: gpg.canTrust
      focusable: true
      bordered: true
      enabled: !gpg.busy
      iconText: "󰄬"
      text: Model.shortcut(gpg.t("securityKey.gpg.trust"), "Alt+T")
      foreground: gpg.foreground
      accent: gpg.accent
      fontFamily: gpg.fontFamily
      onClicked: gpg.trustRequested()
    }

    Button {
      id: removeButton
      visible: gpg.canRemove
      focusable: true
      bordered: true
      enabled: !gpg.busy
      iconText: "󰩺"
      text: Model.shortcut(gpg.asking ? gpg.t("securityKey.fido.confirmRemove") : gpg.t("securityKey.gpg.remove"), "Alt+D")
      selected: gpg.asking
      foreground: gpg.asking ? gpg.urgent : gpg.foreground
      accent: gpg.accent
      fontFamily: gpg.fontFamily
      onClicked: gpg.removeRequested()
    }
  }

  StatusLine {
    width: parent.width
    text: gpg.statusText
    tone: gpg.statusTone
    running: gpg.running
    foreground: gpg.foreground
    accent: gpg.accent
    urgent: gpg.urgent
  }
}
