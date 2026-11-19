#!/bin/bash
# dev-sweep-all: discovery, dry run, failure isolation, inbox lines, log pruning.
# Uses a fake dev-sweep and a COPY of pm_inbox.py in a throwaway dir: never the real inbox.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
real_inbox="$HOME/dev/project-manager/scripts/pm_inbox.py"
[ -f "$real_inbox" ] || { echo "dev-sweep-all-test: $real_inbox missing" >&2; exit 1; }
python3 - "$root/dev-sweep-all" "$real_inbox" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile

wrapper, real_inbox = sys.argv[1], sys.argv[2]
passed, failures = 0, []


def check(name, condition, detail=""):
    global passed
    if condition:
        passed += 1
    else:
        failures.append(f"{name}: {detail}")


FAKE = '''#!/usr/bin/env python3
import json, os, sys
repo = sys.argv[1]
name = os.path.basename(repo)
with open(os.environ["FAKE_CALLS"], "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\\n")
if name == "bad":
    print("noise first\\ndev-sweep: boom", file=sys.stderr); sys.exit(2)
trees = [{"dir": repo, "branch": "main", "verdict": "keep", "reasons": ["primary checkout"], "envFiles": 0}]
for i in range(int(os.environ.get("FAKE_KEEPS_" + name, "1"))):
    trees.append({"dir": f"{repo}-w{i}", "branch": f"b{i}", "verdict": "keep",
                  "reasons": ["uncommitted: 1 modified (x)" if i % 2 else "idle under 24h"], "envFiles": 0})
code = 0
if name == "leftover":
    trees.append({"dir": f"{repo}-half", "branch": "h", "verdict": "partial", "reasons": ["unregistered leftover"], "envFiles": 0})
    code = 3
key = "removed" if "--apply" in sys.argv else "wouldRemove"
print(json.dumps({"worktrees": trees, "total": len(trees), key: 0, "wouldKeep": len(trees), "partial": int(code == 3)}))
sys.exit(code)
'''


