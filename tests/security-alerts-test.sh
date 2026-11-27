#!/bin/sh
# security-alerts: counts by severity, red on any critical, loud failure. Uses a stand-in for gh; never calls GitHub.
set -u
here="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok: $1"; else echo "  FAIL: $1 (want '$3', got '$2')"; fails=$((fails+1)); fi; }

cat >"$t/gh-ok" <<'X'
#!/bin/sh
echo '[[{"security_advisory":{"severity":"critical"}},{"security_advisory":{"severity":"high"}}],[{"security_advisory":{"severity":"high"}},{"security_advisory":{"severity":"low"}}]]'
X
cat >"$t/gh-nocrit" <<'X'
#!/bin/sh
echo '[[{"security_advisory":{"severity":"high"}}]]'
X
cat >"$t/gh-fail" <<'X'
#!/bin/sh
echo "HTTP 403" >&2; exit 1
X
cat >"$t/gh-junk" <<'X'
#!/bin/sh
echo '{"message":"nope"}'
X
cat >"$t/gh-sev" <<'X'
#!/bin/sh
echo '[[{"security_advisory":{"severity":"weird"}}]]'
X
chmod +x "$t"/gh-*
run() { SECURITY_ALERTS_GH="$t/$1" SECURITY_ALERTS_REPOS=o/r SECURITY_ALERTS_NOW=2026-01-01T00:00:00Z "$here/security-alerts" --json 2>"$t/err"; }

out=$(run gh-ok); check "exit 0" "$?" 0
check "counts across pages" "$(echo "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin)["repos"][0]; print(r["critical"],r["high"],r["medium"],r["low"],r["total"])')" "1 2 0 1 4"
check "red on a critical" "$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["red"])')" "True"
out=$(run gh-nocrit); check "not red without a critical" "$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["red"])')" "False"
for g in gh-fail gh-junk gh-sev; do
  out=$(run $g); rc=$?
  check "$g exits 2" "$rc" 2
  check "$g prints no numbers" "$out" ""
  check "$g says why" "$( [ -s "$t/err" ] && echo yes || echo no)" yes
done
SECURITY_ALERTS_GH="$t/nope" SECURITY_ALERTS_REPOS=o/r "$here/security-alerts" >/dev/null 2>&1; check "missing gh exits 2" "$?" 2
[ "$fails" -eq 0 ]
