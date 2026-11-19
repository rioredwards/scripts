#!/bin/sh
# system-catalog-test.sh: one fake home holding one piece of every kind; checks the catalog's entries,
# health mapping, overwrite behaviour and loud failure. Hermetic: nothing real is read.
set -u
root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT
SC="$root/system-catalog" W="$work" /usr/bin/python3 - <<'PY'
import json, os, plistlib, subprocess, sys

W, SC = os.environ["W"], os.environ["SC"]
H = os.path.join(W, "home")
env = dict(os.environ, SYSTEM_CATALOG_HOME=H, SYSTEM_CATALOG_SKILLS=os.path.join(H, "dev/agent-skills"),
           SYSTEM_CATALOG_PM2_JSON=os.path.join(W, "pm2.json"))
OUT = os.path.join(W, "out/catalog.json")


def put(rel, text, mode=0o644):
    path = os.path.join(H, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, mode)


def run():
    return subprocess.run([SC, "--out", OUT], env=env, capture_output=True, text=True)


put("dev/agent-skills/plugins/demo/skills/hello/SKILL.md", "---\nname: hello\ndescription: Say hello.\n---\nbody\n")
put("dev/agent-skills/plugins/demo/.claude-plugin/plugin.json", json.dumps({"name": "demo", "description": "A demo plugin."}))
put(".claude/settings.json", json.dumps({"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\"$HOME/scripts/hooks/lib/hooklog\" Stop 'bash \"$HOME/scripts/hooks/reply-cap.sh\"'"}]}]}}))
put("scripts/hooks/rules/rules.json", json.dumps({"rules": [{"id": "no-x", "on": "tool", "do": "deny"}]}))
for rel in ("scripts/good", "scripts/bad", "scripts/skipped", "scripts/unlisted", "tools/t/tool-one"):
    put(rel, "#!/bin/sh\n", 0o755)
put("scripts/notes.txt", "not executable")
put("Library/LaunchAgents/com.rioredwards.nightly.plist", plistlib.dumps({"Label": "com.rioredwards.nightly", "StartCalendarInterval": {"Hour": 3, "Minute": 40}}).decode())
put("Library/Application Support/Claude/claude-code-sessions/a/b/scheduled-tasks.json", json.dumps({"scheduledTasks": [
    {"id": "t-on", "cronExpression": "0 1 * * *", "enabled": True, "filePath": os.path.join(H, "task/SKILL.md")},
    {"id": "t-off", "cronExpression": "0 2 * * *", "enabled": False}]}))
put("Library/Application Support/Claude/claude-code-sessions/c/d/scheduled-tasks.json", json.dumps({"scheduledTasks": [{"id": "t-on", "enabled": True}]}))
put("task/SKILL.md", "---\nname: t-on\ndescription: Do the nightly thing.\n---\n")
put(".codex/automations/nj/automation.toml", 'name = "Nightly job"\nstatus = "PAUSED"\nrrule = "RRULE:FREQ=DAILY"\nprompt = "Look around."\n')
put("Library/Logs/tool-check/2026-11-18.log", "Tool check: old (h) 2026-11-18 03:20:00\n\n[BROKE] tool good - exit 9\n")
put("Library/Logs/tool-check/2026-11-19.log", "\n".join([
    "Tool check: 3 ok, 1 broke, 1 skipped (host) 2026-11-19 03:22:15", "",
    "[ok   ] tool good", "[BROKE] tool bad - exit 1", "[skip ] tool skipped - skip: not run", "[ok   ] tool list tool-inventory - all inventoried",
    "[BROKE] tool list unlisted - not inventoried: add a line to tool-inventory", "[ok   ] tool tool-one", "[ok   ] launchd job nightly",
    "[ok   ] Desktop task t-on", ""]))
with open(os.path.join(W, "pm2.json"), "w") as f:
    f.write("[PM2] banner\n" + json.dumps([{"name": "up", "pm2_env": {"status": "online", "pm_cwd": "/x"}}, {"name": "down", "pm2_env": {"status": "stopped"}}]))

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)


r = run()
check(r.returncode == 0, "run exits 0: " + r.stderr)
cat = json.load(open(OUT))
by = {(e["kind"], e["name"]): e for e in cat["entries"]}
kinds = sorted({e["kind"] for e in cat["entries"]})
check(kinds == sorted(["skill", "plugin", "hook", "hook rule", "tool", "launchd job", "pm2 process", "scheduled task", "nightly job"]), "every kind present: %s" % kinds)
check(by[("skill", "demo:hello")]["goal"] == "Say hello.", "skill goal is its description")
check(by[("plugin", "demo")]["goal"] == "A demo plugin.", "plugin goal")
check(("hook", "Stop * reply-cap.sh") in by, "hook named by event, matcher and script")
check(by[("hook rule", "no-x")]["trigger"] == "tool: deny", "rule trigger")
check(by[("tool", "good")]["health"] == "ok", "newest log wins: good is ok, not the older failure")
check(by[("tool", "bad")]["health"] == "failing" and by[("tool", "bad")]["reason"] == "exit 1", "BROKE tool is failing with its reason")
check(by[("tool", "skipped")]["health"] == "not checked", "skipped tool is not checked")
check(by[("tool", "unlisted")]["health"] == "failing", "uninventoried tool is failing")
check(("tool", "notes.txt") not in by and ("tool", "tool-one") in by, "only executables, scripts and tools dirs")
check(by[("launchd job", "nightly")]["trigger"] == "daily 03:40" and by[("launchd job", "nightly")]["health"] == "ok", "launchd trigger and health")
check(by[("scheduled task", "t-on")]["health"] == "ok" and by[("scheduled task", "t-on")]["goal"] == "Do the nightly thing.", "task health and goal; duplicate id once")
check(by[("scheduled task", "t-off")]["reason"] == "disabled", "disabled task is not checked")
check(by[("nightly job", "Nightly job")]["health"] == "not checked" and "PAUSED" in by[("nightly job", "Nightly job")]["reason"], "nightly job status")
check(by[("pm2 process", "up")]["health"] == "ok" and by[("pm2 process", "down")]["health"] == "failing", "pm2 health")
check(cat["sources"]["toolCheck"]["at"].startswith("2026-11-19T03:22:15"), "tool-check run time recorded")
check(all(e["lastAudited"] == "" and e["health"] in ("ok", "failing", "not checked") for e in cat["entries"]), "entry fields")
check(len(cat["generatedAt"]) > 10, "generatedAt")

first = open(OUT).read()
run()
check(len(open(OUT).read()) == len(first), "second run overwrites, no growth")
for day in ("18", "19"):
    os.remove(os.path.join(H, "Library/Logs/tool-check/2026-11-%s.log" % day))
r = run()
check(r.returncode != 0 and "no tool-check log" in r.stderr, "missing tool-check log fails loudly")
check(open(OUT).read() == first, "failed run leaves the old file untouched")

print("\n".join("FAIL: " + f for f in fails) if fails else "system-catalog: all checks passed")
sys.exit(1 if fails else 0)
PY
