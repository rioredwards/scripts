#!/bin/bash
# dev-sweep decisions and the apply path, on throwaway git repos with a local bare repo as origin.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root/dev-sweep" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile, time

sweep = sys.argv[1]
OLD = "2020-01-01T00:00:00"
passed, failures = 0, []


class Env:
    """One disposable repo (primary), a bare origin, and an isolated lease dir and pm2 home."""

    def __init__(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp()).resolve()
        self.repo, self.remote = self.tmp / "repo", self.tmp / "remote.git"
        self.env = {**os.environ, "DEV_LEASE_DIR": str(self.tmp / "leases"), "PM2_HOME": str(self.tmp / "pm2"),
                    "GIT_AUTHOR_DATE": OLD, "GIT_COMMITTER_DATE": OLD, "HOME": str(self.tmp / "home")}
        subprocess.run(["git", "init", "--bare", "-q", str(self.remote)], check=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], check=True)
        self.git(self.repo, "config", "user.email", "t@example.com")
        self.git(self.repo, "config", "user.name", "T")
        (self.repo / "f").write_text("one\n")
        self.git(self.repo, "add", ".")
        self.git(self.repo, "commit", "-qm", "init")
        self.git(self.repo, "remote", "add", "origin", str(self.remote))
        self.git(self.repo, "push", "-qu", "origin", "main")
        self.git(self.repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")

    def git(self, path, *args, check=True):
        out = subprocess.run(["git", "-C", str(path), *args], env=self.env, capture_output=True, text=True)
        if check and out.returncode:
            raise AssertionError(f"git {args} failed: {out.stderr}")
        return out.stdout.strip()

    def tree(self, name, branch="feat", pushed=True, commit=True):
        path = self.tmp / name
        self.git(self.repo, "worktree", "add", "-qb", branch, str(path))
        if commit:
            (path / f"{name}.txt").write_text(name)
            self.git(path, "add", ".")
            self.git(path, "commit", "-qm", name)
        if pushed:
            self.git(path, "push", "-qu", "origin", branch)
        return path

    def age(self, path):
        gitdir = pathlib.Path(self.git(path, "rev-parse", "--absolute-git-dir"))
        old = time.time() - 3 * 86400
        for rel in ("index", "logs/HEAD"):
            if (gitdir / rel).exists():
                os.utime(gitdir / rel, (old, old))

    def run(self, *args, env=None):
        return subprocess.run([sys.executable, sweep, str(self.repo), *args], capture_output=True, text=True,
                              env={**self.env, **(env or {})})

    def verdicts(self, *args, env=None):
        out = self.run("--json", *args, env=env)
        assert out.returncode == 0, out.stderr
        data = json.loads(out.stdout)
        return {pathlib.Path(w["dir"]).name: w for w in data["worktrees"]}, data

    def state(self):
        return (self.git(self.repo, "worktree", "list", "--porcelain"), self.git(self.repo, "for-each-ref"),
                subprocess.check_output(["git", "-C", str(self.remote), "for-each-ref"], text=True))

    def done(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


def check(name, condition, detail=""):
    global passed
    if condition:
        passed += 1
    else:
        failures.append(f"{name}: {detail}")


def expect_keep(name, setup, needle, age=True, env_for=None):
    e = Env()
    try:
        path = setup(e)
        if age:
            e.age(path)
        v, _ = e.verdicts(env=env_for(e) if env_for else None)
        row = v[path.name]
        check(name, row["verdict"] == "keep" and any(needle in r for r in row["reasons"]), json.dumps(row))
    finally:
        e.done()


# --- decisions ---------------------------------------------------------------

e = Env()
t = e.tree("done")
e.age(t)
v, data = e.verdicts()
check("remove: clean, pushed, idle", v["done"]["verdict"] == "remove", json.dumps(v["done"]))
check("primary kept", v["repo"]["verdict"] == "keep" and v["repo"]["reasons"] == ["primary checkout"], json.dumps(v["repo"]))
check("totals", data["total"] == 2 and data["wouldRemove"] == 1 and data["wouldKeep"] == 1, json.dumps(data)[-80:])
human = e.run().stdout.splitlines()
check("human lines", human[0].startswith("keep: primary checkout\t") and human[1].startswith("remove\t")
      and human[-1] == "total 2, would remove 1, would keep 1", str(human))
e.done()

e = Env()
t = e.tree("ahead", pushed=False)
e.age(t)
v, _ = e.verdicts()
check("push-then-remove: named branch, not on remote", v["ahead"]["verdict"] == "push-then-remove", json.dumps(v["ahead"]))
e.done()

expect_keep("locked kept", lambda e: (lambda p: (e.git(e.repo, "worktree", "lock", str(p)), p)[1])(e.tree("lk")), "locked")


def dirty(e):
    p = e.tree("dirty")
    (p / "f").write_text("changed\n")
    return p


expect_keep("modified file kept", dirty, "1 modified")


def untracked(e):
    p = e.tree("untracked")
    (p / "new.txt").write_text("x")
    return p


expect_keep("untracked file kept", untracked, "new.txt")


def rebase(e):
    p = e.tree("rebasing")
    (pathlib.Path(e.git(p, "rev-parse", "--absolute-git-dir")) / "rebase-merge").mkdir()
    return p


expect_keep("rebase in progress kept", rebase, "rebase-merge")


def merging(e):
    p = e.tree("merging")
    (pathlib.Path(e.git(p, "rev-parse", "--absolute-git-dir")) / "MERGE_HEAD").write_text(e.git(p, "rev-parse", "HEAD") + "\n")
    return p


expect_keep("merge in progress kept", merging, "MERGE_HEAD")


def stashed(e):
    p = e.tree("stashed")
    (p / "f").write_text("work in progress\n")
    e.git(p, "stash")
    return p


expect_keep("stash from branch kept", stashed, "stash entry from feat")


def detached(e):
    p = e.tree("det", pushed=False)
    e.git(p, "checkout", "-q", "--detach")
    return p


expect_keep("detached HEAD on no remote branch kept", detached, "detached HEAD")


def rejected(e):
    p = e.tree("rej", pushed=False)
    other = e.tmp / "other"
    subprocess.run(["git", "clone", "-q", str(e.remote), str(other)], check=True)
    e.git(other, "config", "user.email", "t@example.com")
    e.git(other, "config", "user.name", "T")
    e.git(other, "checkout", "-qb", "feat")
    (other / "g").write_text("diverged")
    e.git(other, "add", ".")
    e.git(other, "commit", "-qm", "diverged")
    e.git(other, "push", "-q", "origin", "feat")
    return p


expect_keep("push that would be rejected kept", rejected, "push would be rejected")


def no_remote(e):
    p = e.tree("lonely", pushed=False)
    e.git(e.repo, "remote", "remove", "origin")
    return p


expect_keep("no remote to push to kept", no_remote, "no remote origin")
expect_keep("recently active kept", lambda e: e.tree("fresh"), "idle only", age=False)


def running(e):
    p = e.tree("busy")
    e.proc = subprocess.Popen(["sleep", "60"], cwd=p)
    time.sleep(0.5)
    return p


e = Env()
p = running(e)
e.age(p)
v, _ = e.verdicts()
e.proc.kill()
e.proc.wait()
check("process with cwd inside kept", v["busy"]["verdict"] == "keep" and any("running process" in r for r in v["busy"]["reasons"]), json.dumps(v["busy"]))
v, _ = e.verdicts()
check("same tree removable once the process is gone", v["busy"]["verdict"] == "remove", json.dumps(v["busy"]))
e.done()


def with_pm2(e):
    p = e.tree("served")
    (e.tmp / "pm2").mkdir()
    (e.tmp / "pm2" / "pm2.pid").write_text(str(os.getpid()))
    (e.tmp / "bin").mkdir()
    fake = e.tmp / "bin" / "pm2"
    fake.write_text(f"#!/bin/sh\necho '[{{\"name\":\"web\",\"pm2_env\":{{\"pm_cwd\":\"{p}\"}}}}]'\n")
    fake.chmod(0o755)
    return p


expect_keep("pm2 process kept", with_pm2, "pm2 process: web",
            env_for=lambda e: {"PATH": f"{e.tmp / 'bin'}:{os.environ['PATH']}"})


def lease(expires):
    def setup(e):
        p = e.tree("leased")
        (e.tmp / "leases").mkdir()
        (e.tmp / "leases" / ("a" * 32 + ".json")).write_text(json.dumps({"name": "dev-x", "cwd": str(p), "expires": expires}))
        return p
    return setup


expect_keep("live dev lease kept", lease(time.time() + 3600), "live dev lease")
e = Env()
p = lease(time.time() - 3600)(e)
e.age(p)
v, _ = e.verdicts()
check("expired lease does not block", v["leased"]["verdict"] == "remove", json.dumps(v["leased"]))
e.done()


SECRET = "TOPSECRET_VALUE_12345"
PATTERNS = ".env*\nnode_modules/\n.fallow/\nnext-env.d.ts\nnotes.txt\n.claude/worktrees/\nshots/\n"


def ignoring(e, name, branch="feat", pushed=True):
    """A tree whose repo ignores the usual generated paths, caches and env files."""
    p = e.tree(name, branch, pushed=pushed)
    (e.repo / ".gitignore").write_text(PATTERNS)
    e.git(e.repo, "add", ".")
    e.git(e.repo, "commit", "-q", "--allow-empty", "-m", "ignore")
    e.git(e.repo, "push", "-q", "origin", "main")
    e.git(p, "merge", "-q", "main")
    if pushed:
        e.git(p, "push", "-q", "origin", branch)
    return p


def with_files(name, files):
    def setup(e):
        p = ignoring(e, name)
        for rel, text in files.items():
            (p / rel).parent.mkdir(parents=True, exist_ok=True)
            (p / rel).write_text(text)
        return p
    return setup


expect_keep("ignored file off the allowlist kept", with_files("odd", {"notes.txt": "mine"}), "not on the allowlist: notes.txt")
expect_keep("ignored screenshot kept", with_files("shot", {"shots/a.png": "png"}), "not on the allowlist: shots/a.png")
expect_keep("non-empty nested .claude/worktrees kept", with_files("nest", {".claude/worktrees/x": "y"}), "not on the allowlist: .claude/worktrees/x")


def removable(name, files, empty_dirs=()):
    e = Env()
    p = ignoring(e, name)
    for rel, text in files.items():
        (p / rel).parent.mkdir(parents=True, exist_ok=True)
        (p / rel).write_text(text)
    for rel in empty_dirs:
        (p / rel).mkdir(parents=True)
    e.age(p)
    return e, p


for label, files, empties in (
    ("node_modules, .fallow, next-env.d.ts allowed", {"node_modules/x": "g", ".fallow/cache": "g", "apps/next-env.d.ts": "g"}, ()),
    ("empty nested .claude/worktrees allowed", {}, (".claude/worktrees",)),
):
    e, p = removable("gen", files, empties)
    v, _ = e.verdicts()
    check(label, v["gen"]["verdict"] == "remove" and v["gen"]["envFiles"] == 0, json.dumps(v["gen"]))
    e.done()

e, p = removable("envy", {})
os.symlink("/dev/null", p / ".env")
v, _ = e.verdicts()
check("symlinked .env allowed and not counted for backup", v["envy"]["verdict"] == "remove" and v["envy"]["envFiles"] == 0, json.dumps(v["envy"]))
e.done()

# --- env files are preserved, not a blocker ---------------------------------------


def backup_dir(e):
    return e.tmp / "home" / "Backups" / "repo" / "worktree-env"


e, p = removable("envy", {".env": SECRET + "=1", "apps/web/.env.local": "other=2"})
home_before = list((e.tmp / "home").rglob("*")) if (e.tmp / "home").exists() else []
out = e.run()
check("dry run: env files do not block and are counted", "remove\t" in out.stdout and "2 env files to preserve" in out.stdout, out.stdout)
check("dry run writes no backup", not (e.tmp / "home" / "Backups").exists())
check("dry run never prints env contents", SECRET not in out.stdout + out.stderr)
out = e.run("--apply")
check("apply never prints env contents", SECRET not in out.stdout + out.stderr)
check("apply removed the tree with env files", not p.exists() and out.returncode == 0, out.stdout + out.stderr)
b = backup_dir(e)
files = sorted(b.glob("*.env"))
digest = __import__("hashlib").sha256((SECRET + "=1").encode()).hexdigest()[:12]
check("backup stored by hash with the same content", (b / f"{digest}.env").read_text() == SECRET + "=1" and len(files) == 2, str(files))
check("backup modes are owner only", oct(b.stat().st_mode & 0o777) == "0o700" and oct((b / f"{digest}.env").stat().st_mode & 0o777) == "0o600")
rows = [l.split("\t") for l in (b / "index.tsv").read_text().splitlines()]
check("index line has date, tree, branch, file, hash",
      len(rows) == 2 and {r[3] for r in rows} == {".env", "apps/web/.env.local"} and rows[0][1] == str(p) and rows[0][2] == "feat"
      and any(r[4].startswith(digest) for r in rows) and rows[0][0][:2] == "20", str(rows))
check("index and backups never hold anything but env content", SECRET not in (b / "index.tsv").read_text())
e.done()

# Same env content in two trees: one stored file, two index lines. Index is capped at 500 lines.
e = Env()
a = ignoring(e, "one", "f1")
b2 = ignoring(e, "two", "f2")
for p in (a, b2):
    (p / ".env").write_text("same=1")
    e.age(p)
bd = backup_dir(e)
bd.mkdir(parents=True)
(bd / "index.tsv").write_text("".join(f"old{i}\n" for i in range(600)))
out = e.run("--apply")
lines = (bd / "index.tsv").read_text().splitlines()
check("same content stored once, index lines per tree", len(list(bd.glob("*.env"))) == 1 and sum("\t.env\t" in l for l in lines) == 2, str(len(lines)))
check("index trimmed to its last 500 lines", len(lines) == 500 and lines[0] == "old102", f"{len(lines)} {lines[0]}")
check("both trees removed", not a.exists() and not b2.exists(), out.stdout)
e.done()

# A failed backup keeps the tree.
e, p = removable("nobackup", {".env": "k=1"})
(e.tmp / "home").mkdir()
(e.tmp / "home" / "Backups").write_text("a file where the folder should be")
out = e.run("--apply")
check("failed backup keeps the tree", p.exists() and "keep: " in out.stdout and "backup" in out.stdout, out.stdout)
e.done()

# Corrupt stored copy under the same hash is caught by the read-back.
e, p = removable("corrupt", {".env": "k=1"})
bd = backup_dir(e)
bd.mkdir(parents=True)
(bd / (__import__("hashlib").sha256(b"k=1").hexdigest()[:12] + ".env")).write_text("tampered")
out = e.run("--apply")
check("read-back mismatch keeps the tree", p.exists() and "backup" in out.stdout, out.stdout)
e.done()


def prunable(e):
    p = e.tree("vanished")
    shutil.rmtree(p)
    return p


e = Env()
p = prunable(e)
v, _ = e.verdicts()
check("prunable kept", v["vanished"]["verdict"] == "keep" and "prunable" in v["vanished"]["reasons"][0], json.dumps(v.get("vanished")))
e.done()

# --- dry run changes nothing ---------------------------------------------------

e = Env()
a, b = e.tree("a", "fa"), e.tree("b", "fb", pushed=False)
for p in (a, b):
    e.age(p)
(b / "dirty").write_text("x")
before = e.state()
snap = {str(p): sorted(q.name for q in p.iterdir()) for p in (a, b)}
out = e.run()
check("dry run exits 0", out.returncode == 0, out.stderr)
check("dry run changed nothing", e.state() == before and snap == {str(p): sorted(q.name for q in p.iterdir()) for p in (a, b)} and a.exists())
e.done()

# --- apply ---------------------------------------------------------------------

e = Env()
done_, ahead, locked, dirty_ = e.tree("done", "f1"), e.tree("ahead", "f2", pushed=False), e.tree("locked", "f3"), e.tree("dirty", "f4")
e.git(e.repo, "worktree", "lock", str(locked))
(dirty_ / "x").write_text("unsaved")
for p in (done_, ahead, locked, dirty_):
    e.age(p)
out = e.run("--apply")
check("apply exits 0", out.returncode == 0, out.stderr)
check("apply removed finished tree", not done_.exists())
check("apply removed pushed-then-removed tree", not ahead.exists())
check("apply pushed the branch without losing it", "refs/heads/f2" in subprocess.check_output(["git", "-C", str(e.remote), "for-each-ref"], text=True))
check("apply kept branches", e.git(e.repo, "branch", "--list", "f1", "f2") != "")
check("apply left locked and dirty trees alone", locked.exists() and (dirty_ / "x").read_text() == "unsaved")
check("apply totals", out.stdout.strip().splitlines()[-1] == "total 5, removed 2, kept 3", out.stdout)
check("primary survives apply", (e.repo / "f").exists())
e.done()

e = Env()
t = e.tree("rejected", pushed=False)
e.age(t)
other = e.tmp / "other"
subprocess.run(["git", "clone", "-q", str(e.remote), str(other)], check=True)
e.git(other, "config", "user.email", "t@example.com")
e.git(other, "config", "user.name", "T")
e.git(other, "checkout", "-qb", "feat")
(other / "g").write_text("diverged")
e.git(other, "add", ".")
e.git(other, "commit", "-qm", "diverged")
e.git(other, "push", "-q", "origin", "feat")
out = e.run("--apply")
check("apply keeps a tree whose push is rejected", t.exists() and "keep: push would be rejected" in out.stdout, out.stdout)
e.done()

# --- loud failures ---------------------------------------------------------------

e = Env()
t = e.tree("linked")
out = subprocess.run([sys.executable, sweep, str(t)], capture_output=True, text=True, env=e.env)
check("linked worktree rejected as input", out.returncode == 2 and "not a primary checkout" in out.stderr, out.stderr)
e.git(e.repo, "remote", "set-url", "origin", str(e.tmp / "nowhere.git"))
out = e.run()
check("fetch failure is fatal", out.returncode == 2 and "fetch failed" in out.stderr, out.stderr)
check("no args prints help", subprocess.run([sys.executable, sweep], capture_output=True, text=True).returncode == 0)
check("two args is fatal", subprocess.run([sys.executable, sweep, "a", "b"], capture_output=True, text=True).returncode == 2)
e.done()

if failures:
    print("dev-sweep FAILED:\n  " + "\n  ".join(failures))
    sys.exit(1)
print(f"dev-sweep: {passed} checks passed")
PY
