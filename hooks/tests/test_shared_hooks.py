import json
import os
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

    def test_delegate_drift_check_does_not_recurse(self):
        r = self.run_hook('spin-check.sh', {'session_id': 'delegate-check'},
                          AGENT_SPIN_CHECK='on', AGENT_DELEGATE='1')
        self.assertEqual((r.returncode, r.stdout, r.stderr), (0, '', ''))


if __name__ == '__main__':
    unittest.main()
