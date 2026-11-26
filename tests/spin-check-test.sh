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
    def fire_with(self, extra):
        result = None
        for _ in range(20): result = self.call(payload=dict(self.payload,**extra))
        return result
    def test_automated_turns_are_skipped_but_rio_turns_count(self):
        self.enable()
        def lines(*rows): return ''.join(json.dumps(r)+'\n' for r in rows)
        def claude(text): return {'type':'user','message':{'role':'user','content':text}}
        def codex(trigger): return {'type':'event_msg','payload':{'type':'task_started','turn_attribution':{'turn_trigger':trigger}}}
        tool = {'type':'user','message':{'role':'user','content':[{'type':'tool_result','content':'x'}]}}
        def transcript(name, *rows):
            t = self.home/name; t.write_text(lines(*rows)); return str(t)
        mem = self.home/'.codex/memories'; mem.mkdir(parents=True)
        skipped = {
            'claude scheduled': dict(transcript_path=transcript('a.jsonl', claude('<scheduled-task name="x">\nrun'), tool, claude('This session is being continued from a previous conversation'), tool)),
            'claude scheduled prompt': dict(prompt='<scheduled-task name="x">'),
            'codex automation': dict(transcript_path=transcript('b.jsonl', codex('composer'), codex('automation_cron_scheduled'))),
            'codex heartbeat': dict(transcript_path=transcript('c.jsonl', codex('automation_heartbeat_scheduled'))),
            'codex automation prompt': dict(prompt='Automation: nightly\nAutomation ID: x'),
            'memory job': dict(cwd=str(mem)),
        }
        for name, extra in skipped.items():
            for _ in range(21): self.assertIsNone(self.call(payload=dict(self.payload,**extra)), name)
        self.assertEqual(self.call('status')['sessions'],{})
        counted = dict(transcript_path=transcript('d.jsonl', claude('<scheduled-task name="x">'), claude('fix the bug please'), tool))
        counted2 = dict(transcript_path=transcript('e.jsonl', codex('automation_heartbeat_scheduled'), codex('composer')))
        for sid, extra in (('r1',counted), ('r2',counted2)):
            self.assertIsNotNone(self.fire_with(dict(extra,session_id=sid)))
    def test_bound_and_disable(self):
        self.enable()
        for i in range(70): self.call(payload=dict(self.payload,session_id=str(i)))
        self.assertLessEqual(len(self.call('status')['sessions']),64)
        self.call('disable'); self.assertIsNone(self.fire())
unittest.main()
PY
