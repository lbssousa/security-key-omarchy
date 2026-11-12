#!/bin/bash
# omarchy-security-key-pam, under fakeroot (EUID 0, no pkexec), against a fake
# /etc/pam.d. Each test runs in a subshell with a fresh $T.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
pass=0 failed=0

fail() { echo "    $*" >&2; exit 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"; }

helper() { SECURITY_KEY_PAM_ROOT=$T fakeroot -- "$REPO/bin/omarchy-security-key-pam" "$1"; }
pam() { echo "$T/etc/pam.d/$1"; }

# What omarchy-setup-security-fido2 writes, below other modules.
setup() {
  mkdir -p "$T/etc/pam.d"
  cat >"$(pam sudo)" <<'EOF'
#%PAM-1.0
auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/true
auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2
auth		include		system-auth
account		include		system-auth
EOF
  cat >"$(pam polkit-1)" <<'EOF'
auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2 pinverification=0
auth      include system-auth
EOF
  chmod 644 "$(pam sudo)" "$(pam polkit-1)"
}

test_pin_on_sets_both() {
  setup
  helper pin-on >/dev/null || fail "pin-on failed"
  assert_eq "$(sed -n 3p "$(pam sudo)")" "auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2 pinverification=1 userpresence=1"
  assert_eq "$(sed -n 1p "$(pam polkit-1)")" "auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2 pinverification=1 userpresence=1"
  assert_eq "$(stat -c %a "$(pam sudo)")" 644
}

test_other_lines_stay() {
  setup
  cp "$(pam sudo)" "$T/before"
  helper pin-on >/dev/null
  assert_eq "$(diff "$T/before" "$(pam sudo)" | grep -c '^[<>]')" 2
  assert_eq "$(sed -n 2p "$(pam sudo)")" "auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/true"
  assert_eq "$(sed -n 4p "$(pam sudo)")" $'auth\t\tinclude\t\tsystem-auth'
}

test_pin_off_drops_the_option() {
  setup
  helper pin-on >/dev/null
  helper pin-off >/dev/null || fail "pin-off failed"
  assert_eq "$(sed -n 3p "$(pam sudo)")" "auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2 userpresence=1"
  assert_eq "$(sed -n 1p "$(pam polkit-1)")" "auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2 userpresence=1"
}

test_round_trip_is_stable() {
  setup
  helper pin-on >/dev/null
  cp "$(pam sudo)" "$T/on"
  helper pin-off >/dev/null
  helper pin-on >/dev/null
  helper pin-on >/dev/null
  cmp -s "$T/on" "$(pam sudo)" || fail "pin-on twice changed the file"
}

test_comments_and_other_modules_left_alone() {
  mkdir -p "$T/etc/pam.d"
  printf '%s\n' "#auth sufficient pam_u2f.so cue" "auth sufficient pam_u2f.so" "auth required pam_unix.so" >"$(pam sudo)"
  helper pin-on >/dev/null || fail "pin-on failed"
  assert_eq "$(cat "$(pam sudo)")" $'#auth sufficient pam_u2f.so cue\nauth sufficient pam_u2f.so pinverification=1 userpresence=1\nauth required pam_unix.so'
}

test_only_polkit() {
  mkdir -p "$T/etc/pam.d"
  echo "auth include system-auth" >"$(pam sudo)"
  echo "auth sufficient pam_u2f.so cue" >"$(pam polkit-1)"
  helper pin-on >/dev/null || fail "pin-on failed"
  assert_eq "$(cat "$(pam sudo)")" "auth include system-auth"
  assert_eq "$(cat "$(pam polkit-1)")" "auth sufficient pam_u2f.so cue pinverification=1 userpresence=1"
}

test_refuses_without_pam_u2f() {
  mkdir -p "$T/etc/pam.d"
  echo "auth include system-auth" >"$(pam sudo)"
  out=$(helper pin-on 2>&1) && fail "accepted a PAM without pam_u2f"
  [[ $out == *"Neither sudo nor polkit"* ]] || fail "unexpected error: $out"
  assert_eq "$(cat "$(pam sudo)")" "auth include system-auth"
}

test_refuses_a_bracketed_control() {
  mkdir -p "$T/etc/pam.d"
  echo "auth [success=done default=ignore] pam_u2f.so cue" >"$(pam sudo)"
  helper pin-on 2>/dev/null && fail "changed a bracketed control"
  assert_eq "$(cat "$(pam sudo)")" "auth [success=done default=ignore] pam_u2f.so cue"
  assert_eq "$(find "$T/etc/pam.d" -name '*.new.*' | wc -l)" 0
}

test_refuses_symlinked_file() {
  mkdir -p "$T/etc/pam.d" "$T/elsewhere"
  echo "auth sufficient pam_u2f.so cue" >"$T/elsewhere/sudo"
  ln -s "$T/elsewhere/sudo" "$(pam sudo)"
  helper pin-on 2>/dev/null && fail "followed a symlink"
  assert_eq "$(cat "$T/elsewhere/sudo")" "auth sufficient pam_u2f.so cue"
}

test_needs_root() {
  setup
  SECURITY_KEY_PAM_ROOT=$T "$REPO/bin/omarchy-security-key-pam" pin-on 2>/dev/null && fail "ran without root"
  true
}

test_unknown_action() {
  out=$(helper pin 2>&1)
  assert_eq "$?" 2
  [[ $out == Usage:* ]] || fail "unexpected output: $out"
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  if ( T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; export T; "$t" ); then
    echo "ok   $t"; pass=$((pass + 1))
  else
    echo "FAIL $t"; failed=$((failed + 1))
  fi
done
echo "# $(basename "$0"): $pass passed, $failed failed"
(( failed == 0 ))
