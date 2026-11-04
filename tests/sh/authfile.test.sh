#!/bin/bash
# omarchy-security-key-authfile, under fakeroot (EUID 0, no pkexec), against a
# fake /etc/fido2. Uses two accounts that exist anywhere: root and the user
# running the tests. Each test runs in a subshell with a fresh $T.
set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
me=$(id -un)
pass=0 failed=0

fail() { echo "    $*" >&2; exit 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_no_file() { [[ ! -e $1 ]] || fail "unexpected file $1"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "$1 lacks [$2]"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" || fail "$1 has [$2]"; }

# helper_as <user> <action>
helper_as() {
  SECURITY_KEY_AUTHFILE_ROOT=$T SECURITY_KEY_AUTHFILE_USER=$1 \
    fakeroot -- "$REPO/bin/omarchy-security-key-authfile" "$2"
}
helper() { helper_as "$me" "$1"; }
authfile() { echo "$T/etc/fido2/fido2"; }

test_add_creates_line() {
  echo "$me:KH1,PK1,es256,+presence" | helper add >/dev/null || fail "add failed"
  assert_eq "$(cat "$(authfile)")" "$me:KH1,PK1,es256,+presence"
  assert_eq "$(stat -c %a "$(authfile)")" 644
}

test_other_lines_stay() {
  echo "$me:KH1,PK1,es256,+presence" | helper add >/dev/null
  echo "root:KH9,PK9,es256,+presence" | helper_as root add >/dev/null
  assert_eq "$(wc -l <"$(authfile)")" 2
  assert_contains "$(authfile)" "$me:KH1,PK1,es256,+presence"
  assert_contains "$(authfile)" "root:KH9,PK9,es256,+presence"
}

test_second_key_appends_and_dedupes() {
  echo "$me:KH1,PK1,es256,+presence" | helper add >/dev/null
  echo "$me:KH2,PK2,es256,+presence" | helper add >/dev/null
  echo "$me:KH1,PK1,es256,+presence" | helper add >/dev/null
  assert_eq "$(cat "$(authfile)")" "$me:KH1,PK1,es256,+presence:KH2,PK2,es256,+presence"
}

test_rejects_other_users_line() {
  if echo "root:KH,PK,es256,+presence" | helper add 2>/dev/null; then
    fail "accepted a line for another user"
  fi
  assert_no_file "$(authfile)"
}

test_rejects_multiline_and_junk() {
  printf '%s\n%s\n' "$me:A,B" "root:C,D" | helper add 2>/dev/null && fail "accepted two lines"
  echo "$me:A B;rm -rf /" | helper add 2>/dev/null && fail "accepted junk"
  echo "$me:" | helper add 2>/dev/null && fail "accepted an empty credential"
  assert_no_file "$(authfile)"
}

test_refuses_symlinked_authfile() {
  mkdir -p "$T/etc/fido2" "$T/elsewhere"
  ln -s "$T/elsewhere/target" "$(authfile)"
  echo "$me:KH1,PK1" | helper add 2>/dev/null && fail "wrote through a symlink"
  assert_no_file "$T/elsewhere/target"
}

test_refuses_symlinked_authdir() {
  mkdir -p "$T/etc" "$T/elsewhere"
  ln -s "$T/elsewhere" "$T/etc/fido2"
  echo "$me:KH1,PK1" | helper add 2>/dev/null && fail "wrote through a symlinked directory"
  assert_no_file "$T/elsewhere/fido2"
}

test_remove_key_drops_one_credential_then_the_line() {
  echo "$me:KH1,PK1,es256,+presence" | helper add >/dev/null
  echo "$me:KH2,PK2,es256,+presence" | helper add >/dev/null
  echo "root:KH1,PK9,es256,+presence" | helper_as root add >/dev/null
  echo KH1 | helper remove-key >/dev/null || fail "remove-key failed"
  assert_contains "$(authfile)" "$me:KH2,PK2,es256,+presence"
  assert_not_contains "$(authfile)" "$me:KH1"
  assert_contains "$(authfile)" "root:KH1,PK9,es256,+presence"
  echo KH2 | helper remove-key >/dev/null || fail "second remove-key failed"
  assert_eq "$(cat "$(authfile)")" "root:KH1,PK9,es256,+presence"
}

test_remove_key_rejects_unknown_and_junk() {
  echo "$me:KH1,PK1,es256,+presence" | helper add >/dev/null
  echo KHX | helper remove-key 2>/dev/null && fail "removed an unknown key"
  echo 'KH1;x' | helper remove-key 2>/dev/null && fail "accepted junk"
  assert_eq "$(cat "$(authfile)")" "$me:KH1,PK1,es256,+presence"
}

test_needs_root() {
  echo "$me:KH1,PK1" | "$REPO/bin/omarchy-security-key-authfile" add 2>/dev/null && fail "ran without root"
  true
}

test_needs_a_caller() {
  out=$(echo "$me:KH1,PK1" | SECURITY_KEY_AUTHFILE_ROOT=$T fakeroot -- "$REPO/bin/omarchy-security-key-authfile" add 2>&1) &&
    fail "ran without a caller"
  [[ $out == *"no PKEXEC_UID"* ]] || fail "unexpected error: $out"
  assert_no_file "$(authfile)"
}

# Through pkexec the caller comes from PKEXEC_UID and nothing else: the fake
# tree and the named user are dropped, so only what fails before touching a
# file can be checked here.
test_pkexec_unknown_caller_refused() {
  out=$(echo "x:KH1,PK1" | PKEXEC_UID=2147483000 SECURITY_KEY_AUTHFILE_USER=$me SECURITY_KEY_AUTHFILE_ROOT=$T \
    fakeroot -- "$REPO/bin/omarchy-security-key-authfile" add 2>&1) && fail "accepted an unknown uid"
  [[ $out == *"Unknown caller"* ]] || fail "unexpected error: $out"
  assert_no_file "$(authfile)"
}

test_unknown_action() {
  out=$(SECURITY_KEY_AUTHFILE_ROOT=$T SECURITY_KEY_AUTHFILE_USER=$me "$REPO/bin/omarchy-security-key-authfile" remove 2>&1)
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
