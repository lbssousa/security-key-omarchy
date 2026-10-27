import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SecurityKeyModel.js" as Model

// Security key overlay (YubiKey and other FIDO2 keys), after the Security
// page of lbssousa/noctalia: registers the key for sudo and polkit
// (pam_u2f, the user's own ~/.config/Yubico/u2f_keys), imports the OpenPGP
// key stored on its card, and copies its resident SSH keys into ~/.ssh. Each
// of the three has its own tab; the last two show only for keys that have
// those features. Summoned
// with `omarchy-shell shell summon lbssousa.security-key '{}'`
// (omarchy-security-key).
//
// Everything works from the keyboard: Tab walks the buttons, Enter
// activates, Ctrl+Tab and Ctrl+Shift+Tab (or Ctrl+Page Down/Up) switch tabs,
// and every action has its own key, shown on its button, which opens its
// tab too (Alt+R registers, Alt+1-9 removes a registered key or an SSH key,
// counted down the tab shown, Alt+I imports the OpenPGP key, Alt+T trusts
// it, Alt+D removes it from the keyring, Alt+S imports the SSH keys);
// removing asks again first; F5 refreshes, Escape cancels what runs or
// closes. When the card is taller than the screen it scrolls: the
// wheel, the scroll bar, Up/Down, Page Up/Down, Home/End, and Tab brings the
// focused button into view. Actions that need the key's PIN ask for it in a dialog
// over the card (PinDialog), which then waits for the touch.
//
// The key is reached through key-helper (KeyClient.qml), which runs only
// while the overlay is open and notices a key plugged in or pulled out.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  Commons.Translations { id: tr; directory: Qt.resolvedUrl("i18n") }

  // What the helper last reported.
  property bool loaded: false
  property bool helperLost: false
  property var devices: []
  property var credentials: []
  property string authfile: ""
  property var pam: ({})
  property int sharedCount: 0
  property var card: null
  property string keyState: ""
  property bool trusted: false
  property var sshKeys: []

  // The command running in the helper ("fido.register", "gpg.import", …).
  property string op: ""
  readonly property bool busy: op !== ""
  // The remove button waiting for its confirmation: Model.removeId(), or "".
  property string pendingRemove: ""

  // The action the PIN dialog is open for ("fido.register", "ssh.import"),
  // and what it says.
  property string pinOp: ""
  property var pinState: ({ text: "", tone: "info" })

  // The tab picked ("fido", "gpg", "ssh"); `tab` is the one shown, the
  // first when the picked one went away with the key.
  property string chosenTab: ""
  readonly property var tabs: root.loaded && !root.helperLost
    ? Model.tabs(root.devices, root.credentials, root.card, root.sshKeys) : []
  readonly property string tab: Model.currentTab(root.tabs, root.chosenTab)

  // The last outcome, per section.
  property var status: ({ fido: null, gpg: null, ssh: null })

  readonly property var device: Model.device(root.devices)
  readonly property var pamState: Model.pamState(root.pam, root.authfile)
  readonly property bool anything: root.device !== null || root.card !== null || root.credentials.length > 0

  property string fontFamily: Style.font.menuFamily
  property color accent: Commons.Color.polkit.accent
  property color background: Commons.Color.polkit.background
  property color foreground: Commons.Color.polkit.text
  property color urgent: Commons.Color.polkit.textError
  property var borderSpec: Border.surfaceSpec("polkit", "border", Commons.Color.polkit.border, Math.max(1, Style.space(2)), "border-alpha")
  readonly property int cardWidth: Math.min(Style.space(560), Math.max(Style.space(320), panel.width - Style.gapsOut * 2))

  function open(payloadJson) {
    root.op = ""
    root.pendingRemove = ""
    root.pinOp = ""
    root.chosenTab = ""
    root.status = { fido: null, gpg: null, ssh: null }
    root.helperLost = false
    root.opened = true
    Qt.callLater(refocus)
  }

  function close() {
    root.opened = false
    root.op = ""
    root.pinOp = ""
    pinDialog.clear()
  }

  function dismiss() {
    close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "lbssousa.security-key")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // The first field or button of the tab shown (past the tab bar), or the
  // card itself when there is none.
  function refocus() {
    if (!root.opened) return
    keyCatcher.forceActiveFocus()
    var first = keyCatcher.nextItemInFocusChain(true)
    if (first === tabBar) first = tabBar.nextItemInFocusChain(true)
    if (first && first !== keyCatcher && first !== tabBar && first.visible) first.forceActiveFocus()
  }

  // Shows a tab, back at the top of the card. A removal waiting for its
  // confirmation in the tab left asks no more.
  function selectTab(name) {
    if (root.tabs.indexOf(name) < 0 || name === root.tab) return
    root.chosenTab = name
    root.pendingRemove = ""
    scroller.scrollTo(0)
  }

  // Ctrl+Tab: the next tab, with the focus in it (or still on the tab bar).
  function stepTab(by) {
    if (root.tabs.length < 2) return
    selectTab(Model.nextTab(root.tabs, root.tab, by))
    if (!tabBar.activeFocus) root.refocus()
  }

  function setStatus(section, text, tone) {
    var next = { fido: root.status.fido, gpg: root.status.gpg, ssh: root.status.ssh }
    next[section] = text === "" ? null : { text: text, tone: tone }
    root.status = next
  }

  function statusOf(section) {
    return root.status[section] || { text: "", tone: "info" }
  }

  function errorText(code, detail) {
    var text = tr.t(Model.errorKey(code))
    return text.indexOf("%1") >= 0 ? text.arg(detail || code) : text
  }

  // -- actions ------------------------------------------------------------

  function run(command, statusText) {
    if (root.busy) return
    root.pendingRemove = ""
    root.op = command.cmd
    setStatus(Model.section(command.cmd), statusText || tr.t("securityKey.working"), "info")
    client.send(command)
  }

  function refresh() {
    if (root.busy) return
    if (client.running) client.send({ cmd: "refresh" })
    else {
      root.helperLost = false
      client.restart()
    }
  }

  // Registering and importing the SSH keys take the key's PIN when it has
  // one: asked in the dialog, which then shows the touch and any error.
  function askPin(command) {
    if (root.busy || root.device === null) return
    root.pendingRemove = ""
    if (root.device.clientPin !== true) {
      run({ cmd: command })
      return
    }
    setStatus(Model.section(command), "", "info")
    root.pinState = { text: tr.t("securityKey.error.pinRequired"), tone: "info" }
    root.pinOp = command
    Qt.callLater(pinDialog.focusPin)
  }

  function submitPin(pin) {
    if (root.busy || root.pinOp === "") return
    root.op = root.pinOp
    root.pinState = { text: tr.t("securityKey.working"), tone: "info" }
    client.send({ cmd: root.pinOp, pin: pin })
  }

  function closePin() {
    var section = Model.section(root.pinOp) === "ssh" ? sshSection : fidoSection
    selectTab(Model.section(root.pinOp))
    root.pinOp = ""
    pinDialog.clear()
    Qt.callLater(function() {
      if (section.visible) section.focusAction()
      else root.refocus()
    })
  }

  // Removing takes two presses of the same button (or its Alt key, or
  // Enter on it): the first asks, the second runs.
  function remove(kind, which) {
    if (root.busy) return
    var id = Model.removeId(kind, which)
    if (root.pendingRemove !== id) {
      root.pendingRemove = id
      return
    }
    if (kind === "fido") run({ cmd: "fido.remove", index: which })
    else if (kind === "ssh") run({ cmd: "ssh.remove", name: which })
    else run({ cmd: "gpg.remove" })
  }

  // A pending removal whose item went away (another key plugged in, the
  // file deleted elsewhere) asks no more.
  function checkPending() {
    var id = root.pendingRemove
    if (id === "") return
    var still = id === "gpg" ? gpgSection.canRemove
      : id.indexOf("fido:") === 0 ? Number(id.substring(5)) < root.credentials.length
      : root.sshKeys.indexOf(id.substring(4)) >= 0
    if (!still) root.pendingRemove = ""
  }

  function cancel() {
    if (root.busy) client.send({ cmd: "cancel" })
  }

  // -- helper events --------------------------------------------------------

  // Lists arrive through the signal as QVariantList; copy them into JS arrays.
  function list(value) {
    var out = []
    var items = value || []
    for (var i = 0; i < items.length; i++) out.push(items[i])
    return out
  }

  function onHelperEvent(m) {
    var section = Model.section(m.op)
    // The PIN dialog's command reports there, not in its section.
    var inDialog = root.pinOp !== "" && m.op === root.pinOp
    if (m.type === "state") {
      // The fields only exist once the key is known: focus the first of them then.
      if (!root.loaded) Qt.callLater(refocus)
      root.loaded = true
      root.devices = list(m.devices)
      root.credentials = list(m.credentials)
      root.authfile = String(m.authfile || "")
      root.pam = m.pam || ({})
      root.sharedCount = m.sharedCount || 0
      root.card = m.card ? { vendor: m.card.vendor, serial: m.card.serial, holder: m.card.holder,
                             url: m.card.url, fingerprints: list(m.card.fingerprints) } : null
      root.keyState = String(m.keyState || "")
      root.trusted = m.trusted === true
      root.sshKeys = list(m.sshKeys)
      checkPending()
      if (root.pinOp !== "" && !root.busy && root.device === null) closePin()
    } else if (m.type === "busy") {
      if (inDialog && m.stage === "touch") root.pinState = { text: tr.t("securityKey.touch"), tone: "info" }
      else if (m.stage === "touch") setStatus(section, tr.t("securityKey.touch"), "info")
      else if (m.stage === "fetch") setStatus(section, tr.t("securityKey.gpg.importing"), "info")
      // polkit's own dialog asks for the password (the shared authfile).
      else if (inDialog && m.stage === "auth") root.pinState = { text: tr.t("securityKey.working"), tone: "info" }
      else if (m.stage === "auth") setStatus(section, tr.t("securityKey.working"), "info")
    } else if (m.type === "done") {
      if (m.op === "fido.register") setStatus("fido", tr.t("securityKey.fido.registered"), "success")
      else if (m.op === "fido.remove") setStatus("fido", tr.t("securityKey.fido.removed"), "info")
      else if (m.op === "gpg.import") setStatus("gpg", tr.t("securityKey.gpg.imported"), "success")
      else if (m.op === "gpg.trust") setStatus("gpg", tr.t("securityKey.gpg.trustedDone"), "success")
      else if (m.op === "gpg.remove") setStatus("gpg", tr.t("securityKey.gpg.removed"), "info")
      else if (m.op === "ssh.remove") setStatus("ssh", tr.t("securityKey.ssh.removed", "Removed from ~/.ssh: %1").arg(Model.ltr(String(m.name || ""))), "info")
      else if (m.op === "ssh.import") {
        var lines = []
        var imported = list(m.imported)
        var skipped = list(m.skipped)
        if (imported.length > 0) lines.push(tr.t("securityKey.ssh.imported", "Imported: %1").arg(imported.map(Model.ltr).join(", ")))
        if (skipped.length > 0) lines.push(tr.t("securityKey.ssh.skipped", "Already in ~/.ssh, left alone: %1").arg(skipped.map(Model.ltr).join(", ")))
        setStatus("ssh", lines.join("\n"), imported.length > 0 ? "success" : "info")
      }
      if (root.op === m.op) root.op = ""
      if (inDialog) closePin()
    } else if (m.type === "error") {
      if (inDialog) {
        root.pinState = { text: errorText(m.code, m.detail), tone: "error" }
        Qt.callLater(pinDialog.focusPin)
      } else if (section !== "") {
        setStatus(section, errorText(m.code, m.detail), "error")
      }
      if (root.op === m.op) root.op = ""
    } else if (m.type === "cancelled") {
      if (section !== "") setStatus(section, "", "info")
      if (root.op === m.op) root.op = ""
      if (inDialog) closePin()
    }
  }

  // Direct keys for the actions (Alt+key, shown on each button); each works
  // only while its button would, and shows its tab first. Returns whether
  // the key was one of them.
  function altKey(key) {
    if (!root.opened || !root.loaded || root.helperLost || root.busy || root.pinOp !== "") return false
    var has = function(name) { return root.tabs.indexOf(name) >= 0 }
    if (key === Qt.Key_R && has("fido") && root.device !== null) {
      selectTab("fido")
      fidoSection.submit()
    } else if (key === Qt.Key_I && has("gpg") && gpgSection.canImport) {
      selectTab("gpg")
      root.run({ cmd: "gpg.import" })
    } else if (key === Qt.Key_T && has("gpg") && gpgSection.canTrust) {
      selectTab("gpg")
      root.run({ cmd: "gpg.trust" })
    } else if (key === Qt.Key_S && has("ssh") && root.device !== null) {
      selectTab("ssh")
      sshSection.submit()
    } else if (key === Qt.Key_D && has("gpg") && gpgSection.canRemove) {
      selectTab("gpg")
      root.remove("gpg")
      if (root.pendingRemove === "gpg") gpgSection.focusRemove()
    } else if (key >= Qt.Key_1 && key <= Qt.Key_9 && Model.removable(root.tab, root.credentials, root.sshKeys, key - Qt.Key_1) !== null) {
      var item = Model.removable(root.tab, root.credentials, root.sshKeys, key - Qt.Key_1)
      if (item.kind === "fido") {
        root.remove("fido", item.index)
        if (root.pendingRemove !== "") fidoSection.focusRemove(item.index)
      } else {
        root.remove("ssh", item.name)
        if (root.pendingRemove !== "") sshSection.focusRemove(item.index)
      }
    } else {
      return false
    }
    return true
  }

  KeyClient {
    id: client
    active: root.opened
    onEvent: function(message) { root.onHelperEvent(message) }
    onLost: {
      root.loaded = true
      root.helperLost = true
      root.op = ""
      if (root.pinOp !== "") root.closePin()
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-security-key"

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.polkit.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      // Fields and buttons take Tab and Enter themselves; what they leave
      // (Escape, F5) lands here. With the PIN dialog open, Escape cancels
      // what it runs or closes it, and nothing else reaches the card.
      Keys.onPressed: function(event) {
        if (root.pinOp !== "") {
          if (event.key === Qt.Key_Escape) {
            if (root.busy) root.cancel()
            else root.closePin()
            event.accepted = true
          }
        } else if (event.key === Qt.Key_Escape) {
          if (root.busy) root.cancel()
          else if (root.pendingRemove !== "") root.pendingRemove = ""
          else root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_F5) {
          root.refresh()
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && root.tabs.length > 1
                   && [Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_PageDown, Qt.Key_PageUp].indexOf(event.key) >= 0) {
          root.stepTab(event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown ? 1 : -1)
          event.accepted = true
        } else if (scroller.scrollKey(event.key)) {
          event.accepted = true
        } else if (event.modifiers & Qt.AltModifier) {
          event.accepted = root.altKey(event.key)
        }
      }

      BorderSurface {
        id: card
        width: root.cardWidth
        // Centred, so room for the title above (28 + 10) on both sides.
        // The key hints stay below the scrolling part, always in view.
        readonly property real footerSpace: footer.implicitHeight + Style.spacing.panelGap
        height: Math.min(content.implicitHeight + footerSpace + card.contentTopInset + card.contentBottomInset,
                         panel.height - Style.gapsOut * 2 - Style.space(76))
        radius: Style.cornerRadius
        anchors.centerIn: parent
        color: root.background
        borderSpec: root.borderSpec
        padding: Style.spacing.panelPadding

        MouseArea { anchors.fill: parent; onClicked: root.refocus() }

        Flickable {
          id: scroller
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.bottomMargin: card.contentBottomInset + card.footerSpace
          anchors.leftMargin: card.contentLeftInset
          anchors.rightMargin: card.contentRightInset
          contentHeight: content.implicitHeight
          clip: true
          // Under the PIN dialog: out of the Tab chain.
          enabled: root.pinOp === ""
          boundsBehavior: Flickable.StopAtBounds
          // Not while the window has no size yet (a height below zero): a
          // button focused then would scroll the card to a stale target.
          interactive: height > 0 && contentHeight > height

          Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

          readonly property real maxY: Math.max(0, contentHeight - height)
          readonly property real step: Style.space(48)

          function scrollTo(y) {
            var target = Math.max(0, Math.min(maxY, y))
            scrollAnimation.stop()
            if (Style.reduceMotion) {
              contentY = target
            } else {
              scrollAnimation.to = target
              scrollAnimation.start()
            }
          }

          // Up/Down, Page Up/Down, Home/End; false when the key isn't one of
          // them or there is nothing to scroll.
          function scrollKey(key) {
            if (!interactive) return false
            var by = { [Qt.Key_Up]: -step, [Qt.Key_Down]: step,
                       [Qt.Key_PageUp]: -height * 0.9, [Qt.Key_PageDown]: height * 0.9 }
            if (key in by) scrollTo((scrollAnimation.running ? scrollAnimation.to : contentY) + by[key])
            else if (key === Qt.Key_Home) scrollTo(0)
            else if (key === Qt.Key_End) scrollTo(maxY)
            else return false
            return true
          }

          // Tab moves the focus; keep what has it in view.
          readonly property Item focused: Window.activeFocusItem
          onFocusedChanged: {
            if (!interactive || !focused || focused === content) return
            var item = focused
            while (item && item !== content) item = item.parent
            if (!item) return
            var top = focused.mapToItem(content, 0, 0).y - Style.spacing.lg
            var bottom = top + focused.height + Style.spacing.lg * 2
            if (top < contentY) scrollTo(top)
            else if (bottom > contentY + height) scrollTo(bottom - height)
          }

          NumberAnimation {
            id: scrollAnimation
            target: scroller
            property: "contentY"
            duration: 140
            easing.type: Easing.OutCubic
          }

          Column {
            id: content
            // Room for the scroll bar while there is one.
            width: scroller.width - (scroller.interactive ? Style.space(14) : 0)
            spacing: Style.spacing.panelGap

            // The key.
            Row {
              width: parent.width
              spacing: Style.spacing.xxl

              Text {
                id: keyGlyph
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰌋"
                color: root.anything ? root.accent : root.foreground
                opacity: root.anything ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - keyGlyph.width - parent.spacing
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.device ? root.device.name
                    : root.card ? (root.card.vendor + " " + root.card.serial).trim()
                    : tr.t("securityKey.connect")
                  horizontalAlignment: Text.AlignLeft
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.helperLost ? tr.t("securityKey.helperFailed")
                    : !root.loaded ? tr.t("securityKey.working")
                    : !root.device && !root.card ? tr.t("securityKey.connectHint")
                    // What the key can do, unless the tabs below say it.
                    : root.tabs.length > 1 ? ""
                    : [root.device ? "FIDO2" : "", root.card ? "OpenPGP" : "",
                       Model.sshVisible(root.devices) ? "SSH" : ""].filter(function(s) { return s !== "" }).join(" · ")
                  visible: text !== ""
                  horizontalAlignment: Text.AlignLeft
                  wrapMode: Text.Wrap
                  color: root.helperLost ? root.urgent : root.foreground
                  opacity: root.helperLost ? 1 : 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Button {
              visible: root.helperLost
              anchors.right: parent.right
              focusable: true
              bordered: true
              text: tr.t("securityKey.refresh")
              iconText: "󰑐"
              onClicked: root.refresh()
            }

            // The tabs, when there is more than one; Ctrl+Tab walks them.
            Item {
              width: parent.width
              visible: root.tabs.length > 1
              height: tabBar.implicitHeight

              ButtonGroup {
                id: tabBar
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                options: root.tabs.map(function(name) {
                  // "…" on a tab left while its action runs.
                  var label = { fido: "FIDO2", gpg: "OpenPGP", ssh: "SSH" }[name]
                  if (name !== root.tab && Model.section(root.op) === name) label += " …"
                  return { value: name, label: label,
                           icon: { fido: "󰌆", gpg: "󰷖", ssh: "󰣀" }[name] }
                })
                value: root.tab
                foreground: root.foreground
                background: root.background
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(value) { root.selectTab(value) }
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: tabBar.width + implicitWidth + Style.spacing.lg <= parent.width
                textFormat: Text.PlainText
                text: Model.ltr("Ctrl+Tab")
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // One section at a time, as tall as the tallest, so the card
            // keeps its size from tab to tab.
            Item {
              width: parent.width
              visible: root.tab !== ""
              implicitHeight: Math.max(root.tabs.indexOf("fido") >= 0 ? fidoSection.implicitHeight : 0,
                                       root.tabs.indexOf("gpg") >= 0 ? gpgSection.implicitHeight : 0,
                                       root.tabs.indexOf("ssh") >= 0 ? sshSection.implicitHeight : 0)

              FidoSection {
                id: fidoSection
                visible: root.tab === "fido"
                width: parent.width
                height: parent.height
                strings: tr
                credentials: root.credentials
                device: root.device
                pam: root.pamState
                sharedCount: root.sharedCount
                busy: root.busy
                running: Model.section(root.op) === "fido" && root.op !== "fido.remove" && root.pinOp === ""
                pending: root.pendingRemove
                statusText: root.statusOf("fido").text
                statusTone: root.statusOf("fido").tone
                fontFamily: root.fontFamily
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                onRegisterRequested: root.askPin("fido.register")
                onRemoveRequested: function(index) { root.remove("fido", index) }
                onCancelRequested: root.cancel()
              }

              GpgSection {
                id: gpgSection
                visible: root.tab === "gpg"
                width: parent.width
                height: parent.height
                strings: tr
                card: root.card
                keyState: root.keyState
                trusted: root.trusted
                busy: root.busy
                running: Model.section(root.op) === "gpg"
                pending: root.pendingRemove
                statusText: root.statusOf("gpg").text
                statusTone: root.statusOf("gpg").tone
                fontFamily: root.fontFamily
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                onImportRequested: root.run({ cmd: "gpg.import" })
                onTrustRequested: root.run({ cmd: "gpg.trust" })
                onRemoveRequested: root.remove("gpg")
              }

              SshSection {
                id: sshSection
                visible: root.tab === "ssh"
                width: parent.width
                height: parent.height
                strings: tr
                device: root.device
                present: root.sshKeys
                pending: root.pendingRemove
                busy: root.busy
                running: Model.section(root.op) === "ssh" && root.op !== "ssh.remove" && root.pinOp === ""
                statusText: root.statusOf("ssh").text
                statusTone: root.statusOf("ssh").tone
                fontFamily: root.fontFamily
                foreground: root.foreground
                accent: root.accent
                urgent: root.urgent
                onImportRequested: root.askPin("ssh.import")
                onRemoveRequested: function(name) { root.remove("ssh", name) }
                onCancelRequested: root.cancel()
              }
            }
          }
        }

        Text {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.leftMargin: card.contentLeftInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          textFormat: Text.PlainText
          text: tr.t("securityKey.keys")
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        width: Math.min(titleText.implicitWidth + Style.space(24), panel.width - Style.gapsOut * 2)
        height: Style.space(28)
        anchors.horizontalCenter: card.horizontalCenter
        anchors.bottom: card.top
        anchors.bottomMargin: Style.space(10)
        radius: Style.cornerRadius
        color: root.background

        Text {
          id: titleText
          textFormat: Text.PlainText
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          text: tr.t("securityKey.title")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideMiddle
        }
      }

      // The PIN dialog, over the card.
      Rectangle {
        anchors.fill: parent
        visible: root.pinOp !== ""
        color: Commons.Color.polkit.scrim

        MouseArea { anchors.fill: parent; onClicked: pinDialog.focusPin() }

        PinDialog {
          id: pinDialog
          width: Math.min(Style.space(380), parent.width - Style.gapsOut * 2)
          anchors.centerIn: parent
          color: root.background
          borderSpec: root.borderSpec
          strings: tr
          glyph: root.pinOp === "ssh.import" ? "󰣀" : "󰌆"
          title: root.pinOp === "ssh.import" ? tr.t("securityKey.ssh.title") : tr.t("securityKey.fido.title")
          actionText: root.pinOp === "ssh.import" ? tr.t("securityKey.ssh.import")
            : root.credentials.length > 0 ? tr.t("securityKey.fido.registerAnother") : tr.t("securityKey.fido.register")
          message: root.pinState.text
          tone: root.pinState.tone
          running: root.busy
          pinRetries: root.device && root.device.pinRetries !== undefined ? root.device.pinRetries : -1
          fontFamily: root.fontFamily
          foreground: root.foreground
          accent: root.accent
          urgent: root.urgent
          onSubmitted: function(pin) { root.submitPin(pin) }
          onCancelRequested: root.busy ? root.cancel() : root.closePin()
        }
      }
    }
  }
}
