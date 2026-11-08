import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SecurityKeyModel.js" as Model

// Resident SSH keys: downloads the key handles stored on the security key
// (ssh-keygen -K) into ~/.ssh, makes new ones there, and lists the ones in
// ~/.ssh, each in its own box: remove the copy (the key keeps it), delete
// the key from the security key for good, and, when its application names a
// git host, have ssh use it for that host (~/.ssh/config.d). Shown for keys
// that keep resident credentials, and while ~/.ssh holds such keys.
Section {
  id: ssh

  property var strings: null
  property var device: null
  // key-helper's entries: { name, application, host, hostState }.
  property var present: []
  // Suggestions for a new key: { user, comment }.
  property var defaults: ({ user: "", comment: "" })
  // The form for a new key is open (SecurityKey.qml owns it, for Escape).
  property bool creating: false
  // The key just made: { name, publicKey }, or null.
  property var created: null
  // The remove or delete button waiting for confirmation (Model.removeId), or "".
  property string pending: ""
  property bool busy: false
  property bool running: false
  // The PIN dialog is over the card. No text input lives behind it: the
  // form, the minutes editor and the public key go meanwhile (a text input
  // watches the clipboard for as long as it exists) and come back once it
  // closes, the form with what it held (form*).
  property bool covered: false
  property string statusText: ""
  property string statusTone: "info"
  property color urgent: Commons.Color.urgent

  signal importRequested()
  signal createOpened()
  signal createClosed()
  signal createRequested(var options)
  signal removeRequested(string name)
  signal deleteRequested(string name)
  signal hostRequested(string name, bool enable)
  signal persistRequested(string name, int minutes)
  // Sets the host up with its connection reuse, as omarchy-yubikey asks for
  // both together.
  signal hostEnableRequested(string name, int minutes)
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

  function focusDelete(name) {
    for (var i = 0; i < keyRows.count; i++) {
      var row = keyRows.itemAt(i)
      if (row && row.modelData.name === name) row.deleteButton.forceActiveFocus()
    }
  }

  // Back to the button the PIN dialog came from once it closes.
  function focusAction() {
    if (ssh.creating && createLoader.item) createLoader.item.focusFirst()
    else if (importButton.visible) importButton.forceActiveFocus()
  }

  // The key whose host is being set up, or whose connection reuse is being
  // changed, or "". Its number field exists only meanwhile (a text input
  // watches the clipboard). SecurityKey.qml opens it after an import or a new
  // key whose host isn't set up yet.
  property string persistEditing: ""

  function persistText(minutes) {
    return minutes > 0
      ? ssh.t("securityKey.ssh.persistOn", "Reuse connections: %1 min").arg(Commons.I18n.formatNumber(minutes))
      : ssh.t("securityKey.ssh.persistOff", "Reuse connections: no")
  }

  // What the form holds, kept here: its text fields exist only while it is
  // open (createLoader), since a text input watches the clipboard for as long
  // as it exists, shown or not.
  property string formAlgorithm: "ed25519-sk"
  property string formApplication: ""
  property string formUser: ""
  property bool formVerify: true
  property bool formTouch: true
  property string formComment: ""

  // The form, with fresh suggestions each time it opens.
  function openForm() {
    if (ssh.busy || !ssh.device) return
    ssh.formAlgorithm = "ed25519-sk"
    ssh.formApplication = ""
    ssh.formUser = ssh.defaults.user || ""
    ssh.formVerify = true
    ssh.formTouch = true
    ssh.formComment = ssh.defaults.comment || ""
    ssh.createOpened()
  }

  onCreatingChanged: if (ssh.creating) Qt.callLater(function() { if (createLoader.item) createLoader.item.focusFirst() })

  readonly property var options: ({
    algorithm: ssh.formAlgorithm,
    application: ssh.formApplication.trim(),
    user: ssh.formUser.trim(),
    verify: ssh.formVerify,
    touch: ssh.formTouch,
    comment: ssh.formComment.trim()
  })
  readonly property string problem: Model.createProblem(ssh.options)

  function create() {
    if (ssh.busy || ssh.problem !== "") return
    ssh.createRequested(ssh.options)
  }

  function hostText(entry) {
    if (entry.hostState === "on") return ssh.t("securityKey.ssh.hostOn", "ssh uses it for %1, without the agent.").arg(entry.host)
    if (entry.hostState === "edited" || entry.hostState === "foreign")
      return ssh.t("securityKey.ssh.hostLeftAlone", "%1 wasn't written by this overlay, or was changed by hand: it is left alone.")
        .arg(Model.ltr("~/.ssh/config.d/" + entry.host + ".conf"))
    return ""
  }

  glyph: "󰣀"
  title: t("securityKey.ssh.title")
  subtitle: t("securityKey.ssh.subtitle")

  // -- the keys in ~/.ssh ---------------------------------------------------

  Repeater {
    id: keyRows
    model: ssh.creating ? [] : ssh.present

    Rectangle {
      id: row
      required property var modelData
      required property int index
      readonly property alias removeButton: removeButton
      readonly property alias deleteButton: deleteButton
      readonly property bool asking: ssh.pending === Model.removeId("ssh", modelData.name)
      readonly property bool askingDelete: ssh.pending === Model.removeId("sshdel", modelData.name)
      readonly property string removeLabel: asking ? ssh.t("securityKey.fido.confirmRemove") : ssh.t("securityKey.ssh.removeCopy")
      width: parent ? parent.width : 0
      height: rowContent.implicitHeight + Style.spacing.lg * 2
      radius: Style.cornerRadius
      color: "transparent"
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: askingDelete ? ssh.urgent : Qt.rgba(ssh.foreground.r, ssh.foreground.g, ssh.foreground.b, 0.2)

      Column {
        id: rowContent
        x: Style.spacing.lg
        y: Style.spacing.lg
        width: parent.width - Style.spacing.lg * 2
        spacing: Style.spacing.sm

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "󰣀  " + Model.ltr("~/.ssh/" + row.modelData.name)
          horizontalAlignment: Text.AlignLeft
          color: ssh.foreground
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
        }

        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          text: [row.modelData.application ? Model.ltr(row.modelData.application) : "", ssh.hostText(row.modelData)]
            .filter(function(s) { return s !== "" }).join(" · ")
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignLeft
          color: row.modelData.hostState === "on" ? ssh.accent : ssh.foreground
          opacity: row.modelData.hostState === "on" ? 1 : 0.7
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.caption
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.controlGap

          Button {
            id: removeButton
            focusable: true
            bordered: true
            enabled: !ssh.busy
            iconText: "󰩺"
            text: row.index < 9 ? Model.shortcut(row.removeLabel, "Alt+" + (row.index + 1)) : row.removeLabel
            selected: row.asking
            foreground: row.asking ? ssh.urgent : ssh.foreground
            accent: ssh.accent
            fontFamily: ssh.fontFamily
            onClicked: ssh.removeRequested(row.modelData.name)
          }

          Button {
            id: deleteButton
            visible: !!ssh.device
            focusable: true
            bordered: true
            enabled: !ssh.busy
            iconText: "󰆴"
            text: row.askingDelete ? ssh.t("securityKey.ssh.confirmDelete") : ssh.t("securityKey.ssh.delete")
            selected: row.askingDelete
            foreground: ssh.urgent
            accent: ssh.accent
            fontFamily: ssh.fontFamily
            onClicked: ssh.deleteRequested(row.modelData.name)
          }

          Button {
            visible: row.modelData.hostState === "on" || row.modelData.hostState === "off"
            focusable: true
            bordered: true
            enabled: !ssh.busy
            iconText: row.modelData.hostState === "on" ? "󰅙" : "󰒓"
            text: (row.modelData.hostState === "on" ? ssh.t("securityKey.ssh.hostDisable", "Stop using for %1")
                                                     : ssh.t("securityKey.ssh.hostEnable", "Use for %1")).arg(row.modelData.host)
            foreground: ssh.foreground
            accent: ssh.accent
            fontFamily: ssh.fontFamily
            selected: row.modelData.hostState === "off" && ssh.persistEditing === row.modelData.name
            // Setting up asks for the minutes first; stopping is immediate.
            onClicked: row.modelData.hostState === "on" ? ssh.hostRequested(row.modelData.name, false)
              : (ssh.persistEditing = ssh.persistEditing === row.modelData.name ? "" : row.modelData.name)
          }

          Button {
            visible: row.modelData.hostState === "on"
            focusable: true
            bordered: true
            enabled: !ssh.busy
            iconText: "󰑓"
            text: ssh.persistText(row.modelData.persistMinutes || 0)
            selected: ssh.persistEditing === row.modelData.name
            foreground: ssh.foreground
            accent: ssh.accent
            fontFamily: ssh.fontFamily
            onClicked: ssh.persistEditing = ssh.persistEditing === row.modelData.name ? "" : row.modelData.name
          }
        }

        // How long connections to the host are reused, as omarchy-yubikey
        // offers it: whole minutes from 0 (the default) to 1440.
        Loader {
          width: parent.width
          // Never while hidden: SecurityKey.qml closes it with the tab too.
          active: ssh.visible && !ssh.covered && ssh.persistEditing === row.modelData.name
            && (row.modelData.hostState === "on" || row.modelData.hostState === "off")
          visible: active

          sourceComponent: Component {
            Column {
              spacing: Style.spacing.sm

              function minutes() {
                var typed = parseInt(minutesField.field.contentItem.text, 10)
                var value = isNaN(typed) ? minutesField.field.value : typed
                return Math.max(0, Math.min(1440, value))
              }

              function apply() {
                if (ssh.busy) return
                if (row.modelData.hostState === "on") ssh.persistRequested(row.modelData.name, minutes())
                else ssh.hostEnableRequested(row.modelData.name, minutes())
              }

              NumberField {
                id: minutesField
                label: ssh.t("securityKey.ssh.persistLabel", "Reuse connections to %1 for (minutes)").arg(row.modelData.host)
                from: 0
                to: 1440
                stepSize: 1
                value: row.modelData.persistMinutes || 0
                foreground: ssh.foreground
                accent: ssh.accent
                fontFamily: ssh.fontFamily
                Component.onCompleted: Qt.callLater(function() { minutesField.field.forceActiveFocus() })
                Keys.onReturnPressed: parent.apply()
                Keys.onEnterPressed: parent.apply()
              }

              Text {
                width: rowContent.width
                textFormat: Text.PlainText
                text: ssh.t("securityKey.ssh.persistHint")
                wrapMode: Text.Wrap
                color: ssh.foreground
                opacity: 0.6
                font.family: ssh.fontFamily
                font.pixelSize: Style.font.caption
              }

              Flow {
                width: rowContent.width
                spacing: Style.spacing.controlGap

                Button {
                  focusable: true
                  bordered: true
                  enabled: !ssh.busy
                  iconText: row.modelData.hostState === "on" ? "󰄬" : "󰒓"
                  text: Model.shortcut(row.modelData.hostState === "on" ? ssh.t("securityKey.ssh.apply")
                    : ssh.t("securityKey.ssh.hostEnable", "Use for %1").arg(row.modelData.host), "Enter")
                  foreground: ssh.foreground
                  accent: ssh.accent
                  fontFamily: ssh.fontFamily
                  onClicked: parent.parent.apply()
                }

                Button {
                  focusable: true
                  bordered: true
                  text: Model.shortcut(ssh.t("securityKey.cancel"), "Esc")
                  foreground: ssh.foreground
                  accent: ssh.accent
                  fontFamily: ssh.fontFamily
                  onClicked: ssh.persistEditing = ""
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: row.askingDelete
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.deleteWarning")
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignLeft
          color: ssh.urgent
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // -- the key just made: its public key, to hand to the server ----------

  Column {
    width: parent.width
    visible: !ssh.creating && !!ssh.created
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: ssh.created ? ssh.t("securityKey.ssh.created", "Created %1. Its public key, for the server or git host:").arg(Model.ltr("~/.ssh/" + ssh.created.name)) : ""
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignLeft
      color: ssh.foreground
      font.family: ssh.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // Read-only, and created only while there is a key to show.
    Loader {
      width: parent.width
      active: ssh.visible && !ssh.covered && !ssh.creating && !!ssh.created

      sourceComponent: Component {
        TextEdit {
          readOnly: true
          selectByMouse: true
          textFormat: TextEdit.PlainText
          text: ssh.created ? ssh.created.publicKey : ""
          wrapMode: TextEdit.WrapAnywhere
          color: ssh.foreground
          selectionColor: ssh.accent
          font.family: "monospace"
          font.pixelSize: Style.font.caption
        }
      }
    }

    Button {
      focusable: true
      bordered: true
      iconText: "󰆏"
      text: ssh.t("securityKey.ssh.copy")
      foreground: ssh.foreground
      accent: ssh.accent
      fontFamily: ssh.fontFamily
      onClicked: if (ssh.created) Quickshell.clipboardText = ssh.created.publicKey
    }
  }

  // -- a new key --------------------------------------------------------------

  Loader {
    id: createLoader
    width: parent.width
    // Never while hidden: SecurityKey.qml closes the form with the tab too.
    active: ssh.creating && ssh.visible && !ssh.covered
    visible: active

    sourceComponent: Component {
      Column {
        id: createForm
        width: createLoader.width
        spacing: Style.spacing.sm

        function focusFirst() { applicationField.forceActiveFocus() }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.createTitle")
          color: ssh.foreground
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.algorithm")
          color: ssh.foreground
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        ButtonGroup {
          id: algorithmGroup
          options: [{ value: "ed25519-sk", label: "ed25519-sk" }, { value: "ecdsa-sk", label: "ecdsa-sk" }]
          value: ssh.formAlgorithm
          foreground: ssh.foreground
          accent: ssh.accent
          fontFamily: ssh.fontFamily
          onChanged: function(value) { ssh.formAlgorithm = value }
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.algorithmHint")
          wrapMode: Text.Wrap
          color: ssh.foreground
          opacity: 0.6
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.application")
          color: ssh.foreground
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        TextField {
          id: applicationField
          Component.onCompleted: text = ssh.formApplication
          onTextChanged: ssh.formApplication = text
          width: parent.width
          foreground: ssh.foreground
          accent: ssh.accent
          inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
          placeholderText: "github.com"
          maximumLength: 128
          // Enter makes the key; Alt+key never reaches the text.
          Keys.onPressed: function(event) {
            if (event.modifiers & Qt.AltModifier) event.accepted = true
          }
          onAccepted: ssh.create()
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.applicationHint")
          wrapMode: Text.Wrap
          color: ssh.foreground
          opacity: 0.6
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.user")
          color: ssh.foreground
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        TextField {
          id: userField
          Component.onCompleted: text = ssh.formUser
          onTextChanged: ssh.formUser = text
          width: parent.width
          foreground: ssh.foreground
          accent: ssh.accent
          inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
          maximumLength: 64
          // Enter makes the key; Alt+key never reaches the text.
          Keys.onPressed: function(event) {
            if (event.modifiers & Qt.AltModifier) event.accepted = true
          }
          onAccepted: ssh.create()
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.userHint")
          wrapMode: Text.Wrap
          color: ssh.foreground
          opacity: 0.6
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.caption
        }

        Toggle {
          id: verifyToggle
          width: parent.width
          label: ssh.t("securityKey.ssh.verify")
          checked: ssh.formVerify
          foreground: ssh.foreground
          accent: ssh.accent
          fontFamily: ssh.fontFamily
          onClicked: ssh.formVerify = !ssh.formVerify
        }

        Toggle {
          id: touchToggle
          width: parent.width
          label: ssh.t("securityKey.ssh.touch")
          description: checked ? "" : ssh.t("securityKey.ssh.touchOff")
          checked: ssh.formTouch
          foreground: ssh.foreground
          accent: ssh.accent
          fontFamily: ssh.fontFamily
          onClicked: ssh.formTouch = !ssh.formTouch
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.t("securityKey.ssh.comment")
          color: ssh.foreground
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        TextField {
          id: commentField
          Component.onCompleted: text = ssh.formComment
          onTextChanged: ssh.formComment = text
          width: parent.width
          foreground: ssh.foreground
          accent: ssh.accent
          inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
          maximumLength: 128
          // Enter makes the key; Alt+key never reaches the text.
          Keys.onPressed: function(event) {
            if (event.modifiers & Qt.AltModifier) event.accepted = true
          }
          onAccepted: ssh.create()
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: ssh.problem !== "" ? ssh.t(Model.createProblemKey(ssh.problem))
            : ssh.t("securityKey.ssh.fileName", "Saved as %1").arg(Model.ltr("~/.ssh/" + Model.handleName(ssh.options.algorithm, ssh.options.application, ssh.options.user)))
          wrapMode: Text.WrapAnywhere
          horizontalAlignment: Text.AlignLeft
          color: ssh.problem !== "" ? ssh.urgent : ssh.foreground
          opacity: ssh.problem !== "" ? 1 : 0.7
          font.family: ssh.fontFamily
          font.pixelSize: Style.font.caption
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.controlGap

          Button {
            focusable: true
            bordered: true
            enabled: !ssh.busy && ssh.problem === ""
            iconText: "󰐕"
            text: Model.shortcut(ssh.t("securityKey.ssh.createKey"), "Enter")
            foreground: ssh.foreground
            accent: ssh.accent
            fontFamily: ssh.fontFamily
            onClicked: ssh.create()
          }

          Button {
            focusable: true
            bordered: true
            text: Model.shortcut(ssh.t("securityKey.cancel"), "Esc")
            foreground: ssh.foreground
            accent: ssh.accent
            fontFamily: ssh.fontFamily
            onClicked: ssh.createClosed()
          }
        }
      }
    }
  }

  // -- import and create --------------------------------------------------

  Flow {
    width: parent.width
    visible: !!ssh.device && !ssh.creating
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
      visible: !ssh.running
      focusable: true
      bordered: true
      enabled: !ssh.busy
      iconText: "󰐕"
      text: Model.shortcut(ssh.t("securityKey.ssh.create"), "Alt+N")
      foreground: ssh.foreground
      accent: ssh.accent
      fontFamily: ssh.fontFamily
      onClicked: ssh.openForm()
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
    visible: ssh.present.length > 0 && !ssh.creating
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
