import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SessionFooter(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.td = Path(self.temp.name)
        gh = self.td / 'gh'
        gh.write_text('''#!/bin/sh
set -eu
case "$3" in
  https://github.com/acme/app/issues/12) file="$FOOTER_TEST_DIR/issue" ;;
  https://github.com/acme/app/pull/34) file="$FOOTER_TEST_DIR/pr" ;;
  *) exit 1 ;;
esac
case "$2" in
  view) cat "$file" ;;
  edit) cat > "$file"; printf '%s\\n' "$1 $3" >> "$FOOTER_TEST_DIR/edits" ;;
  *) exit 1 ;;
esac
''')
        gh.chmod(0o755)
        for kind in ('issue', 'pr'):
            (self.td / kind).write_text('Original body\n\nSession: prior-session\n')

    def run_hook(self, command, response, sid='new-session', key='command'):
        payload = {'session_id': sid, 'tool_input': {key: command}, 'tool_response': response}
        r = subprocess.run(['bash', str(ROOT / 'hooks/issue-session-footer.sh')],
                           input=json.dumps(payload), text=True, capture_output=True,
                           env={**os.environ, 'PATH': f'{self.td}:{os.environ["PATH"]}',
                                'FOOTER_TEST_DIR': str(self.td)}, timeout=15)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r

    def test_create_and_edit_both_kinds(self):
        for kind, segment, number in [('issue', 'issues', 12), ('pr', 'pull', 34)]:
            url = f'https://github.com/acme/app/{segment}/{number}'
            self.run_hook(f'gh {kind} create --title x --body y', url)
            self.run_hook(f'gh {kind} edit {number} --title z', {'stdout': url})
            body = (self.td / kind).read_text()
            self.assertEqual(body, 'Original body\n\nSession: prior-session\n\nSession: new-session\n')
        self.assertEqual(len((self.td / 'edits').read_text().splitlines()), 2)

    def test_codex_cmd_payload(self):
        self.run_hook('gh pr create --title x --body y',
                      {'output': 'https://github.com/acme/app/pull/34'}, key='cmd')
        self.assertIn('Session: new-session', (self.td / 'pr').read_text())

    def test_quoted_mentions_and_reads_do_nothing(self):
        for command in ['echo "gh pr create"', "rg 'gh issue edit' .", 'gh pr view 34']:
            self.run_hook(command, 'https://github.com/acme/app/pull/34')
        self.assertFalse((self.td / 'edits').exists())

    def test_url_only_in_command_does_nothing(self):
        self.run_hook('gh pr create --body https://github.com/acme/app/pull/34', 'failed')
        self.assertFalse((self.td / 'edits').exists())

    def test_only_matching_kind_is_stamped(self):
        self.run_hook('gh pr create --title x',
                      'https://github.com/acme/app/issues/12\nhttps://github.com/acme/app/pull/34')
        self.assertNotIn('new-session', (self.td / 'issue').read_text())
        self.assertIn('Session: new-session', (self.td / 'pr').read_text())

    def test_footer_is_a_complete_line(self):
        (self.td / 'pr').write_text('Session: new-session-longer\n')
        self.run_hook('gh pr edit 34 --title x', 'https://github.com/acme/app/pull/34')
        self.assertIn('\nSession: new-session\n', (self.td / 'pr').read_text())

    def test_missing_session_does_nothing(self):
        self.run_hook('gh pr create --title x', 'https://github.com/acme/app/pull/34', sid='')
        self.assertFalse((self.td / 'edits').exists())


class SharedHooks(unittest.TestCase):
    def run_hook(self, name, payload, **env):
        return subprocess.run(['bash', str(ROOT / 'hooks' / name)],
                              input=json.dumps(payload), text=True, capture_output=True,
                              env={**os.environ, **env}, timeout=15)

    def test_phase_read_and_reminder(self):
        sid = f'shared-hook-test-{os.getpid()}'
        marker = Path('/tmp') / f'claude-loop-phase-{sid}'
        stamp = Path('/tmp') / f'claude-loop-remind-{sid}'
        try:
            # A phase skill used standalone (no core:loop) must not create the marker.
            for tool_input in [{'skill': 'core:explore'},
                               {'command': 'cat ~/dev/agent-skills/plugins/core/skills/explore/SKILL.md'}]:
                self.run_hook('loop-phase-tracker.sh', {'session_id': sid, 'tool_input': tool_input})
                self.assertFalse(marker.exists())
            self.run_hook('loop-phase-tracker.sh', {'session_id': sid, 'tool_input': {'skill': 'core:loop'}})
            self.assertEqual(marker.read_text(), 'loop')
            for tool_input in [{'skill': 'core:plan'},
                               {'command': 'cat ~/dev/agent-skills/plugins/core/skills/plan/SKILL.md'}]:
                self.run_hook('loop-phase-tracker.sh', {'session_id': sid, 'tool_input': tool_input})
                self.assertEqual(marker.read_text(), 'plan')
            r = self.run_hook('loop-reminder.sh', {'session_id': sid}, LOOP_REMINDER_INTERVAL_SECS='0')
            self.assertIn('last phase skill loaded: plan', json.loads(r.stdout)['hookSpecificOutput']['additionalContext'])
            r = self.run_hook('compact-reanchor.sh', {'session_id': sid})
            self.assertIn('Last phase skill loaded: plan', r.stdout)
            self.assertIn('checkpoint with Rio', r.stdout)
        finally:
            marker.unlink(missing_ok=True)
            stamp.unlink(missing_ok=True)

    def test_compaction_asks_for_a_scope_checkpoint(self):
        """Compaction only happens deep into long work, so it is the trigger for Rio's
        scope check-in. Delegates report to an agent, not Rio, so they stay quiet."""
        r = self.run_hook('compact-reanchor.sh', {'session_id': f'no-loop-{os.getpid()}'})
        self.assertIn('checkpoint with Rio', r.stdout)
        self.assertIn('attention: away', r.stdout)
        self.assertNotIn('core:loop', r.stdout)
        r = self.run_hook('compact-reanchor.sh', {'session_id': 'x', 'agent_id': 'sub'})
        self.assertEqual(r.stdout, '')

    def test_task_start_nudge_reaches_main_agent_only(self):
        """Each prompt from Rio may start a task: the main agent is told to check past
        sessions first and offer core:loop. Delegates get their task from an agent."""
        r = self.run_hook('task-start.sh', {'session_id': 's', 'prompt': 'fix the header'})
        c = json.loads(r.stdout)['hookSpecificOutput']['additionalContext']
        self.assertIn('load the `utils:sesh` skill', c)
        self.assertIn('`--topic <task> --light` mode', c)
        self.assertIn('skill name, not a shell command', c)
        self.assertIn('`session-handoff`', c)
        self.assertIn('/core:loop', c)
        r = self.run_hook('task-start.sh', {'session_id': 's', 'prompt': 'x', 'agent_id': 'sub'})
        self.assertEqual(r.stdout, '')
        r = self.run_hook('task-start.sh', {'session_id': 's', 'prompt': '<task-notification>done</task-notification>'})
        self.assertEqual(r.stdout, '')

    def test_daily_call_cap_stops_calls_loudly(self):
        """A runaway replay cannot spend the month: past the per-day cap the lib refuses and
        says why, and the cap is raised on purpose with one env var."""
        with tempfile.TemporaryDirectory() as td:
            lib = ROOT / 'hooks/lib/call-budget-lib.sh'
            def take(cap):
                return subprocess.run(['sh', '-c', f'. "{lib}"; call_budget_take decisions'], text=True,
                                      capture_output=True, env={**os.environ, 'OPENAI_CALL_COUNT_DIR': td,
                                                                'OPENAI_DAILY_CALL_CAP': cap})
            self.assertEqual(take('1').returncode, 0)
            r = take('1')
            self.assertEqual(r.returncode, 1)
            self.assertIn('decisions daily cap: 2 calls today, cap 1', r.stdout)
            self.assertIn('OPENAI_DAILY_CALL_CAP', r.stdout)
            self.assertEqual(take('100').returncode, 0)

    def test_reply_cap_tightens_for_short_asks(self):
        words = lambda n: ' '.join(['word'] * n)
        claude = lambda prompt: [{'type': 'user', 'message': {'content': prompt}},
                                 {'type': 'user', 'message': {'content': [{'type': 'tool_result', 'content': 'x'}]}}]
        codex_user = lambda text: {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user',
                                   'content': [{'type': 'input_text', 'text': text}]}}
        codex = lambda prompt: [codex_user('# AGENTS.md instructions for /x\n\nrules'), codex_user(prompt),
                                codex_user('<environment_context/>')]
        cases = [(claude('what is up'), 100, 2), (claude(words(9)), 100, 0),
                 (codex('how did yesterday go'), 100, 2), (codex(words(9)), 100, 0),
                 (claude('<command-message>pm:talk</command-message>'), 100, 0),
                 (claude('short ask'), 60, 0)]
        for events, reply_words, code in cases:
            with tempfile.TemporaryDirectory() as td:
                t = Path(td) / 't.jsonl'
                t.write_text(''.join(json.dumps(e) + '\n' for e in events))
                r = self.run_hook('reply-cap.sh', {'transcript_path': str(t), 'stop_hook_active': False,
                                                   'last_assistant_message': words(reply_words)},
                                  AGENT_DELEGATE='')
                self.assertEqual(r.returncode, code, (events, r.stderr))

    def test_claude_and_codex_register_same_hooks(self):
        """A guard hook added for one agent must reach the other (ledger: Codex runs the same guard hooks)."""
        def hooks(path):
            text = (Path.home() / path).read_text()
            return set(re.findall(r'scripts/hooks/([\w./-]+?)\\?"(?: (tool|response)\b)?', text))
        claude, codex = hooks('.dotfiles/.claude/settings.json'), hooks('.dotfiles/.codex/hooks.json')
        claude_only = {h for h in claude if h[0].startswith('turn-end/claude-')}
        # Codex has no spawn-time block, so it gets a SubagentStart note instead (L-0212);
        # Claude's Skill-line rule lives in rules.json.
        codex_only = {h for h in codex if h[0].startswith('turn-end/codex-') or h[0] == 'subagent-skill-note.sh'}
        self.assertEqual(claude - claude_only, codex - codex_only)


if __name__ == '__main__':
    unittest.main()
