#!/bin/bash
# A three-day, advisory trial. Context gathering and review stay with native agents.
set -eu
umask 077
INPUT='{}'
if [ "$#" -eq 0 ]; then
  INPUT=$(cat)
  . "$HOME/scripts/hooks/lib/delegate.sh"
  hook_is_delegate "$INPUT" && exit 0
fi
python3 - "$@" 3<<<"$INPUT" <<'PY'
import fcntl, json, os, pathlib, sys, time, uuid
root = pathlib.Path.home()/'.local/state'
path = root/'spin-check-trial.json'
args = sys.argv[1:]
now = int(time.time())
if not args and not path.exists():
    sys.exit(0)
root.mkdir(parents=True, exist_ok=True)
with (root/'spin-check-trial.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        state = json.loads(path.read_text()) if path.exists() else dict(enabled=False, expires_at=0, sessions={}, records=[])
        if not isinstance(state.get('sessions'),dict) or not isinstance(state.get('records'),list):
            raise ValueError('invalid state structure')
        command = args[0] if args else 'hook'
        output = None
        def record(kind, sid, fire=None, note=''):
            state['records'].append(dict(at=now, kind=kind, session=sid, fire=fire, note=note[:1000]))
            state['records'] = state['records'][-120:]
        if command == 'enable':
            expiry = int(args[1])
            if not now < expiry <= now + 3*86400:
                raise ValueError('expiry must be within the next three days')
            state.update(enabled=True, expires_at=expiry)
        elif command == 'disable':
            state['enabled'] = False
        elif command == 'status':
            output = dict(state, active=bool(state['enabled'] and now < state['expires_at']))
        elif command == 'result':
            sid, fire, outcome, note = args[1:]
            if outcome not in ('pass','corrected','disagreed','context-gap'):
                raise ValueError('outcome: pass, corrected, disagreed, context-gap')
            session = state['sessions'].get(sid,{})
            if session.get('pending') != fire:
                raise ValueError('receipt does not match the pending checkpoint')
            record(outcome, sid, fire, note)
            session['pending'] = None
        elif command == 'hook':
            try:
                payload = json.load(os.fdopen(3))
            except (ValueError, OSError):
                sys.exit(0)
            if not isinstance(payload,dict) or not state['enabled'] or now >= state['expires_at']:
                sys.exit(0)
            sid = payload.get('session_id')
            event = payload.get('hook_event_name')
            if not sid or event not in ('PostToolUse','UserPromptSubmit'):
                sys.exit(0)
            session = state['sessions'].setdefault(sid,dict(count=0,last_fire=0,pending=None))
            session['touched'] = now
            if event == 'UserPromptSubmit':
                session['count'] = 0
                # Native task notifications also submit prompts; keep the review receipt valid.
            else:
                session['count'] += 1
                if session['count'] >= 20 and now-session['last_fire'] >= 1800:
                    if session['pending']:
                        record('unacknowledged',sid,session['pending'])
                    fire = uuid.uuid4().hex[:12]
                    session.update(count=0,last_fire=now,pending=fire)
                    pointers = dict(session_id=sid, transcript_path=payload.get('transcript_path'), cwd=payload.get('cwd'), checkpoint=fire)
                    record('prompted',sid,fire,json.dumps(pointers))
                    brief = pathlib.Path.home()/'scripts/hooks/spin-check-review.md'
                    message = (
                        f'SpinCheck live trial checkpoint. Shared review brief: {brief}. '
                        f'Current evidence pointers: {json.dumps(pointers)}. '
                        'This approved trial calls for a fresh native read-only reviewer using that brief, '
                        'with no inherited parent conclusions. On Codex use Sol, fork_turns=none. '
                        'Receive its result before more consequential work; act on concrete findings or explain disagreement with evidence. '
                        f'Record the result: bash "$HOME/scripts/hooks/spin-check.sh" result {json.dumps(sid)} {fire} '
                        '<pass|corrected|disagreed|context-gap> "reviewer ID, evidence and action". '
                        'Do not ask Rio to supervise the review. This prompt establishes attempted delivery, not completed review.'
                    )
                    output = dict(hookSpecificOutput=dict(hookEventName='PostToolUse',additionalContext=message))
            ordered = sorted(state['sessions'],key=lambda s: state['sessions'][s].get('touched',0))
            for old in ordered[:-64]:
                if state['sessions'][old].get('pending'):
                    record('evicted-unacknowledged',old,state['sessions'][old]['pending'])
                del state['sessions'][old]
        else:
            raise ValueError('usage: enable EPOCH | disable | status | result SESSION CHECKPOINT OUTCOME NOTE')
        if command != 'status':
            temp = path.with_suffix('.tmp')
            with temp.open('w') as handle:
                json.dump(state,handle,ensure_ascii=False)
            os.replace(temp,path)
        if output is not None:
            print(json.dumps(output,ensure_ascii=False))
    except (ValueError, KeyError, TypeError, OSError) as exc:
        print(f'SpinCheck trial infrastructure error: {exc}',file=sys.stderr)
        sys.exit(1)
PY
