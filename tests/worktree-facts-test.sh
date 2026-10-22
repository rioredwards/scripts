#!/bin/bash
# Retirement inventory must expose preservation risks using disposable Git repos.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root/dev-scan" <<'PY'
import json, pathlib, subprocess, sys, tempfile
scan = sys.argv[1]
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp).resolve()
    repo, remote, work = (root / p for p in ('repo', 'remote', 'work tree'))
    def git(path, *args):
        return subprocess.check_output(['git', '-C', str(path), *args], stderr=subprocess.DEVNULL, text=True).strip()
    subprocess.run(['git', 'init', '--bare', '-q', str(remote)], check=True)
    subprocess.run(['git', 'init', '-q', '-b', 'main', str(repo)], check=True)
    git(repo, 'config', 'user.email', 'test@example.com')
    git(repo, 'config', 'user.name', 'Test')
    (repo / '.gitignore').write_text('.env\nnode_modules/\n')
    (repo / 'tracked').write_text('initial\n')
    git(repo, 'add', '.')
    git(repo, 'commit', '-qm', 'initial')
    git(repo, 'remote', 'add', 'origin', str(remote))
    git(repo, 'push', '-qu', 'origin', 'main')
    git(repo, 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
    git(repo, 'worktree', 'add', '-qb', 'done', str(work))
    def row():
        rows = json.loads(subprocess.check_output([sys.executable, scan, 'worktrees', str(repo)], text=True))
        assert rows[0]['isMain'] and not rows[1]['isMain']
        return rows[1]
    clean = row()
    assert clean['changed'] == clean['untracked'] == clean['unpushed'] == clean['ahead'] == 0
    assert clean['ignored'] == [] and not clean['locked']
    assert clean['commonDir'] == str(repo / '.git') and len(clean['head']) == 40
    (work / '.env').write_text('unique local configuration')
    (work / 'node_modules').mkdir()
    (work / 'node_modules' / 'generated').write_text('reinstallable')
    (work / 'scratch').mkdir()
    (work / 'scratch' / 'one').write_text('unfinished')
    (work / 'scratch' / 'two\nlines').write_text('unfinished')
    git(repo, 'worktree', 'lock', '--reason', 'active task', str(work))
    risky = row()
    assert set(risky['ignored']) == {'.env', 'node_modules/'}
    assert risky['untracked'] == 2 and risky['locked']
    git(work, 'mv', 'tracked', 'renamed')
    assert row()['changed'] == 1, 'rename source must not count as a second change'
    git(work, 'commit', '-qm', 'unfinished commit')
    assert row()['unpushed'] == row()['ahead'] == 1
    git(work, 'push', '-qu', 'origin', 'done')
    assert row()['unpushed'] == 0 and row()['ahead'] == 1, 'pushed is not merged'
    git(repo, 'symbolic-ref', '--delete', 'refs/remotes/origin/HEAD')
    unknown = row()
    assert unknown['ahead'] is None and unknown['unpushed'] is None
    assert unknown['ignored'] and unknown['locked'], 'missing base must retain preservation facts'
print('worktree facts: clean, ignored, locked, untracked, rename, unpushed, unmerged, unknown base passed')
PY
