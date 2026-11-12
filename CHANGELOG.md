# Changelog

## 0.8.0 (2026-11-12)

- The FIDO2 tab chooses whether sudo and polkit ask for the key's PIN along
  with the touch, or for a touch alone. The switch runs `pkexec
  omarchy-security-key-pam pin-on` (or `pin-off`), a new helper in the Arch
  package with its own polkit action, which asks for an administrator. It
  only changes the `pam_u2f.so` auth lines of `/etc/pam.d/sudo` and
  `/etc/pam.d/polkit-1`, and in them only `pinverification=` (`1`, or
  dropped) and `userpresence=1`. When only one of them asks for the PIN, the
  switch shows off and says so; turning it on sets both. It refuses to ask
  for the PIN while the key plugged in has none. Without the package, the tab
  says to install it.

## 0.7.4 (2026-11-10)

- Restrict resident SSH key names strictly to safe characters. Resident key
  filenames created or imported from authenticators must match
  `^id_(?:ed25519_sk|ecdsa_sk)_rk(?:_[A-Za-z0-9._@:-]+)?$`. Before, malicious
  or hostile authenticators with carriage returns, newlines or spaces in their
  user IDs could produce filenames capable of injecting directives (such as
  `ProxyCommand`) into `IdentityFile` lines in `~/.ssh/config.d/<host>.conf`.
  Found in the Omarchy plugin marketplace's review.

## 0.7.3 (2026-11-08)

- No text input lives behind the PIN dialog. While it is open, the SSH tab's
  new-key form, the minutes editor and the public key of the key just made
  go, and come back when it closes, the form with what it held. Before, the
  form's three text fields stayed alive under the dialog while a new key was
  made, still reading every clipboard offer. Found in the Omarchy plugin
  marketplace's review.

## 0.7.2 (2026-11-07)

- The PIN dialog's field exists only while the PIN can be typed. Before, it
  was only hidden while the key waited for a touch, and a hidden text field
  still reads every clipboard offer. Found in the Omarchy plugin
  marketplace's review.

## 0.7.1 (2026-11-07)

- The SSH tab's new-key form and the minutes editor close when another tab is
  shown, when the SSH tab goes away (the key pulled out) and when the overlay
  closes. Their loaders are also inactive while the tab is hidden. Before,
  switching tabs or closing the overlay with the form open kept its three text
  fields alive and hidden, still reading every clipboard offer (0.6.1 had
  fixed the PIN dialog only). Found in the Omarchy plugin marketplace's
  review.

## 0.7.0 (2026-11-07)

- **Connection reuse** for the git hosts set up in `~/.ssh/config.d`, as in
  omarchy-yubikey. Setting a host up asks for the minutes, from 0 to 1440:
  *Use for <host>* opens them, and so does importing or creating a key whose
  host isn't set up yet. A configured host's *Reuse connections* button
  changes them. The default, 0, authenticates every new connection (and turns
  inherited multiplexing off). More than 0 keeps the authenticated connection
  that long (`ControlMaster auto`, `ControlPersist`, a socket in the private
  `~/.ssh/security-key/control`). The host's file keeps the setting when keys
  join or leave it. Files written by 0.6, without these lines, are still the
  overlay's and count as 0.
- The minutes field exists only while it is being edited, like the other text
  fields.

## 0.6.1 (2026-11-07)

- The PIN dialog and the new SSH key form create their text fields only while
  they are open, and the public key just made is shown only while there is
  one. A text input watches the clipboard for as long as it exists, shown or
  not, and Qt reads each new clipboard offer for it. Before, these fields
  lived with the shell for good, so another client's oversized or endless
  clipboard offer could exhaust memory or block the shell. Found in the
  Omarchy plugin marketplace's review.

## 0.6.0 (2026-11-07)

Brought over from omarchy-yubikey, with the fixes its review asked for:

- **New resident SSH keys**, from a form in the SSH tab (Alt+N): type,
  application, a random user ID by default, PIN and touch for every use, and
  a comment. The options are checked before the key is touched (no accented
  comments, no user ID that would name the copy like a `.pub` file), the copy
  gets the name `ssh-keygen -K` gives it, never over a file already there, and
  the overlay shows the public key with a copy button. A key with the same
  application and user ID on the security key is replaced only after the PIN
  dialog asks again.
