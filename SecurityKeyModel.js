// Pure helpers for the security key overlay, kept out of QML so node can
// test them (tests/js/).

// The first FIDO device the helper reported, or null.
function device(devices) {
  return devices && devices.length > 0 ? devices[0] : null
}

// The GPG section needs an OpenPGP card; the SSH one a key that keeps
// resident (discoverable) credentials.
function gpgVisible(card) {
  return !!card
}

function sshVisible(devices) {
  if (!devices) return false
  for (var i = 0; i < devices.length; i++) if (devices[i].rk) return true
  return false
}

// Registering is only offered where sudo and polkit will read the key: the
// helper's "target" is "own" or "shared" (see fido_target in key-helper).
function canRegister(target) {
  return !!target && (target.kind === "own" || target.kind === "shared")
}

var TARGET_NOTICES = {
  "no-pam": "securityKey.fido.pam.missing",
  "no-helper": "securityKey.fido.pam.noHelper",
  "other-file": "securityKey.fido.pam.otherFile",
  "mixed": "securityKey.fido.pam.mixed"
}

// sudo or polkit only take a key with its PIN, and the one plugged in has none.
function needsPin(pinRequired, device) {
  return !!pinRequired && !!device && device.clientPin !== true
}

// What to say about the target instead of offering to register, or "".
function targetNoticeKey(target) {
  return (target && TARGET_NOTICES[target.kind]) || ""
}

// Whether a key is registered where sudo and polkit read it.
function hasActive(credentials) {
  for (var i = 0; credentials && i < credentials.length; i++) if (!credentials[i].unused) return true
  return false
}

// Latin runs with slashes, tildes or plus signs (paths, file names, Alt+R)
// inside right-to-left text: isolated, so the bidi algorithm doesn't move
// their punctuation around. Invisible in left-to-right text.
function ltr(text) {
  return "\u2066" + text + "\u2069"
}

// A button label with its key after it.
function shortcut(label, key) {
  return label + "  " + ltr(key)
}

// gpg's own grouping: ten blocks of four, an extra space in the middle.
function formatFingerprint(fpr) {
  var hex = String(fpr || "").toUpperCase()
  if (hex.length !== 40) return hex
  var blocks = hex.match(/.{4}/g)
  return blocks.slice(0, 5).join(" ") + "  " + blocks.slice(5).join(" ")
}

var ERROR_KEYS = {
  "pin-required": "securityKey.error.pinRequired",
  "pin-invalid": "securityKey.error.pinInvalid",
  "pin-blocked": "securityKey.error.pinBlocked",
  "timeout": "securityKey.error.timeout",
  "no-device": "securityKey.error.noDevice",
  "no-card": "securityKey.error.noDevice",
  "no-pin": "securityKey.fido.needsPin",
  "already-registered": "securityKey.fido.alreadyRegistered",
  "write-failed": "securityKey.error.writeFailed",
  // pkexec dismissed, refused or left unanswered (the shared authfile).
  "not-authorized": "securityKey.error.writeFailed",
  "import-failed": "securityKey.gpg.importFailed",
  "trust-failed": "securityKey.gpg.trustFailed",
  "secret-on-disk": "securityKey.gpg.secretOnDisk",
  "ssh-none": "securityKey.ssh.none"
}

function errorKey(code) {
  return ERROR_KEYS[code] || "securityKey.error.generic"
}

// Alt+1-9 count the removable items of the tab shown: the registered keys
// on "fido", the SSH keys in ~/.ssh on "ssh". Item n (from 0) is
// { kind: "fido", index } or { kind: "ssh", index, name }, or null past the
// end.
function removable(tab, credentials, sshKeys, n) {
  if (n < 0) return null
  if (tab === "fido" && credentials && n < credentials.length) return { kind: "fido", index: n }
  if (tab === "ssh" && sshKeys && n < sshKeys.length) return { kind: "ssh", index: n, name: sshKeys[n] }
  return null
}

// One tab per section the key can do, in the card's order: "fido" (also
// without the key, while keys are registered), "gpg", "ssh" (also while
// ~/.ssh holds resident keys).
function tabs(devices, credentials, card, sshKeys) {
  var out = []
  if (device(devices) !== null || (credentials && credentials.length > 0)) out.push("fido")
  if (gpgVisible(card)) out.push("gpg")
  if (sshVisible(devices) || (sshKeys && sshKeys.length > 0)) out.push("ssh")
  return out
}

// The tab picked, while it is still there; the first one otherwise.
function currentTab(tabs, chosen) {
  if (!tabs || tabs.length === 0) return ""
  return tabs.indexOf(chosen) >= 0 ? chosen : tabs[0]
}

// Ctrl+Tab and Ctrl+Shift+Tab: the next or previous tab (by 1 or -1),
// round the ends.
function nextTab(tabs, current, by) {
  if (!tabs || tabs.length === 0) return ""
  var at = Math.max(0, tabs.indexOf(current))
  return tabs[(at + by + tabs.length * 2) % tabs.length]
}

// What a remove button asks to confirm: "fido:0", "ssh:<file>", "gpg".
function removeId(kind, which) {
  return kind === "gpg" ? "gpg" : kind + ":" + which
}

// Which section an operation belongs to: "fido.register" -> "fido".
function section(op) {
  var dot = String(op || "").indexOf(".")
  return dot > 0 ? op.substring(0, dot) : ""
}

var KEY_STATE_KEYS = {
  "missing": "securityKey.gpg.state.missing",
  "public": "securityKey.gpg.state.public",
  "ready": "securityKey.gpg.state.ready"
}

function keyStateKey(state) {
  return KEY_STATE_KEYS[state] || ""
}

if (typeof module !== "undefined") {
  module.exports = {
    device: device,
    gpgVisible: gpgVisible,
    sshVisible: sshVisible,
    canRegister: canRegister,
    needsPin: needsPin,
    targetNoticeKey: targetNoticeKey,
    hasActive: hasActive,
    formatFingerprint: formatFingerprint,
    errorKey: errorKey,
    section: section,
    keyStateKey: keyStateKey,
    ltr: ltr,
    removable: removable,
    tabs: tabs,
    currentTab: currentTab,
    nextTab: nextTab,
    removeId: removeId,
    shortcut: shortcut
  }
}
