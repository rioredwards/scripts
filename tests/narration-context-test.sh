#!/bin/sh
# Behavioural tests for narration-context's "already said" trailer (scripts#7).
# Runs against a throwaway HOME so real per-Mac state is never touched.
#   sh tests/narration-context-test.sh
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
nc="$here/narration-context"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME"
repo="$tmp/repo"; mkdir -p "$repo"; git -C "$repo" init -q -b main && git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

fail=0
check() { # name, expected-substring-or-!substring, output
  case "$2" in
    !*) if printf '%s' "$3" | grep -qF -- "${2#!}"; then echo "FAIL $1: found '${2#!}'"; fail=1; else echo "ok   $1"; fi ;;
    *)  if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok   $1"; else echo "FAIL $1: missing '$2'"; echo "$3" | sed 's/^/     /'; fail=1; fi ;;
  esac
}
run() { HOOK_AGENT=claude HOOK_CWD="$repo" HOOK_SESSION_ID="$1" "$nc" -f "Depth: brief"; }

out="$(run s1)"
check "first clip: full block"            "Project: repo" "$out"
check "first clip: no trailer"            "!Already said" "$out"

out="$(run s1)"
check "same session: block still complete" "Project: repo" "$out"
check "same session: trailer present"     "Already said in the last clip — do not repeat: Time, Machine, Agent, Project, Branch, Turn" "$out"
check "caller facts never marked"         "!Depth" "$(printf '%s' "$out" | grep 'Already said')"

git -C "$repo" checkout -q -b feature 2>/dev/null || git -C "$repo" switch -q -c feature
out="$(run s1)"
check "branch change: Branch spoken"      "!Branch" "$(printf '%s' "$out" | grep 'Already said')"
check "branch change: Project still quiet" "Project" "$(printf '%s' "$out" | grep 'Already said')"

out="$(run s2)"
check "new session: Turn spoken"          "!Turn" "$(printf '%s' "$out" | grep 'Already said')"
check "new session: Machine still quiet"  "Machine" "$(printf '%s' "$out" | grep 'Already said')"

# Trailer must not parse as a `Key: value` fact (reader / narration-title regex).
trailer="$(printf '%s' "$out" | grep 'Already said')"
if printf '%s' "$trailer" | grep -qE '^[A-Za-z][A-Za-z ]{0,30}:'; then echo "FAIL trailer parses as a fact"; fail=1; else echo "ok   trailer is not a fact line"; fi



# narration-spoken: the model-facing block drops exactly the named facts.
spoken="$(printf '%s' "$out" | "$here/narration-spoken")"
check "spoken: kept changed fact"         "Turn: number 1" "$spoken"
check "spoken: dropped Machine"           "!Machine:" "$spoken"
check "spoken: dropped Project"           "!Project:" "$spoken"
check "spoken: caller fact kept"          "Depth: brief" "$spoken"
check "spoken: trailer gone"              "!Already said" "$spoken"
check "spoken: header kept"               "MESSAGE CONTEXT" "$spoken"
plain="$(printf 'MESSAGE CONTEXT — x\nTime: 1 PM\n' | "$here/narration-spoken")"
check "spoken: no trailer passes through" "Time: 1 PM" "$plain"
exit $fail