class Env:
    def __init__(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp()).resolve()
        self.dev = self.tmp / "dev"
        self.logs = self.tmp / "logs"
        pm = self.tmp / "pm" / "scripts"
        pm.mkdir(parents=True)
        shutil.copy(real_inbox, pm / "pm_inbox.py")
        self.pm, self.inbox = pm / "pm_inbox.py", self.tmp / "pm" / "inbox"
        self.fake = self.tmp / "fake-dev-sweep"
        self.fake.write_text(FAKE)
        self.fake.chmod(0o755)
        self.calls = self.tmp / "calls.log"
        self.marker = self.tmp / "enabled"
        self.marker.write_text("")
        self.env = {**os.environ, "HOME": str(self.tmp / "home"), "DEV_ROOT": str(self.dev), "SCRIPTS": str(self.tmp / "scriptsrepo"),
                    "DOTFILES": str(self.tmp / "plain-dotfiles"), "DEV_SWEEP_LOG_DIR": str(self.logs), "DEV_SWEEP_PM_INBOX": str(self.pm),
                    "DEV_SWEEP_BIN": str(self.fake), "DEV_SWEEP_MARKER": str(self.marker), "FAKE_CALLS": str(self.calls)}
        for rel, extra in (("alpha", 1), ("grp/beta", 1), ("bad", 1), ("big", 17), ("leftover", 1), ("single", 0)):
            self.repo(self.dev / rel, extra)
        self.repo(self.tmp / "scriptsrepo", 1)
        (self.dev / ".hidden-repo").mkdir()
        (self.tmp / "plain-dotfiles").mkdir()  # exists but is not a repo: skipped

    def repo(self, path, extra):
        path.mkdir(parents=True)
        g = lambda *a, cwd=path: subprocess.run(["git", "-C", str(cwd), *a], check=True, capture_output=True)
        g("init", "-q", "-b", "main")
        g("-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-q", "--allow-empty", "-m", "i")
        for i in range(extra):
            g("worktree", "add", "-qb", f"w{i}", str(self.tmp / "wt" / f"{path.name}-{i}"))

    def run(self, *args, extra=None):
        return subprocess.run([sys.executable, wrapper, *args], capture_output=True, text=True, env={**self.env, **(extra or {})})

    def inbox_text(self):
        return "".join(p.read_text() for p in sorted(self.inbox.glob("*.md"))) if self.inbox.exists() else ""

    def call_names(self):
        return [pathlib.Path(l.split()[0]).name for l in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def done(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


big = {"FAKE_KEEPS_big": "6"}

# --- discovery and dry run ---------------------------------------------------------------
e = Env()
out = e.run("--dry-run", extra=big)
names = sorted(e.call_names())
check("discovers repos with more than one worktree, two levels deep, plus SCRIPTS",
      names == ["alpha", "bad", "beta", "big", "leftover", "scriptsrepo"], str(names) + out.stderr)
check("single-worktree and hidden repos skipped", "single" not in names and ".hidden-repo" not in names)
check("dry run never passes --apply", "--apply" not in e.calls.read_text())
check("dry run writes nothing to the inbox", e.inbox_text() == "" and not e.inbox.exists(), e.inbox_text())
check("dry run prints what it would have written", "inbox (dry run, not written): Worktree sweep: big still has 18 worktrees" in out.stdout, out.stdout)
check("dry run writes a log", len(list(e.logs.glob("sweep-*-dry.log"))) == 1)
e.done()

# --- real run: failure isolation, lines, no duplicates ---------------------------------------
e = Env()
out = e.run(extra=big)
check("real run passes --apply", "--apply" in e.calls.read_text())
check("failing repo does not stop the rest", sorted(e.call_names()) == ["alpha", "bad", "beta", "big", "leftover", "scriptsrepo"], str(e.call_names()))
check("exit 1 when a repo failed", out.returncode == 1, str(out.returncode))
text = e.inbox_text()
check("failure line: repo and one-line error", "- status: Worktree sweep failed on bad: dev-sweep: boom" in text and "noise first" not in text, text)
check("over-15 line with reason tally", "- status: Worktree sweep: big still has 18 worktrees (" in text and "3 uncommitted" in text and "3 idle under 24h" in text, text)
check("exit 3 (leftover) line", "- status: Worktree sweep failed on leftover: could not delete leftover folders (leftover-half)" in text, text)
check("no line for a quiet repo", "alpha" not in text and "beta" not in text, text)
check("inbox file passes the real format check", subprocess.run([sys.executable, str(e.pm), "check"], capture_output=True, text=True).returncode == 0)
lines_before = text.count("\n")
e.run(extra=big)
check("second run adds no duplicate lines", e.inbox_text().count("\n") == lines_before, e.inbox_text())
# an unread line from an earlier day also counts
old = e.inbox / "2020-01-01-dev-sweep.md"
old.write_text("- status: Worktree sweep: big still has 99 worktrees (old)\n")
for p in list(e.inbox.glob("*.md")):
    if p != old:
        p.unlink()
e.run(extra=big)
check("an older unread line for the repo blocks a new one", "still has 18" not in e.inbox_text() and "failed on bad" in e.inbox_text(), e.inbox_text())
# a line for a repo whose name only starts with "big" does not block big
old.write_text("- status: Worktree sweep: big-backend still has 99 worktrees (old)\n")
e.run(extra=big)
check("a line for big-backend does not block big", "big still has 18" in e.inbox_text(), e.inbox_text())
e.done()

# --- one repo the wrapper cannot read: reported, the rest still run ----------------------------
e = Env()
(e.dev / "broken" / ".git").mkdir(parents=True)  # looks like a primary checkout, git rejects it
(e.dev / "alpha-link").symlink_to(e.dev / "alpha")
out = e.run(extra=big)
check("an unreadable repo does not stop the rest", sorted(e.call_names()) == ["alpha", "bad", "beta", "big", "leftover", "scriptsrepo"], str(e.call_names()) + out.stderr)
check("an unreadable repo gets a failure line", "- status: Worktree sweep failed on broken: " in e.inbox_text(), e.inbox_text() + out.stderr)
check("an unreadable repo makes the run exit 1", out.returncode == 1, str(out.returncode))
check("a symlink to a repo is swept once", e.call_names().count("alpha") == 1, str(e.call_names()))
e.done()

# --- missing roots fail loud ----------------------------------------------------------------------
e = Env()
for var in ("DEV_ROOT", "SCRIPTS", "DOTFILES"):
    out = e.run(extra={var: str(e.tmp / "missing")})
    check(f"missing {var} exits 2 and sweeps nothing", out.returncode == 2 and not e.calls.exists() and "is not a directory" in out.stderr, out.stderr)
e.done()

e = Env()
e.marker.unlink()
out = e.run()
check("real run without the marker does nothing and exits 0", out.returncode == 0 and not e.calls.exists() and "not enabled" in out.stdout, out.stdout)
out = e.run("--dry-run")
check("dry run needs no marker", out.returncode == 1 or out.returncode == 0, str(out.returncode))
check("dry run without marker did run", e.calls.exists())
e.done()

# --- log pruning ---------------------------------------------------------------------------
e = Env()
e.logs.mkdir()
for i in range(20):
    (e.logs / f"sweep-2020-01-{i + 1:02d}T000000.log").write_text("old")
(e.logs / "launchd.log").write_text("keep me")
e.run(extra=big)
logs = sorted(p.name for p in e.logs.glob("sweep-*.log"))
check("log pruning keeps the newest 14", len(logs) == 14 and logs[-1] > "sweep-2021", str(logs))
check("log pruning leaves other files alone", (e.logs / "launchd.log").exists())
check("log names the repos", "== " + str(e.dev / "alpha") in (e.logs / logs[-1]).read_text())
e.done()

if failures:
    print("dev-sweep-all FAILED:\n  " + "\n  ".join(failures))
    sys.exit(1)
print(f"dev-sweep-all: {passed} checks passed")
PY
