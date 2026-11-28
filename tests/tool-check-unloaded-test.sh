#!/bin/bash
# tool-check flags a com.rio* LaunchAgent that is installed but not loaded (it would never run,
# so the nonzero-exit check alone never sees it). Loaded jobs and jobs turned off on purpose
# (plist Disabled, or `launchctl disable`) are not reported broken.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/scripts/tests" "$t/tools" "$t/LaunchAgents" "$t/sessions/a/b"
printf 'exit 0\n' > "$t/scripts/tests/run-all.sh"
: > "$t/scripts/tool-inventory"
printf '{"scheduledTasks": []}' > "$t/sessions/a/b/scheduled-tasks.json"
printf -- '-\t0\tcom.rioredwards.good\n' > "$t/launchctl.txt"
plist() { # label disabled
  /usr/bin/python3 -c 'import plistlib,sys; d={"Label":sys.argv[1],"ProgramArguments":["/bin/true"]}
if sys.argv[2]=="1": d["Disabled"]=True
open(sys.argv[3],"wb").write(plistlib.dumps(d))' "$1" "$2" "$t/LaunchAgents/$1.plist"
}
plist com.rioredwards.good 0
plist com.rioredwards.dead 0
plist com.rioredwards.off 1
plist com.rioredwards.paused 0
printf 'disabled services = {\n\t\t"com.rioredwards.paused" => disabled\n\t\t"com.rioredwards.dead" => enabled\n\t}\n' > "$t/disabled.txt"
out="$(TZ=UTC TOOL_CHECK_NOW=2026-10-14T12:00:00Z TOOL_CHECK_SCRIPTS="$t/scripts" TOOL_CHECK_TOOLS="$t/tools" \
  TOOL_CHECK_LOGDIR="$t/logs" TOOL_CHECK_INBOX_DIR="$t/inbox" TOOL_CHECK_ASKS="$t/asks.md" \
  TOOL_CHECK_TASKS_GLOB="$t/sessions/*/*/scheduled-tasks.json" TOOL_CHECK_PLISTS="$t/LaunchAgents" \
  TOOL_CHECK_LAUNCHCTL_LIST="$t/launchctl.txt" TOOL_CHECK_DISABLED="$t/disabled.txt" "$here/tool-check" 2>&1 || true)"
fail() { echo "tool-check-unloaded-test: FAIL: $1"; echo "$out"; exit 1; }
grep -q 'BROKE launchd job dead: installed but not loaded' <<<"$out" || fail "unloaded job not flagged"
for j in good off paused; do
  if grep -q "BROKE launchd job $j" <<<"$out"; then fail "$j job flagged"; fi
done
echo "tool-check-unloaded-test: ok"
