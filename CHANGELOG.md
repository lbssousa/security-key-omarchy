# Changelog

## Unreleased

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
