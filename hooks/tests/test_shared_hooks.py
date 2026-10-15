import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


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
            r = self.run_hook('loop-compact-reanchor.sh', {'session_id': sid})
            self.assertIn('Last phase skill loaded: plan', r.stdout)
        finally:
            marker.unlink(missing_ok=True)
            stamp.unlink(missing_ok=True)

    def test_codex_drift_context(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / 'rollout.jsonl'
            events = [
                {'type': 'session_meta', 'payload': {}},
                {'type': 'response_item', 'payload': {'type': 'message', 'role': 'user',
                 'content': [{'type': 'input_text', 'text': 'Only compare tools. Do not edit.'}]}},
                {'type': 'response_item', 'payload': {'type': 'message', 'role': 'assistant',
                 'content': [{'type': 'output_text', 'text': 'I will publish a new integration.'}]}},
                {'type': 'response_item', 'payload': {'type': 'function_call', 'name': 'exec_command',
                 'arguments': json.dumps({'cmd': 'git push'})}},
            ]
            p.write_text(''.join(json.dumps(e) + '\n' for e in events))
            sid = f'spin-test-{os.getpid()}'
            r = self.run_hook('spin-check.sh', {'session_id': sid, 'transcript_path': str(p)},
                              AGENT_SPIN_CHECK='on', AGENT_SPIN_CHECK_EVERY='1',
                              AGENT_SPIN_CHECK_DEBUG='1', AGENT_DELEGATE='')
            self.assertEqual(r.returncode, 0, r.stderr)
            for text in ['Only compare tools', 'publish a new integration', 'git push']:
                self.assertIn(text, r.stderr)

    def spin_env(self, td, p=None, code=200, confirm=None, confirm_code=200):
        """Stub both passes, recording each call and its input. The Decisions API (curl) answers
        each question with p[name] (default 0) and HTTP `code`; a None probability is a refusal.
        The second look (curl to /v1/responses) answers `confirm` (default deny) and `confirm_code`."""
        bindir = td / 'bin'
        bindir.mkdir(exist_ok=True)
        (td / 'p.json').write_text(json.dumps(p or {}))
        (td / 'code').write_text(str(code))
        (td / 'confirm.json').write_text(json.dumps(confirm or {'quote': '', 'evidence': '', 'verdict': 'deny'}))
        (td / 'confirm_code').write_text(str(confirm_code))
        curl = bindir / 'curl'
        curl.write_text(f'#!/bin/sh\ncase "$*" in *v1/responses*)\n'
                        f'  echo confirm >> "{td}/confirms"\n  cat > "{td}/confirm_body"\n'
                        f'  jq -c \'{{output: [{{type: "message", content: [{{type: "output_text", text: tojson}}]}}]}}\' "{td}/confirm.json"\n'
                        f'  printf "\\n%s" "$(cat "{td}/confirm_code")"; exit 0 ;;\nesac\n'
                        f'echo call >> "{td}/calls"\ncat > "{td}/prompt"\n'
                        f'jq -c --slurpfile p "{td}/p.json" \'{{answers: [.questions[] | .name as $n | $p[0][$n] as $v\n'
                        f'  | if ($p[0] | has($n)) and $v == null then {{type: "refusal", name: $n}}\n'
                        f'    else {{type: "predicate", name: $n, probability: ($v // 0)}} end]}}\' "{td}/prompt"\n'
                        f'printf "\\n%s" "$(cat "{td}/code")"\n')
        keyfor = bindir / 'keyfor'
        keyfor.write_text('#!/bin/sh\necho sk-test\n')
        for f in (curl, keyfor):
            f.chmod(0o755)
        return dict(PATH=f'{bindir}:{os.environ["PATH"]}', TMPDIR=str(td), AGENT_SPIN_CHECK='on',
                    AGENT_SPIN_CHECK_EVERY='50', AGENT_SPIN_CHECK_FIRST_WRITE='on',
                    AGENT_SPIN_CHECK_STOP='on', AGENT_SPIN_CHECK_LOG=str(td / 'fires.log'),
                    AGENT_SPIN_CHECK_MODEL='gpt-6-sol', AGENT_DELEGATE='')

    def confirms(self, td):
        p = td / 'confirms'
        return p.read_text().count('confirm') if p.exists() else 0

    def test_periodic_screens_then_confirms_with_a_quote(self):
        """L-0193: a periodic flag reaches the agent only when a second look quotes the evidence."""
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            t = self.spin_transcript(td, [
                {'type': 'user', 'message': {'content': 'Only compare the two tools. Do not edit.'}},
                {'type': 'assistant', 'message': {'content': [{'type': 'text', 'text': 'Rewriting the whole config loader now.'},
                    {'type': 'tool_use', 'name': 'Bash', 'input': {'command': 'ls'}}]}}])
            payload = {'session_id': 'per', 'transcript_path': t, 'hook_event_name': 'PostToolUse',
                       'tool_name': 'Bash', 'tool_input': {'command': 'ls'}}
            hit = {'category': 'OVERRUN', 'quote': 'Rewriting the whole config loader now.',
                   'evidence': 'Rio asked only to compare.', 'verdict': 'confirm'}
            env = {**self.spin_env(td, p={'overrun': 0.9}, confirm=hit), 'AGENT_SPIN_CHECK_EVERY': '1'}
            r = self.run_hook('spin-check.sh', payload, **env)
            self.assertEqual(r.returncode, 2, r.stderr)
            self.assertIn('SPIN-CHECK after 1 tool calls', r.stderr)
            self.assertIn('- OVERRUN: "Rewriting the whole config loader now."\n  Why: Rio asked only to compare.', r.stderr)
            self.assertEqual((self.calls(td), self.confirms(td)), (1, 1))
            body = json.loads((td / 'confirm_body').read_text())
            self.assertEqual(body['model'], 'gpt-6-sol')
            self.assertIn('Only compare the two tools', body['input'])
            self.assertIn('category', body['text']['format']['schema']['required'])
            log = (td / 'fires.log').read_text()
            self.assertIn('mode=periodic', log)
            self.assertIn('model=gpt-6-luna/decisions+gpt-6-sol', log)
            self.assertIn('confirm=overrun:confirm', log)
            self.assertRegex(log, r'\tconfirm_ms=\d+\t')
            # denied, or a quote that is not in the input: silent
            self.spin_env(td, p={'overrun': 0.9})
            r = self.run_hook('spin-check.sh', payload, **env)
            self.assertEqual((r.returncode, r.stderr), (0, ''))
            self.assertIn('verdict=ON TRACK (denied: overrun)', (td / 'fires.log').read_text())
            self.spin_env(td, p={'overrun': 0.9}, confirm={**hit, 'quote': 'something never said'})
            r = self.run_hook('spin-check.sh', payload, **env)
            self.assertEqual((r.returncode, r.stderr), (0, ''))
            self.assertIn('confirm=overrun:unquoted', (td / 'fires.log').read_text())
            # the screen passes: no second look
            self.spin_env(td, p={'overrun': 0.2}, confirm=hit)
            r = self.run_hook('spin-check.sh', payload, **env)
            self.assertEqual((r.returncode, self.calls(td), self.confirms(td)), (0, 4, 3))
            self.assertIn('confirm=-', (td / 'fires.log').read_text().splitlines()[-1])
            # the second look is down: loud once, then quiet
            self.spin_env(td, p={'overrun': 0.9}, confirm=hit, confirm_code=500)
            r = self.run_hook('spin-check.sh', payload, **env)
            self.assertEqual(r.returncode, 2, r.stderr)
            self.assertIn('SPIN-CHECK IS BROKEN, second-look call failed: overrun: HTTP 500', r.stderr)
            r = self.run_hook('spin-check.sh', payload, **env)
            self.assertEqual((r.returncode, r.stderr), (0, ''))

    def spin_transcript(self, td, events):
        t = td / 't.jsonl'
        t.write_text(''.join(json.dumps(e) + '\n' for e in events))
        return str(t)

    def calls(self, td):
        p = td / 'calls'
        return p.read_text().count('call') if p.exists() else 0

    def test_first_write_check_fires_once_per_message(self):
        """L-0006: the first file write after each message from Rio is judged, even on a short turn."""
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            env = self.spin_env(td, p={'unasked_write': 0.95}, confirm={
                'quote': 'why is the test slow?', 'evidence': 'Rio asked a question.', 'verdict': 'confirm'})
            t = self.spin_transcript(td, [{'type': 'user', 'message': {'content': 'why is the test slow?'}}])
            base = {'session_id': 'fw', 'transcript_path': t, 'hook_event_name': 'PostToolUse'}
            read = {**base, 'tool_name': 'Bash', 'tool_input': {'command': 'grep -r slow . 2>/dev/null > /dev/null'}}
            edit = {**base, 'tool_name': 'Edit', 'tool_input': {'file_path': '/x/app.py', 'old_string': 'a', 'new_string': 'b'}}
            r = self.run_hook('spin-check.sh', read, **env)
            self.assertEqual((r.returncode, self.calls(td)), (0, 0), r.stderr)
            r = self.run_hook('spin-check.sh', edit, **env)
            self.assertEqual(r.returncode, 2, r.stderr)
            self.assertIn('first write this turn', r.stderr)
            self.assertIn('- Unasked: "why is the test slow?"\n  Why: Rio asked a question.', r.stderr)
            self.assertIn('THE WRITE BEING JUDGED', json.loads((td / 'confirm_body').read_text())['instructions'])
            self.assertIn('why is the test slow?', (td / 'prompt').read_text())
            self.assertIn('/x/app.py', (td / 'prompt').read_text())
            log = (td / 'fires.log').read_text()
            self.assertIn('mode=first-write', log)
            self.assertIn('p={"unasked_write":0.95}', log)
            self.assertRegex(log, r'\tms=\d+\t')
            # second write in the same turn: silent
            r = self.run_hook('spin-check.sh', {**base, 'tool_name': 'Bash', 'tool_input': {'command': 'echo hi > out.txt'}}, **env)
            self.assertEqual((r.returncode, self.calls(td)), (0, 1), r.stderr)
            # Rio speaks again: re-armed, and a shell write counts
            self.run_hook('spin-check.sh', {**base, 'hook_event_name': 'UserPromptSubmit'}, **env)
            r = self.run_hook('spin-check.sh', {**base, 'tool_name': 'Bash', 'tool_input': {'command': "sed -i '' s/a/b/ f.txt"}}, **env)
            self.assertEqual((r.returncode, self.calls(td)), (2, 2), r.stderr)
            # Codex apply_patch counts too
            self.run_hook('spin-check.sh', {**base, 'hook_event_name': 'UserPromptSubmit'}, **env)
            r = self.run_hook('spin-check.sh', {**base, 'tool_name': 'apply_patch', 'tool_input': {'input': '*** Begin Patch'}}, **env)
            self.assertEqual((r.returncode, self.calls(td)), (2, 3), r.stderr)
            # toggled off: periodic only
            self.run_hook('spin-check.sh', {**base, 'hook_event_name': 'UserPromptSubmit'}, **env)
            r = self.run_hook('spin-check.sh', edit, **{**env, 'AGENT_SPIN_CHECK_FIRST_WRITE': 'off'})
            self.assertEqual((r.returncode, self.calls(td)), (0, 3), r.stderr)

    def test_spin_conversation_keeps_rios_lines_and_skips_hook_feedback(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            env = self.spin_env(td)
            t = self.spin_transcript(td, [
                {'type': 'user', 'message': {'content': '<!-- reply 1 -->\n> quoted line\n\nwhy not?'}},
                {'type': 'user', 'message': {'content': 'Item A - plz fix\nItem B - just asking'}},
                {'type': 'user', 'message': {'content': 'Stop hook feedback:\nReply is too long'}},
            ])
            r = self.run_hook('spin-check.sh', {'session_id': 'th', 'transcript_path': t, 'hook_event_name': 'PostToolUse',
                                                'tool_name': 'Write', 'tool_input': {'file_path': '/x/a'}},
                              **env, AGENT_SPIN_CHECK_DEBUG='1')
            self.assertIn('why not?', r.stderr)
            self.assertIn('Item A - plz fix\n     Item B', r.stderr)
            self.assertNotIn('Reply is too long', r.stderr)

    def test_stop_check_blocks_once_and_shares_its_verdict(self):
        """L-0012: the final reply is checked against this turn's tool calls; the retry is never re-checked."""
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            env = self.spin_env(td, p={'unverified_claim': 0.9, 'unasked_change': 0.1}, confirm={
                'quote': 'Tests pass.', 'evidence': 'No test ran this turn.', 'verdict': 'confirm'})
            t = self.spin_transcript(td, [
                {'type': 'user', 'message': {'content': 'old ask'}},
                {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Bash', 'input': {'command': 'pytest old'}}]}},
                {'type': 'user', 'message': {'content': 'fix the parser'}},
                {'type': 'assistant', 'message': {'content': [{'type': 'tool_use', 'name': 'Edit',
                    'input': {'file_path': '/x/parser.py', 'old_string': 'a', 'new_string': 'b'}}]}},
                {'type': 'user', 'message': {'content': [{'type': 'tool_result', 'content': 'edited ok'}]}},
            ])
            stop = {'session_id': 'st', 'transcript_path': t, 'hook_event_name': 'Stop',
                    'stop_hook_active': False, 'last_assistant_message': 'Fixed the parser. Tests pass.'}
            # the turn-end probe asks first: same verdict, no notice, one reviewer call
            p = self.run_hook('spin-check.sh', stop, **env, AGENT_SPIN_CHECK_PROBE='1')
            self.assertEqual((p.returncode, p.stderr), (2, ''))
            r = self.run_hook('spin-check.sh', stop, **env)
            self.assertEqual(r.returncode, 2, r.stderr)
            self.assertIn('- Claim with no check in view: "Tests pass."\n  Why: No test ran this turn.', r.stderr)
            self.assertNotIn('Change Rio did not ask for', r.stderr)
            self.assertIn('Revised reply', r.stderr)
            self.assertEqual((self.calls(td), self.confirms(td)), (1, 1))
            self.assertIn('confirm=unverified_claim:confirm', (td / 'fires.log').read_text())
            prompt = (td / 'prompt').read_text()
            self.assertIn('/x/parser.py', prompt)
            self.assertIn('edited ok', prompt)
            self.assertNotIn('pytest old', prompt.split('THIS TURN')[1])
            self.assertIn('mode=stop', (td / 'fires.log').read_text())
            r = self.run_hook('spin-check.sh', {**stop, 'stop_hook_active': True}, **env)
            self.assertEqual((r.returncode, r.stderr, self.calls(td)), (0, '', 1))
            r = self.run_hook('spin-check.sh', stop, **{**env, 'AGENT_SPIN_CHECK_STOP': 'off'})
            self.assertEqual((r.returncode, self.calls(td)), (0, 1))

    def test_stop_check_passes_on_track_and_never_blocks_on_failure(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            t = self.spin_transcript(td, [{'type': 'user', 'message': {'content': 'hi'}}])
            stop = {'session_id': 'ok', 'transcript_path': t, 'hook_event_name': 'Stop',
                    'stop_hook_active': False, 'last_assistant_message': 'Hello.'}
            r = self.run_hook('spin-check.sh', stop, **self.spin_env(td, p={'unverified_claim': 0.7}))
            self.assertEqual((r.returncode, r.stderr, self.confirms(td)), (0, '', 0))
            # flagged by the screen, denied by the second look: passes
            r = self.run_hook('spin-check.sh', {**stop, 'last_assistant_message': 'Hello there.'},
                              **self.spin_env(td, p={'unverified_claim': 0.9}))
            self.assertEqual((r.returncode, r.stderr, self.confirms(td)), (0, '', 1))
            self.assertIn('verdict=ON TRACK (denied: unverified_claim)', (td / 'fires.log').read_text())
            # The model declines some inputs: that reply goes unjudged, with no alarm.
            r = self.run_hook('spin-check.sh', {**stop, 'last_assistant_message': 'Hey.'},
                              **self.spin_env(td, p={'unverified_claim': 0.1, 'unasked_change': None}))
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, '', ''))
            self.assertIn('verdict=ON TRACK (refused: unasked_change)', (td / 'fires.log').read_text())
            env = self.spin_env(td, code=500)  # API down = broken reviewer
            r = self.run_hook('spin-check.sh', {**stop, 'last_assistant_message': 'Hi again.'}, **env)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn('SPIN-CHECK IS BROKEN', json.loads(r.stdout)['systemMessage'])
            self.assertIn('HTTP 500', (td / 'fires.log').read_text())

    def test_delegate_drift_check_does_not_recurse(self):
        r = self.run_hook('spin-check.sh', {'session_id': 'delegate-check'},
                          AGENT_SPIN_CHECK='on', AGENT_DELEGATE='1')
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, '', ''))

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
        codex_only = {h for h in codex if h[0].startswith('turn-end/codex-')}
        self.assertEqual(claude - claude_only, codex - codex_only)


if __name__ == '__main__':
    unittest.main()
