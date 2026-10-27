const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../../SecurityKeyModel.js")

const yubikey = { path: "/dev/hidraw1", name: "YubiKey", rk: true, clientPin: true }

test("the first device, if any", () => {
  assert.equal(Model.device([yubikey, { path: "/dev/hidraw2" }]), yubikey)
  assert.equal(Model.device([]), null)
  assert.equal(Model.device(null), null)
})

test("sections show only what the key supports", () => {
  assert.equal(Model.gpgVisible({ serial: "1" }), true)
  assert.equal(Model.gpgVisible(null), false)
  assert.equal(Model.sshVisible([yubikey]), true)
  assert.equal(Model.sshVisible([{ path: "/dev/hidraw2", rk: false }]), false)
  assert.equal(Model.sshVisible([]), false)
})

test("whether sudo and polkit read the per-user keys", () => {
  const mine = "/home/ada/.config/Yubico/u2f_keys"
  const perUser = { u2f: true, authfile: "" }
  const none = { u2f: false, authfile: "" }
  assert.deepEqual(Model.pamState({ sudo: perUser, polkit: perUser }, mine), { kind: "ok", path: "" })
  assert.deepEqual(Model.pamState({ sudo: { u2f: true, authfile: mine }, polkit: none }, mine), { kind: "ok", path: "" })
  assert.deepEqual(Model.pamState({ sudo: { u2f: true, authfile: "/etc/fido2/fido2" }, polkit: perUser }, mine),
    { kind: "shared", path: "/etc/fido2/fido2" })
  assert.deepEqual(Model.pamState({ sudo: none, polkit: none }, mine), { kind: "missing", path: "" })
  assert.deepEqual(Model.pamState(null, mine), { kind: "missing", path: "" })
})

test("fingerprints group like gpg prints them", () => {
  assert.equal(Model.formatFingerprint("bac0b1b569777a733e37447fb10712c404063d38"),
    "BAC0 B1B5 6977 7A73 3E37  447F B107 12C4 0406 3D38")
  assert.equal(Model.formatFingerprint("ABC"), "ABC")
})

test("error codes and operations", () => {
  assert.equal(Model.errorKey("pin-invalid"), "securityKey.error.pinInvalid")
  assert.equal(Model.errorKey("weird"), "securityKey.error.generic")
  assert.equal(Model.section("fido.register"), "fido")
  assert.equal(Model.section("refresh"), "")
  assert.equal(Model.keyStateKey("ready"), "securityKey.gpg.state.ready")
  assert.equal(Model.keyStateKey("none"), "")
})

test("latin runs isolated for right-to-left text", () => {
  assert.equal(Model.ltr("~/.ssh"), "⁦~/.ssh⁩")
  assert.equal(Model.shortcut("Remove", "Alt+1"), "Remove  ⁦Alt+1⁩")
  assert.deepEqual(["id_ed25519_sk_rk"].map(Model.ltr), ["⁦id_ed25519_sk_rk⁩"])
})

test("Alt+N counts the registered keys, then the SSH keys", () => {
  const creds = [{ label: "a" }, { label: "b" }]
  const ssh = ["id_ed25519_sk_rk", "id_ed25519_sk_rk_github.com"]
  assert.deepEqual(Model.removable(creds, ssh, 1), { kind: "fido", index: 1 })
  assert.deepEqual(Model.removable(creds, ssh, 3), { kind: "ssh", index: 1, name: "id_ed25519_sk_rk_github.com" })
  assert.equal(Model.removable(creds, ssh, 4), null)
  assert.deepEqual(Model.removable([], ssh, 0), { kind: "ssh", index: 0, name: "id_ed25519_sk_rk" })
  assert.equal(Model.removeId("ssh", "id_x"), "ssh:id_x")
  assert.equal(Model.removeId("gpg"), "gpg")
  assert.equal(Model.errorKey("secret-on-disk"), "securityKey.gpg.secretOnDisk")
})