- **Delete from security key**, next to each copy's *Remove copy*: two presses
  and the PIN, with a warning that it can't be undone. Only the credential of
  that copy is deleted, matched by its key handle, so a copy of a key replaced
  since deletes nothing; the host file is checked before anything is deleted.
- **Git hosts**: *Use for &lt;host&gt;* on keys whose application names a git
  host writes `~/.ssh/config.d/<host>.conf` (the host's keys, without the
  agent) and the `Include` for it. Hand-written or hand-edited files are left
  alone. Removing a copy takes it out of its host file.
- **OpenPGP**: once gpg uses the card, the import button reads *Update key*
  and fetches the public key again; until then it stands out.
- `sshKeys` in the helper's state are objects (`name`, `application`, `host`,
  `hostState`), and the state carries suggestions for a new key.

## 0.5.0 (2026-11-04)

- When sudo or polkit demand the PIN (`pinverification=1` on `pam_u2f`), a key
  without a PIN isn't registered, since it could never sign in: the overlay
  says to set one first. The FIDO2 tab no longer promises sign-in with just a
  touch.
- A key is only registered where sudo and polkit will read it. Without the
  package's helper for `/etc/fido2/fido2`, with PAM pinned to any other file,
  with sudo and polkit on different files, or with neither asking for a key,
  the overlay offers no register button and says why, instead of saving a key
  to `~/.config/Yubico/u2f_keys` that nothing reads.
- The overlay no longer lists keys from one file and saves them to another
  when PAM is pinned to a file other than `/etc/fido2/fido2`, the only one the
  helper writes.
- Registering the key plugged in a second time is refused without asking for a
  touch (`fido2-assert`, with `up=false`). Before, it added a second credential
  of the same key.
- Keys left in `~/.config/Yubico/u2f_keys` that sudo and polkit no longer read
  are listed as not used and can be removed.

## 0.4.0 (2026-11-03)

- The Arch package now installs `omarchy-security-key-authfile` and its polkit
  action (`org.omarchy.security-key.authfile`), so the overlay registers and
  removes keys in Omarchy's `/etc/fido2/fido2` without omarchy-multiuser. It
  takes the place of `omarchy-mu-fido2-authfile`, keeping its checks: only the
  caller's line, from `PKEXEC_UID`, with no `--user` and no `sudo` route.
- `omarchy-security-key` falls back to Omarchy's own terminal setup.

## 0.3.0 (2026-10-27)

- The three sections are tabs now (*FIDO2*, *OpenPGP*, *SSH*), one shown at
  a time, with the card keeping the height of the tallest. Ctrl+Tab and
  Ctrl+Shift+Tab (or Ctrl+Page Down/Up) switch tabs; an action's Alt key
  opens its tab, and a tab left while its action runs shows "…".
- Alt+1-9 count the items of the tab shown, so SSH keys start at Alt+1.
- The card no longer opens scrolled down when the key is reported before
  the overlay's window has its size.

## 0.2.0 (2026-10-27)

- When sudo and polkit read a shared authfile that
  [omarchy-multiuser](https://github.com/lbssousa/omarchy-multiuser)
  manages (`/etc/fido2/fido2`), the overlay lists the keys on your line
  there and registers and removes them through `pkexec
  omarchy-mu-fido2-authfile` (your own password, in the polkit agent),
  instead of only warning that PAM doesn't read your own list.

## 0.1.0 (2026-10-27)

- First release: the `lbssousa.security-key` overlay, after the security-key
  page of lbssousa/noctalia. Registers a FIDO2 key for sudo and polkit in the
  user's own `~/.config/Yubico/u2f_keys` (PIN asked in a dialog, touch,
  per-key removal) and says when PAM reads another authfile; imports the
  OpenPGP key on the card (card URL, then keyservers), links it to the card,
  trusts it and removes it from the keyring again (only card stubs, never a
  secret kept on disk); copies the key's resident SSH keys into `~/.ssh`
  without overwriting, and removes them one by one. The last two sections
  show only for keys that support them, and the overlay follows the key
  being plugged in or pulled out.
- Every action has an Alt key shown on its button; catalogs for every Omarchy
  language.
- `key-helper` (Python, standard library) drives fido2-token, pamu2fcfg, gpg
  and ssh-keygen; PINs never reach a command line, the environment or a log.
- `omarchy-security-key`, a PKGBUILD, and `just test` / `dev` / `link` /
  `validate` / `pkg`.
