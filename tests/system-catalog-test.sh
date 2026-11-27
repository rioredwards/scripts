#!/bin/sh
# system-catalog-test.sh: one fake home holding one piece of every kind; checks the catalog's entries,
# health mapping, overwrite behaviour and loud failure. Hermetic: nothing real is read.
set -u
root="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT
SC="$root/system-catalog" W="$work" /usr/bin/python3 - <<'PY'
import json, os, plistlib, sqlite3, subprocess, sys

W, SC = os.environ["W"], os.environ["SC"]
H = os.path.join(W, "home")
env = dict(os.environ, SYSTEM_CATALOG_HOME=H, SYSTEM_CATALOG_SKILLS=os.path.join(H, "dev/agent-skills"),
           SYSTEM_CATALOG_PM2_JSON=os.path.join(W, "pm2.json"), SYSTEM_CATALOG_NOW="1795777229")
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
put("dev/agent-skills/plugins/demo/skills/long/SKILL.md", "---\nname: long\ndescription: >-\n  First part\n  second part.\nother: x\n---\n")
put("dev/agent-skills/plugins/demo/.claude-plugin/plugin.json", json.dumps({"name": "demo", "description": "A demo plugin."}))
put(".claude/settings.json", json.dumps({"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\"$HOME/scripts/hooks/lib/hooklog\" Stop 'bash \"$HOME/scripts/hooks/reply-cap.sh\"'"}]}]}}))
put("scripts/hooks/rules/rules.json", json.dumps({"rules": [{"id": "no-x", "on": "tool", "do": "deny"}]}))
for rel in ("scripts/good", "scripts/bad", "scripts/skipped", "scripts/unlisted", "tools/t/tool-one"):
    put(rel, "#!/bin/sh\n", 0o755)
os.symlink("../tools/t/tool-one", os.path.join(H, "scripts/tool-link"))
put("scripts/notes.txt", "not executable")
put("Library/LaunchAgents/com.rioredwards.nightly.plist", plistlib.dumps({"Label": "com.rioredwards.nightly", "StartCalendarInterval": {"Hour": 3, "Minute": 40}}).decode())
put("Library/Application Support/Claude/claude-code-sessions/a/b/scheduled-tasks.json", json.dumps({"scheduledTasks": [
    {"id": "t-on", "cronExpression": "0 1 * * *", "enabled": True, "filePath": os.path.join(H, "task/SKILL.md")},
    {"id": "t-off", "cronExpression": "0 2 * * *", "enabled": False}]}))
put("Library/Application Support/Claude/claude-code-sessions/c/d/scheduled-tasks.json", json.dumps({"scheduledTasks": [{"id": "t-on", "enabled": True}]}))
put("task/SKILL.md", "---\nname: t-on\ndescription: Do the nightly thing.\n---\n")
put(".codex/automations/nj/automation.toml", 'id = "nj"\nname = "Nightly job"\nstatus = "PAUSED"\nrrule = "RRULE:FREQ=DAILY"\nprompt = "Look around."\n')
NOW_MS = 1795777229 * 1000
HOUR = 3600 * 1000
CODEX_DB = os.path.join(H, ".codex/sqlite/codex.db")


def automation(id, status, rrule, created_h_ago=24 * 30, kind="cron"):
    put(".codex/automations/%s/automation.toml" % id, 'version = 1\nid = "%s"\nkind = "%s"\nname = "Job %s"\nprompt = "p"\nstatus = "%s"\nrrule = "%s"\ncreated_at = %d\n'
        % (id, kind, id, status, rrule, NOW_MS - created_h_ago * HOUR))


STATE_DB = os.path.join(H, ".codex/state_5.sqlite")
UNFINISHED = {}  # (automation, hours ago) -> (last event, rollout age in seconds)


