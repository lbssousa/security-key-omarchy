import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SecurityKeyModel.js" as Model

// Asks for the key's PIN before an action that needs it (registering the
// key, importing the SSH keys), then stays while the key waits for a touch:
// the PIN field gives its place to the touch notice.
// A wrong PIN leaves it open with the field cleared; success closes it.
// Escape (handled by SecurityKey.qml) cancels or closes; Enter in the
// field submits.
BorderSurface {
  id: dialog

  property var strings: null
  property string glyph: ""
  property string title: ""
  // The action's own name, on the button that runs it.
  property string actionText: ""
  property string message: ""
  // "info", "success" or "error".
  property string tone: "info"
  property bool running: false
  // -1 when the key doesn't say.
  property int pinRetries: -1

  property string fontFamily: Style.font.menuFamily
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent

  signal submitted(string pin)
  signal cancelRequested()

  function t(key, fallback) { return dialog.strings ? dialog.strings.t(key, fallback) : (fallback || key) }

  // The PIN never outlives the command that took it.
  function submit() {
    if (dialog.running || !pinLoader.item) return
    var pin = pinLoader.item
    if (pin.text === "") {
      pin.forceActiveFocus()
      return
    }
    var value = pin.text
    pin.text = ""
    dialog.submitted(value)
  }

  // The field exists only while the PIN can be typed (pinLoader): like any
  // text input, it reads every clipboard offer for as long as it exists, so
  // it goes while the key waits for a touch. Cancel holds the focus meanwhile.
  onRunningChanged: if (running) cancelButton.forceActiveFocus()

  function clear() { if (pinLoader.item) pinLoader.item.text = "" }
  function focusPin() { if (pinLoader.item) pinLoader.item.forceActiveFocus() }

  radius: Style.cornerRadius
  padding: Style.spacing.panelPadding
  height: content.implicitHeight + contentTopInset + contentBottomInset

  MouseArea { anchors.fill: parent; onClicked: dialog.focusPin() }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: dialog.contentTopInset
    anchors.leftMargin: dialog.contentLeftInset
    anchors.rightMargin: dialog.contentRightInset
    spacing: Style.spacing.xxl

    Text {
      id: glyphText
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: dialog.glyph
      color: dialog.tone === "error" ? dialog.urgent : dialog.accent
      font.family: dialog.fontFamily
      font.pixelSize: Style.font.displayLarge

      SequentialAnimation on opacity {
        running: dialog.running && !Style.reduceMotion
        loops: Animation.Infinite
        onRunningChanged: if (!running) glyphText.opacity = 1
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: dialog.title
      horizontalAlignment: Text.AlignHCenter
      color: dialog.foreground
      font.family: dialog.fontFamily
      font.pixelSize: Style.font.heading
      elide: Text.ElideRight
    }

    StatusLine {
      width: parent.width
      visible: !dialog.running && text !== ""
      text: dialog.message
      tone: dialog.tone
      horizontalAlignment: Text.AlignHCenter
      foreground: dialog.foreground
      accent: dialog.accent
      urgent: dialog.urgent
    }

    // The PIN field, or, once the PIN went, what the key waits for in its
    // place (the same height, so the dialog doesn't jump).
    Item {
      width: parent.width
      // The field's height, kept for when it's gone.
      property real fieldHeight: 0
      height: Math.max(fieldHeight, touchLine.implicitHeight)

      Loader {
        id: pinLoader
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        active: !dialog.running
        onLoaded: parent.fieldHeight = item.implicitHeight

        sourceComponent: Component {
          PinField {
            width: pinLoader.width
            placeholderText: dialog.t("securityKey.pinPlaceholder")
            foreground: dialog.foreground
            accent: dialog.accent
            onAccepted: dialog.submit()
          }
        }
      }

      StatusLine {
        id: touchLine
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: dialog.running
        text: dialog.message
        tone: dialog.tone
        running: dialog.running
        horizontalAlignment: Text.AlignHCenter
        foreground: dialog.foreground
        accent: dialog.accent
        urgent: dialog.urgent
      }
    }

    Text {
      width: parent.width
      visible: dialog.pinRetries >= 0 && dialog.pinRetries < 8
      textFormat: Text.PlainText
      text: dialog.t("securityKey.pinRetries", "%1 PIN tries left").arg(Commons.I18n.formatNumber(dialog.pinRetries))
      horizontalAlignment: Text.AlignHCenter
      color: dialog.urgent
      font.family: dialog.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.controlGap

      Button {
        visible: !dialog.running
        focusable: true
        bordered: true
        iconText: dialog.glyph
        text: Model.shortcut(dialog.actionText, "Enter")
        foreground: dialog.foreground
        accent: dialog.accent
        fontFamily: dialog.fontFamily
        onClicked: dialog.submit()
      }

      Button {
        id: cancelButton
        focusable: true
        bordered: true
        text: Model.shortcut(dialog.t("securityKey.cancel"), "Esc")
        foreground: dialog.foreground
        accent: dialog.accent
        fontFamily: dialog.fontFamily
        onClicked: dialog.cancelRequested()
      }
    }
  }
}
