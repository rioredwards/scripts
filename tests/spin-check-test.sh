#!/bin/sh
set -eu
export SPIN_TEST_SCRIPT="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)/hooks/spin-check.sh"
python3 - <<'PY'
import json, os, pathlib, subprocess, tempfile, time, unittest
SCRIPT = pathlib.Path(os.environ['SPIN_TEST_SCRIPT'])
class Trial(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.tmp.name)
        lib = self.home / 'scripts/hooks/lib'
        lib.mkdir(parents=True)
        (lib/'delegate.sh').symlink_to(SCRIPT.parent/'lib/delegate.sh')
        self.env = dict(os.environ, HOME=str(self.home))
        self.env.pop('AGENT_DELEGATE', None)
        self.payload = dict(session_id='root', cwd=str(self.home), hook_event_name='PostToolUse')
    def tearDown(self): self.tmp.cleanup()
    def call(self, *args, payload=None):
        p = subprocess.run(['bash',str(SCRIPT),*map(str,args)], input=json.dumps(payload or self.payload), text=True, capture_output=True, env=self.env)
        self.assertEqual(p.returncode,0,p.stderr)
        return json.loads(p.stdout) if p.stdout.strip() else None
    def enable(self): self.call('enable', int(time.time())+3600)
    def fire(self):
        result = None
        for _ in range(20): result = self.call()
        return result
    def test_inactive_and_expired(self):
        self.assertIsNone(self.call())
        self.enable()
        state = self.home/'.local/state/spin-check-trial.json'
        data=json.loads(state.read_text()); data['expires_at']=1; state.write_text(json.dumps(data))
        self.assertIsNone(self.fire())
    def test_checkpoint_reset_cooldown_and_receipt(self):
        self.enable()
        for _ in range(19): self.assertIsNone(self.call())
        self.call(payload=dict(self.payload,hook_event_name='UserPromptSubmit'))
        for _ in range(19): self.assertIsNone(self.call())
        result=self.call()
        self.assertIn('spin-check-review.md',result['hookSpecificOutput']['additionalContext'])
        status=self.call('status'); pending=status['sessions']['root']['pending']
        self.assertIsNone(self.fire())
        self.call(payload=dict(self.payload,hook_event_name='UserPromptSubmit'))
        self.assertEqual(self.call('status')['sessions']['root']['pending'],pending)
        self.call('result','root',pending,'pass','native reviewer transcript: test')
        self.assertIsNone(self.call('status')['sessions']['root']['pending'])
    def test_delegates_do_not_start_reviews(self):
        self.enable()
        for _ in range(21): self.assertIsNone(self.call(payload=dict(self.payload,agent_id='child')))
        transcript=self.home/'child.jsonl'
        transcript.write_text(json.dumps({'type':'session_meta','payload':{'source':{'subagent':{'thread_spawn':{'parent_thread_id':'root'}}}}})+'\n')
        for _ in range(21): self.assertIsNone(self.call(payload=dict(self.payload,transcript_path=str(transcript))))
        self.assertEqual(self.call('status')['sessions'],{})
    def test_bound_and_disable(self):
        self.enable()
        for i in range(70): self.call(payload=dict(self.payload,session_id=str(i)))
        self.assertLessEqual(len(self.call('status')['sessions']),64)
        self.call('disable'); self.assertIsNone(self.fire())
unittest.main()
PY