def make_db(runs, last_runs=()):
    os.makedirs(os.path.dirname(CODEX_DB), exist_ok=True)
    for path in (CODEX_DB, STATE_DB):
        if os.path.exists(path):
            os.remove(path)
    db = sqlite3.connect(CODEX_DB)
    db.execute("CREATE TABLE automation_runs (thread_id TEXT PRIMARY KEY, automation_id TEXT NOT NULL, status TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)")
    db.execute("CREATE TABLE automations (id TEXT PRIMARY KEY, last_run_at INTEGER)")
    st = sqlite3.connect(STATE_DB)
    st.execute("CREATE TABLE threads (id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL)")
    for i, (aid, status, h_ago) in enumerate(runs):
        tid = "th%d" % i
        db.execute("INSERT INTO automation_runs VALUES (?,?,?,?,?)", (tid, aid, status, NOW_MS - int(h_ago * HOUR), NOW_MS - int(h_ago * HOUR)))
        rollout = os.path.join(W, "rollouts/%s.jsonl" % tid)
        os.makedirs(os.path.dirname(rollout), exist_ok=True)
        event, age = UNFINISHED.get((aid, h_ago), ("task_complete", 60))
        with open(rollout, "w") as rf:
            rf.write('{"type":"session_meta"}\n' + ('{"type":"event_msg","payload":{"type":"%s"}}\n' % event if event else ""))
        os.utime(rollout, (NOW_MS // 1000 - age, NOW_MS // 1000 - age))
        st.execute("INSERT INTO threads VALUES (?,?)", (tid, rollout))
    for aid, h_ago in last_runs:
        db.execute("INSERT INTO automations VALUES (?,?)", (aid, NOW_MS - int(h_ago * HOUR)))
    for c in (db, st):
        c.commit()
        c.close()


daily, hourly, weekly_mon = "RRULE:FREQ=DAILY;BYHOUR=3;BYMINUTE=0", "RRULE:FREQ=HOURLY;BYMINUTE=0", "RRULE:FREQ=WEEKLY;BYDAY=MO;BYHOUR=9"
automation("a-ok", "ACTIVE", daily)
automation("a-stale", "ACTIVE", daily)
automation("a-never", "ACTIVE", daily)
automation("a-new", "ACTIVE", daily, created_h_ago=1)
automation("a-fail", "ACTIVE", daily)
automation("a-hb", "ACTIVE", hourly, kind="heartbeat")
automation("a-weekly", "ACTIVE", weekly_mon)
automation("a-paused-stale", "PAUSED", daily)
automation("a-abort", "ACTIVE", daily)
automation("a-abort-old", "ACTIVE", daily)
automation("a-running", "ACTIVE", daily)
automation("a-stuck", "ACTIVE", daily)
RUNS = [("a-ok", "ARCHIVED", 60), ("a-ok", "PENDING_REVIEW", 10), ("a-stale", "PENDING_REVIEW", 96), ("a-fail", "PENDING_REVIEW", 40),
        ("a-fail", "FAILED", 10), ("a-weekly", "PENDING_REVIEW", 120), ("a-paused-stale", "PENDING_REVIEW", 500),
        ("a-abort", "PENDING_REVIEW", 40), ("a-abort", "PENDING_REVIEW", 12), ("a-abort-old", "PENDING_REVIEW", 40), ("a-abort-old", "PENDING_REVIEW", 12),
        ("a-running", "PENDING_REVIEW", 0.1), ("a-stuck", "PENDING_REVIEW", 2)]
UNFINISHED.update({("a-abort", 12): ("turn_aborted", 60), ("a-abort-old", 40): ("turn_aborted", 60), ("a-paused-stale", 500): ("turn_aborted", 60),
                   ("a-running", 0.1): (None, 120), ("a-stuck", 2): (None, 3600)})
make_db(RUNS, [("a-hb", 0.5)])
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
check(by[("skill", "demo:long")]["goal"] == "First part second part.", "multi-line description becomes the goal")
check(by[("plugin", "demo")]["goal"] == "A demo plugin.", "plugin goal")
check(("hook", "Stop * reply-cap.sh") in by, "hook named by event, matcher and script")
check(by[("hook rule", "no-x")]["trigger"] == "tool: deny", "rule trigger")
check(by[("tool", "good")]["health"] == "ok", "newest log wins: good is ok, not the older failure")
check(by[("tool", "bad")]["health"] == "failing" and by[("tool", "bad")]["reason"] == "exit 1", "BROKE tool is failing with its reason")
check(by[("tool", "skipped")]["health"] == "not checked", "skipped tool is not checked")
check(by[("tool", "unlisted")]["health"] == "failing", "uninventoried tool is failing")
check(("tool", "tool-link") not in by and sum(k[1] == "tool-one" for k in by) == 1, "a symlinked tool is one piece")
check(("tool", "notes.txt") not in by and ("tool", "tool-one") in by, "only executables, scripts and tools dirs")
check(by[("launchd job", "nightly")]["trigger"] == "daily 03:40" and by[("launchd job", "nightly")]["health"] == "ok", "launchd trigger and health")
check(by[("scheduled task", "t-on")]["health"] == "ok" and by[("scheduled task", "t-on")]["goal"] == "Do the nightly thing.", "task health and goal; duplicate id once")
check(by[("scheduled task", "t-off")]["reason"] == "disabled", "disabled task is not checked")
check(by[("nightly job", "Nightly job")]["health"] == "not checked" and "paused" in by[("nightly job", "Nightly job")]["reason"], "paused nightly job is shown as paused, not failing")
nj = lambda i: by[("nightly job", "Job " + i)]
check(nj("a-ok")["health"] == "ok", "latest run inside the window is ok")
check(nj("a-stale")["health"] == "failing" and "has not run" in nj("a-stale")["reason"], "last run outside the window: has not run when it should have")
check(nj("a-never")["health"] == "failing" and "has not run" in nj("a-never")["reason"], "old job that never ran is failing, not fine")
check(nj("a-new")["health"] == "not checked" and "not due" in nj("a-new")["reason"], "brand-new job with no run yet is not failing")
check(nj("a-fail")["health"] == "failing" and "FAILED" in nj("a-fail")["reason"], "latest run failed beats an older ok run")
check(nj("a-hb")["health"] == "ok", "heartbeat run is read from automations.last_run_at")
check(nj("a-weekly")["health"] == "ok", "weekly job 5 days after its run is still inside the window")
check(nj("a-paused-stale")["health"] == "not checked" and "paused" in nj("a-paused-stale")["reason"], "paused job with a stale run is paused, not failing")
check(nj("a-abort")["health"] == "failing" and "did not finish" in nj("a-abort")["reason"], "latest run with turn_aborted is failing")
check(nj("a-running")["health"] == "not checked" and "running now" in nj("a-running")["reason"], "unfinished run with a recently written rollout is running now, not failing")
check(nj("a-stuck")["health"] == "failing" and "never finished" in nj("a-stuck")["reason"], "unfinished run with a stale rollout is failing")
check(nj("a-abort-old")["health"] == "ok", "an older unfinished run does not matter once the latest finished")
check(nj("a-paused-stale")["health"] == "not checked" and "paused" in nj("a-paused-stale")["reason"], "paused job's rollout is never read")
check("no run record" in nj("a-hb")["reason"], "heartbeat with no automation_runs row says its ok is unverified for finishing")
check(not any("no check yet" in e["reason"] for e in cat["entries"] if e["kind"] == "nightly job"), "no nightly job says no check yet")
check(by[("pm2 process", "up")]["health"] == "ok" and by[("pm2 process", "down")]["health"] == "failing", "pm2 health")
check(cat["sources"]["toolCheck"]["at"].startswith("2026-11-19T03:22:15"), "tool-check run time recorded")
check(all(e["lastAudited"] == "" and e["health"] in ("ok", "failing", "not checked") for e in cat["entries"]), "entry fields")
check(len(cat["generatedAt"]) > 10, "generatedAt")

first = open(OUT).read()
run()
check(len(open(OUT).read()) == len(first), "second run overwrites, no growth")
first = open(OUT).read()
hold = CODEX_DB + ".held"
os.rename(CODEX_DB, hold)
check((r := run()).returncode != 0 and "codex.db" in r.stderr and open(OUT).read() == first, "missing codex database fails loudly, old file kept")
os.rename(hold, CODEX_DB)
db = sqlite3.connect(CODEX_DB); db.execute("DROP TABLE automation_runs"); db.commit(); db.close()
check((r := run()).returncode != 0 and "automation_runs" in r.stderr and open(OUT).read() == first, "missing table fails loudly, old file kept")
make_db(RUNS + [("a-ok", "WEIRD_NEW_STATE", 1)], [("a-hb", 0.5)])
check((r := run()).returncode != 0 and "WEIRD_NEW_STATE" in r.stderr and open(OUT).read() == first, "unknown run status fails loudly")
make_db(RUNS, [("a-hb", 0.5)])
hold = STATE_DB + ".held"
os.rename(STATE_DB, hold)
check((r := run()).returncode != 0 and "state_5.sqlite" in r.stderr and open(OUT).read() == first, "missing state database fails loudly")
os.rename(hold, STATE_DB)
st = sqlite3.connect(STATE_DB); st.execute("DELETE FROM threads WHERE id='th1'"); st.commit(); st.close()
check((r := run()).returncode != 0 and "th1" in r.stderr and open(OUT).read() == first, "run without a thread row fails loudly")
make_db(RUNS, [("a-hb", 0.5)])
os.rename(os.path.join(W, "rollouts/th1.jsonl"), os.path.join(W, "rollouts/th1.held"))
check((r := run()).returncode != 0 and "th1" in r.stderr and open(OUT).read() == first, "missing rollout file fails loudly")
make_db(RUNS, [("a-hb", 0.5)])
for bad in ("RRULE:FREQ=DAILY;BYDAY=MO,TU", "RRULE:FREQ=HOURLY;BYDAY=MO,TU,WE,TH,FR"):
    automation("a-badshape", "ACTIVE", bad)
    check((r := run()).returncode != 0 and "a-badshape" in r.stderr and open(OUT).read() == first, "schedule the window rule cannot handle fails loudly: " + bad)
os.remove(os.path.join(H, ".codex/automations/a-badshape/automation.toml"))
for bad, err in (("[BROKE] launchd job launchctl - list failed", "match no catalog entry"), ("[BROKE] tool check inventory - check crashed", "unrecognized")):
    put("Library/Logs/tool-check/2026-11-19.log", "Tool check: (h) 2026-11-19 03:22:15\n\n%s\n" % bad)
    check((r := run()).returncode != 0 and err in r.stderr and open(OUT).read() == first, "fails loudly, old file kept: " + bad)
for day in ("18", "19"):
    os.remove(os.path.join(H, "Library/Logs/tool-check/2026-11-%s.log" % day))
r = run()
check(r.returncode != 0 and "no tool-check log" in r.stderr, "missing tool-check log fails loudly")
check(open(OUT).read() == first, "failed run leaves the old file untouched")

print("\n".join("FAIL: " + f for f in fails) if fails else "system-catalog: all checks passed")
sys.exit(1 if fails else 0)
PY
