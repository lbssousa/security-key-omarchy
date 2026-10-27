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

// Whether sudo and polkit will read the keys this overlay registers:
//   "ok"      pam_u2f reads the per-user file
//   "shared"  pam_u2f is pinned to another authfile (Omarchy's /etc/fido2/fido2); path says which
//   "missing" neither service asks for a security key
function pamState(pam, authfile) {
  var services = pam ? [pam.sudo, pam.polkit] : []
  var any = false
  for (var i = 0; i < services.length; i++) {
    var s = services[i]
    if (!s || !s.u2f) continue
    any = true
    if (s.authfile && s.authfile !== authfile) return { kind: "shared", path: s.authfile }
  }
  return { kind: any ? "ok" : "missing", path: "" }
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
  "write-failed": "securityKey.error.writeFailed",
  "import-failed": "securityKey.gpg.importFailed",
  "trust-failed": "securityKey.gpg.trustFailed",
  "secret-on-disk": "securityKey.gpg.secretOnDisk",
  "ssh-none": "securityKey.ssh.none"
}

function errorKey(code) {
  return ERROR_KEYS[code] || "securityKey.error.generic"
}

// Alt+1-9 count the removable items down the card: the registered keys,
// then the SSH keys in ~/.ssh. Item n (from 0) is { kind: "fido", index }
// or { kind: "ssh", index, name }, or null past the end.
function removable(credentials, sshKeys, n) {
  var fido = credentials ? credentials.length : 0
  if (n < 0) return null
  if (n < fido) return { kind: "fido", index: n }
  var ssh = sshKeys || []
  if (n - fido < ssh.length) return { kind: "ssh", index: n - fido, name: ssh[n - fido] }
  return null
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
    pamState: pamState,
    formatFingerprint: formatFingerprint,
    errorKey: errorKey,
    section: section,
    keyStateKey: keyStateKey,
    ltr: ltr,
    removable: removable,
    removeId: removeId,
    shortcut: shortcut
  }
}
