# Changelog

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
