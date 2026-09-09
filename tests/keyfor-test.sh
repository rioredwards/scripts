#!/bin/zsh
# keyfor: round-trip tests against a throwaway age identity and store.
# Never touches the real ~/.config/age/key.txt or ~/.dotfiles/secrets.

set -uo pipefail

KEYFOR="${0:A:h}/../keyfor"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export KEYFOR_AGE_IDENTITY="$tmp/key.txt"
export KEYFOR_SECRETS_FILE="$tmp/keys.env.age"
age-keygen -o "$KEYFOR_AGE_IDENTITY" 2>/dev/null

pass=0 fail=0
ok()   { print -- "  ok: $1"; (( ++pass )) }
bad()  { print -u2 -- "  FAIL: $1"; (( ++fail )) }
check() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi
}

# --- set then get round-trips
print -r -- 'sk-test-value-123' | "$KEYFOR" --set OPENAI_API_KEY >/dev/null
check "get returns what set stored" "$("$KEYFOR" OPENAI_API_KEY)" 'sk-test-value-123'

# --- short slug resolves to the full env name
check "slug resolves" "$("$KEYFOR" openai)" 'sk-test-value-123'

# --- QBO names are not suffixed with _API_KEY
print -r -- 'qbo-secret' | "$KEYFOR" --set QBO_CLIENT_ID >/dev/null
check "QBO name kept verbatim" "$("$KEYFOR" QBO_CLIENT_ID)" 'qbo-secret'

# --- set is idempotent-by-replacement, not append
print -r -- 'rotated' | "$KEYFOR" --set OPENAI_API_KEY >/dev/null
check "set replaces, does not append" "$("$KEYFOR" OPENAI_API_KEY)" 'rotated'
check "store still has 2 keys" "$("$KEYFOR" --list | wc -l | tr -d ' ')" '2'

# --- values containing '=' survive
print -r -- 'a=b=c' | "$KEYFOR" --set RESEND_API_KEY >/dev/null
check "value with = survives" "$("$KEYFOR" RESEND_API_KEY)" 'a=b=c'

# --- list prints names only, never values
list="$("$KEYFOR" --list)"
[[ "$list" != *rotated* && "$list" != *'a=b=c'* ]] && ok "list leaks no values" || bad "list leaked a value"

# --- ciphertext on disk really is encrypted
grep -q 'rotated' "$KEYFOR_SECRETS_FILE" && bad "plaintext found in store file" || ok "store file is encrypted"

# --- --run scopes the var to one child process
check "--run exports only that var" "$("$KEYFOR" --run OPENAI_API_KEY -- zsh -c 'print -- $OPENAI_API_KEY')" 'rotated'
check "--run does not leak others" "$("$KEYFOR" --run OPENAI_API_KEY -- zsh -c 'print -- ${RESEND_API_KEY:-unset}')" 'unset'

# --- works where launchd and hooks live: no Homebrew on PATH
check "bare PATH still resolves age" "$(PATH=/usr/bin:/bin "$KEYFOR" OPENAI_API_KEY)" 'rotated'
print -r -- 'set-under-bare-path' | PATH=/usr/bin:/bin "$KEYFOR" --set DEEPSEEK_API_KEY >/dev/null
check "bare PATH can write too" "$("$KEYFOR" DEEPSEEK_API_KEY)" 'set-under-bare-path'
"$KEYFOR" --rm DEEPSEEK_API_KEY >/dev/null

# --- rm removes
"$KEYFOR" --rm RESEND_API_KEY >/dev/null
"$KEYFOR" RESEND_API_KEY >/dev/null 2>&1 && bad "rm did not remove" || ok "rm removes the key"

# --- fail loud, no fallbacks
"$KEYFOR" NOPE_API_KEY >/dev/null 2>&1 && bad "missing key should exit nonzero" || ok "missing key exits nonzero"
"$KEYFOR" --rm NOPE_API_KEY >/dev/null 2>&1 && bad "rm of missing key should fail" || ok "rm of missing key fails loud"

KEYFOR_AGE_IDENTITY="$tmp/absent.txt" "$KEYFOR" OPENAI_API_KEY >/dev/null 2>&1 \
  && bad "missing identity should exit nonzero" || ok "missing identity exits nonzero"

# --- empty value is rejected rather than stored
print -r -- '' | "$KEYFOR" --set BLANK_API_KEY >/dev/null 2>&1 \
  && bad "empty value should be rejected" || ok "empty value rejected"

print -- "keyfor: $pass passed, $fail failed"
(( fail == 0 ))
