"""Tests for ../tool-check, using temp-dir fixtures (no real tools, jobs, tasks or inbox are touched).

  python3 tests/tool-check-test.py
"""
import importlib.machinery
import importlib.util
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
TOOL = str(Path(__file__).parents[1] / "tool-check")
PM_GATHER = Path.home() / "dev/project-manager/scripts/pm-gather.sh"
NOW = "2026-10-14T12:00:00Z"  # a Wednesday, run with TZ=UTC
BROKEN = "# comment\npass | {S}/pass\nfail | {S}/fail\nskipped | skip: sends messages\nsynt | syntax\n"
CLEAN = BROKEN.replace("{S}/fail", "{S}/pass")
os.environ["TZ"] = "UTC"
time.tzset()

loader = importlib.machinery.SourceFileLoader("tool_check", TOOL)
spec = importlib.util.spec_from_loader(loader.name, loader)
tc = importlib.util.module_from_spec(spec)
loader.exec_module(tc)


def utc(s):
    return tc.iso_epoch(s + "Z")


class CronTests(unittest.TestCase):
    def slot(self, expr, at):
        ts = tc.cron_last_slot(expr, utc(at))
        return time.strftime("%Y-%m-%d %H:%M", time.gmtime(ts))

    def test_daily_and_exact_slot(self):
        self.assertEqual(self.slot("0 9 * * *", "2026-10-14T11:45:00"), "2026-10-14 09:00")
        self.assertEqual(self.slot("0 9 * * *", "2026-10-14T08:59:00"), "2026-10-13 09:00")
        self.assertEqual(self.slot("0 9 * * *", "2026-10-14T09:00:00"), "2026-10-14 09:00")

    def test_weekday_and_sunday_as_0_or_7(self):
        self.assertEqual(self.slot("30 8 * * 1", "2026-10-14T12:00:00"), "2026-10-12 08:30")  # Monday
        self.assertEqual(self.slot("0 6 * * 0", "2026-10-14T12:00:00"), "2026-10-11 06:00")
        self.assertEqual(self.slot("0 6 * * 7", "2026-10-14T12:00:00"), "2026-10-11 06:00")

    def test_steps_and_lists(self):
        self.assertEqual(self.slot("*/15 * * * *", "2026-10-14T12:07:00"), "2026-10-14 12:00")
        self.assertEqual(self.slot("0 8,17 * * 1-5", "2026-10-14T12:00:00"), "2026-10-14 08:00")
        self.assertEqual(self.slot("10/20 * * * *", "2026-10-14T12:35:00"), "2026-10-14 12:30")

    def test_dom_or_dow_when_both_restricted(self):
        # "midnight on the 1st OR on any Sunday": Sunday 10-11 is newer than the 1st
        self.assertEqual(self.slot("0 0 1 * 0", "2026-10-14T12:00:00"), "2026-10-11 00:00")

    def test_bad_expressions(self):
        for bad in ("* * * *", "61 * * * *", "a * * * *", "5-2 * * * *"):
            with self.assertRaises(ValueError, msg=bad):
                tc.cron_last_slot(bad, utc("2026-10-14T12:00:00"))


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        r = Path(self.tmp.name)
        self.scripts, self.tools, self.inbox = r / "scripts", r / "tools", r / "inbox"
        self.logdir, self.asks, self.plists = r / "logs", r / "asks.md", r / "LaunchAgents"
        self.launchctl, self.tasks_dir = r / "launchctl.txt", r / "sessions/a/b"
        for d in (self.scripts / "tests", self.tools, self.plists, self.tasks_dir):
            d.mkdir(parents=True)
        (self.scripts / "tests/run-all.sh").write_text("exit 0\n")
        self.exe("pass", "#!/bin/sh\nexit 0\n")
        self.exe("fail", "#!/bin/sh\necho boom >&2\nexit 3\n")
        self.exe("skipped", "#!/bin/sh\nexit 0\n")
        self.exe("synt", "#!/bin/sh\necho ok\n")
        self.inventory(BROKEN)
        self.launchctl.write_text("-\t0\tcom.rioredwards.good\n-\t0\tcom.apple.thing\n")
        self.tasks()

    def exe(self, name, body):
        p = self.scripts / name
        p.write_text(body)
        p.chmod(0o755)

    def inventory(self, text):
        (self.scripts / "tool-inventory").write_text(text.replace("{S}", str(self.scripts)))

    def tasks(self, tasks=None, runs=()):
        (self.tasks_dir / "scheduled-tasks.json").write_text(json.dumps({"scheduledTasks": tasks or []}))
        for i, rec in enumerate(runs):
            (self.tasks_dir / ("local_%d.json" % i)).write_text(json.dumps(rec))

    def run_tool(self, *args):
        env = dict(os.environ, TZ="UTC", TOOL_CHECK_NOW=NOW, TOOL_CHECK_SCRIPTS=str(self.scripts), TOOL_CHECK_TOOLS=str(self.tools),
                   TOOL_CHECK_LOGDIR=str(self.logdir), TOOL_CHECK_INBOX_DIR=str(self.inbox), TOOL_CHECK_ASKS=str(self.asks),
                   TOOL_CHECK_TASKS_GLOB=str(self.tasks_dir.parent.parent / "*/*/scheduled-tasks.json"),
                   TOOL_CHECK_PLISTS=str(self.plists), TOOL_CHECK_LAUNCHCTL_LIST=str(self.launchctl))
        t0 = time.time()
        p = subprocess.run([TOOL, *args], env=env, capture_output=True, text=True, timeout=120)
        return p, time.time() - t0

    def log(self):
        return (self.logdir / "2026-10-14.log").read_text()

    # slice 1: tools

    def test_pass_fail_hang_skip_and_uninventoried(self):
        self.exe("stray", "#!/bin/sh\nexit 0\n")
        self.inventory(BROKEN + "hang | [1s] sleep 30\n")
        (self.scripts / "dangling").symlink_to(self.scripts / "nope")
        p, secs = self.run_tool()
        self.assertEqual(p.returncode, 1)
        out = p.stdout
        self.assertIn("BROKE tool fail: exit 3: boom", out)
        self.assertIn("BROKE tool hang: timed out after 1s", out)
        self.assertLess(secs, 20, "a hanging tool must be killed at its timeout")
        self.assertIn("BROKE tool list stray: not inventoried", out)
        self.assertIn("BROKE tool list dangling: dangling symlink", out)
        self.assertNotIn("BROKE tool pass", out)
        self.assertNotIn("BROKE tool skipped", out)
        self.assertNotIn("BROKE tool synt", out)
        log = self.log()
        self.assertIn("[skip ] tool skipped - skip: sends messages", log)
        self.assertIn("[ok   ] tool pass", log)
        self.assertIn("command: %s/fail" % self.scripts, log)

    def test_all_good_exits_zero(self):
        self.inventory(CLEAN)
        p, _ = self.run_tool()
        self.assertEqual(p.returncode, 0, p.stdout)
        self.assertIn("0 broke", p.stdout)

    def test_bad_inventory_lines(self):
        self.inventory("pass | {S}/pass\npass | {S}/pass\nno-separator\nskipped | skip:\nsynt | syntax\nfail | {S}/pass\n")
        p, _ = self.run_tool()
        self.assertEqual(p.returncode, 1)
        self.assertIn("duplicate name", p.stdout)
        self.assertIn("want 'name | check command'", p.stdout)
        self.assertIn("skip needs a reason", p.stdout)

    def test_syntax_error_detected(self):
        self.exe("synt", "#!/bin/sh\nif then fi (\n")
        p, _ = self.run_tool()
        self.assertIn("BROKE tool synt", p.stdout)

    def test_failing_test_suite_and_missing_run_all(self):
        (self.scripts / "tests/run-all.sh").write_text("echo nope\nexit 1\n")
        t = self.tools / "thing"
        t.mkdir()
        (t / "test.sh").write_text("exit 0\n")
        p, _ = self.run_tool()
        self.assertIn("BROKE test suite scripts tests (run-all.sh): exit 1", p.stdout)
        self.assertIn("[ok   ] test suite thing tests", self.log())
        (self.scripts / "tests/run-all.sh").unlink()
        p, _ = self.run_tool()
        self.assertIn("BROKE test suite scripts tests (run-all.sh): exit", p.stdout)

    # slice 2: launchd jobs and Desktop tasks

    def test_launchd_nonzero_exit_with_log_tail(self):
        logf = self.scripts / "bad.err"
        logf.write_text("line1\nssh: timed out\n")
        (self.plists / "com.rioredwards.bad.plist").write_bytes(
            plistlib.dumps({"Label": "com.rioredwards.bad", "ProgramArguments": ["/bin/zsh", "-c", "x"], "StandardErrorPath": str(logf)}))
        self.launchctl.write_text("-\t0\tcom.rioredwards.good\n-\t1\tcom.rioredwards.bad\n-\t78\tcom.apple.nope\n")
        p, _ = self.run_tool()
        self.assertIn("BROKE launchd job bad: last run exited 1: ssh: timed out", p.stdout)
        self.assertNotIn("good", p.stdout)
        self.assertNotIn("apple", p.stdout)

    def test_no_rio_jobs_is_broken(self):
        self.launchctl.write_text("-\t0\tcom.apple.thing\n")
        p, _ = self.run_tool()
        self.assertIn("no com.rio* jobs", p.stdout)

    def test_missed_slot_and_errored_run(self):
        base = {"cronExpression": "0 9 * * *", "enabled": True, "createdAt": 1767225600000}
        self.tasks([
            dict(base, id="on-time", lastScheduledFor="2026-10-14T09:00:00.000Z"),
            dict(base, id="missed", lastScheduledFor="2026-10-13T09:00:00.000Z"),
            dict(base, id="errored", lastScheduledFor="2026-10-14T09:00:00.000Z"),
            dict(base, id="off", enabled=False, lastScheduledFor="2026-01-01T09:00:00.000Z"),
            dict(base, id="bad-cron", cronExpression="nonsense"),
            dict(base, id="brand-new", createdAt=int(utc("2026-10-14T09:30:00") * 1000)),
        ], runs=[
            {"scheduledTaskId": "errored", "createdAt": 1, "error": "old failure, superseded"},
            {"scheduledTaskId": "errored", "createdAt": 2, "error": "session crashed\nbadly"},
            {"scheduledTaskId": "on-time", "createdAt": 3},
        ])
        p, _ = self.run_tool()
        out = p.stdout
        self.assertIn("BROKE Desktop task missed: missed its Wed Oct 14 09:00 run", out)
        self.assertIn("BROKE Desktop task errored: latest run failed: session crashed badly", out)
        self.assertIn("BROKE Desktop task bad-cron: cannot read schedule", out)
        for fine in ("on-time", "off", "brand-new"):
            self.assertNotIn("BROKE Desktop task %s" % fine, out)

    def test_recent_slot_gets_grace(self):
        self.tasks([{"id": "t", "enabled": True, "cronExpression": "55 11 * * *", "createdAt": 1767225600000,
                     "lastScheduledFor": "2026-10-13T11:55:00.000Z"}])
        p, _ = self.run_tool()
        self.assertNotIn("BROKE Desktop task t", p.stdout)  # 11:55 slot is inside the 15 minute grace at 12:00

    def test_missing_or_unreadable_tasks_file(self):
        (self.tasks_dir / "scheduled-tasks.json").write_text("{not json")
        p, _ = self.run_tool()
        self.assertIn("BROKE Desktop task", p.stdout)
        self.assertIn("unreadable", p.stdout)
        (self.tasks_dir / "scheduled-tasks.json").unlink()
        p, _ = self.run_tool()
        self.assertIn("no file found", p.stdout)

    # slice 4: inbox

    def inbox_file(self):
        return self.inbox / "2026-10-14-tool-check.md"

    def test_a_crashing_check_family_is_reported_and_the_rest_still_run(self):
        (self.scripts / "tool-inventory").unlink()  # the inventory check raises FileNotFoundError
        (self.tasks_dir / "scheduled-tasks.json").write_text(json.dumps({"scheduledTasks": [{"id": "x", "enabled": True, "cronExpression": "0 9 * * *"}]}))
        self.launchctl.write_text("-\t1\tcom.rioredwards.bad\n")
        p, _ = self.run_tool("--inbox")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn("inventory: check crashed: FileNotFoundError", p.stdout)
        self.assertIn("BROKE launchd job bad", p.stdout)  # a later family still ran
        text = self.inbox_file().read_text()
        self.assertIn("- status: Broken tool check inventory: check crashed: FileNotFoundError", text)
        self.assertEqual(len([l for l in text.splitlines() if l.startswith("- ask:")]), 1)

    def test_inbox_clean_run_has_only_status(self):
        self.inventory(CLEAN)
        p, _ = self.run_tool("--inbox")
        self.assertEqual(p.returncode, 0)
        text = self.inbox_file().read_text()
        self.assertRegex(text, r"^- status: Tool check: \d+ ok, 0 broke\n$")
        self.assertEqual([f.name for f in self.inbox.iterdir()], ["2026-10-14-tool-check.md"])

    def test_inbox_broken_run_writes_status_and_one_ask(self):
        self.asks.write_text("# Asks\n- A1 [open] 2026-10-01 audit: something else | yes: x | link: y\n")
        p, _ = self.run_tool("--inbox")
        self.assertEqual(p.returncode, 0, "the report is the alert; --inbox exits 0")
        lines = self.inbox_file().read_text().splitlines()
        self.assertRegex(lines[0], r"^- status: Tool check: \d+ ok, 1 broke$")
        self.assertIn("- status: Broken tool fail: exit 3: boom", lines)
        asks = [l for l in lines if l.startswith("- ask:")]
        self.assertEqual(len(asks), 1)
        self.assertIn("fail", asks[0])

    def test_inbox_no_second_ask_while_one_is_open(self):
        self.asks.write_text("- A9 [open] 2026-10-13 tool-check: 1 tools or jobs broke | yes: x | link: y\n")
        self.run_tool("--inbox")
        self.assertNotIn("- ask:", self.inbox_file().read_text())
        self.asks.write_text("- A9 [yes 2026-10-13] 2026-10-12 tool-check: 1 tools or jobs broke | yes: x | link: y\n")
        self.run_tool("--inbox")
        self.assertIn("- ask:", self.inbox_file().read_text())

    def test_inbox_passes_the_real_pm_gather_validator(self):
        if not PM_GATHER.is_file():
            self.skipTest("project-manager/scripts/pm-gather.sh not on this machine")
        m = re.search(r"python3 - \"\$1\" <<'PY'\n(.*?)\nPY\n", PM_GATHER.read_text(), re.S)
        self.assertIsNotNone(m, "pm-gather.sh inbox validator not found; update this test")
        validator = Path(self.tmp.name) / "validator.py"
        validator.write_text(m.group(1))
        # a broken run (status + ask lines), then a clean run (status line only)
        for inventory in (BROKEN, CLEAN):
            self.inventory(inventory)
            self.run_tool("--inbox")
            p = subprocess.run([sys.executable, "-I", str(validator), str(self.inbox)], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
            self.assertNotIn("ERROR", p.stdout)


if __name__ == "__main__":
    unittest.main()
