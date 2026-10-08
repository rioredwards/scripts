#!/bin/sh
# run-all.sh: run every test in ~/scripts. Exits non-zero if any fails.
#   sh tests/run-all.sh
# Shell tests run via their own shebang (keyfor-test.sh needs zsh).
set -u
root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

failed=""
n=0
run() {
  n=$((n + 1))
  printf '== %s\n' "$*"
  if "$@" >"${TMPDIR:-/tmp}/run-all.$$.log" 2>&1; then
    echo "   ok"
  else
    echo "   FAIL (exit $?)"
    sed 's/^/   | /' "${TMPDIR:-/tmp}/run-all.$$.log"
    failed="$failed $*"
  fi
}

for t in tests/*-test.sh; do run "./$t"; done
run python3 tests/dev-lease-test.py
run python3 hooks/tests/test_shared_hooks.py
run python3 hooks/rules/test_rules.py
run sh hooks/rules/validate.sh

rm -f "${TMPDIR:-/tmp}/run-all.$$.log"
if [ -n "$failed" ]; then
  printf '\nFAILED:%s\n' "$failed"
  exit 1
fi
printf '\nall %s passed\n' "$n"
