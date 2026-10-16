#!/bin/sh
# Regression coverage for command detection, missing completion and cue expiry.
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

root = Path.cwd()
with tempfile.TemporaryDirectory() as directory:
    home = Path(directory)
    scripts = home / 'scripts'
    scripts.mkdir()
    cue = scripts / 'automation-cue.sh'
    cue.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HOME/calls"\n')
    cue.chmod(0o755)
    env = {**os.environ, 'HOME': str(home), 'AGENT_AUTOMATION_CUE': 'on',
           'AGENT_AUTOMATION_CUE_STALE': '5'}
    calls = home / 'calls'
    markers = home / '.cache/automation-guard/inflight'

    def hook(event, command=''):
        subprocess.run(['bash', str(root / 'hooks/automation-guard.sh')],
                       input=json.dumps({'hook_event_name': event,
                                         'tool_input': {'command': command}}),
                       text=True, env=env, check=True)

    for command in [
        "gh issue list --state open --search 'AlcoDens' && rg -n 'onPaste' apps/web",
        "echo open -a Safari", "git commit -m 'open -a Safari'",
        "rg screencapture file", "echo osascript System Events",
        "gh issue list --state open && echo '/Applications/Safari.app'",
    ]:
        hook('PreToolUse', command)
        assert not list(markers.iterdir()), command
        assert not calls.exists(), command

    for command in [
        'open -a Safari', 'env FOO=1 /usr/bin/open -a Safari',
        'open file.txt && rg -n pattern file',
        "echo 'open -a Safari'; open file.txt",
        'echo hi && open "hammerspoon://test"', 'open "/Applications/Safari.app"',
        'screencapture /tmp/shot.png', 'shortcuts run Test',
        'if screencapture /tmp/shot.png; then echo ok; fi',
        'while cliclick p; do sleep 1; done', 'sudo -u rio cliclick p',
        'sudo -n -u rio /usr/bin/open -a Safari',
        'osascript -e \'tell application "System Events" to keystroke "a"\'',
    ]:
        hook('PreToolUse', command)
        assert len(list(markers.iterdir())) == 1, command
        assert calls.read_text().splitlines()[-1] == 'start 300'
        hook('PostToolUse', command)
        assert not list(markers.iterdir()), command
        assert calls.read_text().splitlines()[-1] == 'stop'

    # A denied command has no PostToolUse. Any later event sweeps and hides it.
    hook('PreToolUse', 'open -a Safari')
    marker = next(markers.iterdir())
    os.utime(marker, (time.time() - 420, time.time() - 420))
    hook('PreToolUse', 'git status')
    assert not list(markers.iterdir())
    assert calls.read_text().splitlines()[-1] == 'stop'

    # An expired marker must not hide another command's active cue.
    hook('PreToolUse', 'open -a Safari')
    old = next(markers.iterdir())
    hook('PreToolUse', 'screencapture /tmp/shot.png')
    os.utime(old, (time.time() - 420, time.time() - 420))
    hook('PreToolUse', 'git status')
    assert len(list(markers.iterdir())) == 1
    assert calls.read_text().splitlines()[-1] == 'start 300'
    hook('Stop')
    assert not list(markers.iterdir())

    # Capture the actual Lua sent by the cue wrapper and exercise its timer.
    bin_dir = home / 'bin'
    bin_dir.mkdir()
    (bin_dir / 'pgrep').write_text('#!/bin/sh\nexit 0\n')
    (bin_dir / 'osascript').write_text('#!/bin/sh\nprintf "%s" "$2" > "$HOME/apple"\n')
    for file in bin_dir.iterdir():
        file.chmod(0o755)
    env['PATH'] = str(bin_dir) + ':' + os.environ['PATH']

    def lua_for(*args):
        subprocess.run(['bash', str(root / 'automation-cue.sh'), *args], env=env, check=True)
        apple = (home / 'apple').read_text()
        return apple.split('execute lua code "', 1)[1][:-1]

    start = lua_for('start', '2')
    stop = lua_for('stop')
    lua = '''
local visible = false
function G_automationCueShow() visible = true end
function G_automationCueHide() visible = false end
hs = {timer = {doAfter = function(seconds, callback)
  assert(seconds == 2)
  return {callback = callback, stop = function(self) self.stopped = true end}
end}}
'''
    lua += start + '\nassert(visible)\nlocal first = G_automationCueExpiry\n'
    lua += start + '\nassert(first.stopped)\nG_automationCueExpiry.callback()\nassert(not visible)\n'
    lua += start + '\nlocal last = G_automationCueExpiry\n' + stop
    lua += '\nassert(last.stopped and G_automationCueExpiry == nil and not visible)\n'
    subprocess.run(['luajit', '-e', lua], check=True)
print('automation guard regressions passed')
PY
