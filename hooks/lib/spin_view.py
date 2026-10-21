#!/usr/bin/env python3
"""spin_view.py: the fixed view the spin-check final-reply judge reads.

Built from the raw Claude or Codex transcript, never from text the agent chose
(L-0108). Sections, in order:

  SESSION CONTEXT   the latest SessionStart / UserPromptSubmit hook context
                    (session knobs, machine, reply cap).
  EARLIER           every message from Rio, whole, each followed by the agent's
                    final reply to it, whole, plus incoming events (task
                    notifications, CI events, messages from other sessions),
                    trimmed. Bounced drafts are dropped: only the reply that
                    stood counts. Over budget, the oldest agent replies and
                    events go first; Rio's messages are never cut.
  RIO'S LATEST MESSAGE, whole.
  WORK SINCE        every agent message, tool call, tool result, incoming event
                    and hook note since then. Over budget, the longest results
                    are cut first, each cut naming its transcript line.
  FILES WRITTEN, FINAL REPLY, and the TRANSCRIPT path for grep look-ups.

Usage: spin_view.py TRANSCRIPT [--reply-file F] [--until ISO_TS]
  --reply-file  the reply being judged (default: the last agent text run in
                the transcript, which is then left out of WORK SINCE).
  --until       replay: ignore records at or after this UTC timestamp.
"""
import argparse
import json
import os
import re
import sys

EARLIER_BUDGET = 90_000   # chars
WORK_BUDGET = 110_000
EVENT_CAP = 1_500         # an event in EARLIER
TOOL_INPUT_CAP = 3_000
RESULT_FLOOR = 1_500      # a cut result keeps this much (head and tail)
HOOK_CTX_CAP = 4_000
RIO_CAP = 8_000           # an earlier message from Rio (a long paste); his latest stays whole

WRAPPER_RE = re.compile(
    r"^\s*(\[Request interrupted|Caveat:|Base directory for this skill|This session is being continued"
    r"|Stop hook feedback:|# AGENTS\.md instructions|\(Re-invocation of )")
AMBIENT_RE = re.compile(
    r"^\s*<(system-reminder|artifact-view-context|in-app-browser-context)\b[^>]*>[\s\S]*?</\1>")
DROP_RE = re.compile(r"<(environment_context|user_instructions|turn_aborted|permissions|skill>"
                     r"|external_codex_apps_open_page|recommended_plugins)")
RIO_TAG_RE = re.compile(r"<(pasted_content|realtime_delegation|send_user_message_question_reply|scheduled-task)\b")
WRITE_TOOLS = re.compile(r"^(Edit|Write|NotebookEdit|MultiEdit)$")
PATCH_FILE = re.compile(r"\*\*\* (?:Add|Update|Delete) File: (\S+)")
SHELL_WRITE = re.compile(
    r"(^|[;&|(]\s*)(sed\s+(-\w+\s+)*-\w*i|perl\s+-\w*i|tee|mv|cp|rm|trash|touch|ln|patch"
    r"|git\s+(commit|apply|mv|rm|restore|reset|push))(\s|$)|(^|[^-=>0-9&<])>>?\s*[~/.$\w\"']")
JS_CMD = re.compile(r'"?cmd"?:\s*"((?:[^"\\]|\\.)*)"')
QUIET_REDIRECT = re.compile(r"[0-9]*>>?\s*/dev/(null|stderr|stdout|tty)|&>\s*/dev/null|[0-9]*>&[0-9-]")


def text_of(content):
    """Message content -> text, with images marked (the judge cannot see them)."""
    if isinstance(content, str):
        return content
    parts = []
    for b in content or []:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t in ("text", "input_text", "output_text"):
            parts.append(b.get("text") or "")
        elif t in ("image", "input_image"):
            parts.append("[image attached: you cannot see it; a claim may rest on it]")
    return "\n".join(parts)


def classify(text, origin_kind=None):
    """An incoming message -> [(kind, text)], kind rio | event | bounce; wrappers yield nothing.
    Apps prepend ambient blocks (reminders, viewer state) to Rio's own text: split them off."""
    text = re.sub(r"<!-- reply( \d+)? -->", "", text).strip()
    out, prefix = [], []
    while m := AMBIENT_RE.match(text):
        prefix.append(m.group(0).strip())
        text = text[m.end():].strip()
    ambient = "\n".join(prefix)
    if "Linked sessions now" in ambient or "forked this session" in ambient:
        out.append(("event", ambient))
    if not text or WRAPPER_RE.match(text) or DROP_RE.match(text):
        return out
    m = re.match(r"<command-name>([^<]*)</command-name>", text) or (
        re.search(r"<command-name>([^<]*)</command-name>", text) if text.startswith("<command-") else None)
    if m:
        args = re.search(r"<command-args>([\s\S]*?)</command-args>", text)
        return out + [("rio", (m.group(1) + " " + (args.group(1) if args else "")).strip())]
    if text.startswith("<bash-input>"):
        return out + [("rio", "(Rio ran in his shell)\n" + text)]
    if text.startswith("<hook_prompt"):
        return out + [("bounce", text)]
    if RIO_TAG_RE.match(text):
        return out + [("rio", text)]
    if text.startswith("<") or origin_kind not in (None, "human"):
        return out + [("event", text)]
    return out + [("rio", text)]


def records(path, until):
    """Yield normalized items: dicts with kind in rio|event|text|tool|result|hook|bounce|ctx."""
    codex = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if not isinstance(r, dict):
                continue
            if codex is None:
                codex = r.get("type") == "session_meta"
            ts = r.get("timestamp") or ""
            if until and ts and ts >= until:
                break
            yield from (codex_items if codex else claude_items)(r, n)


def claude_items(r, n):
    t = r.get("type")
    if t == "attachment":
        a = r.get("attachment") or {}
        at = a.get("type")
        if at == "queued_command":
            p = a.get("prompt")
            for kind, text in classify(text_of(p if isinstance(p, list) else str(p or "")),
                                       (a.get("origin") or {}).get("kind")):
                yield {"kind": kind, "text": text, "line": n}
        elif at == "hook_additional_context":
            content = a.get("content")
            content = "\n".join(content) if isinstance(content, list) else str(content or "")
            ev = a.get("hookEvent") or ""
            if ev in ("SessionStart", "UserPromptSubmit"):
                yield {"kind": "ctx", "hook": ev, "text": content, "line": n}
            else:
                yield {"kind": "hook", "hook": a.get("hookName") or ev, "text": content, "line": n}
        return
    msg = r.get("message") or {}
    content = msg.get("content")
    if t == "user":
        if r.get("isCompactSummary"):
            return
        if r.get("isMeta"):
            if text_of(content).lstrip().startswith("Stop hook feedback:"):
                yield {"kind": "bounce", "line": n}
            return
        if isinstance(content, list) and any(b.get("type") == "tool_result" for b in content if isinstance(b, dict)):
            for b in content:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    yield {"kind": "result", "text": text_of(b.get("content")), "line": n,
                           "error": bool(b.get("is_error"))}
            return
        for kind, text in classify(text_of(content), (r.get("origin") or {}).get("kind")):
            yield {"kind": kind, "text": text, "line": n}
    elif t == "assistant":
        for b in content or []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text" and (b.get("text") or "").strip():
                yield {"kind": "text", "text": b["text"], "line": n}
            elif b.get("type") == "tool_use":
                inp = b.get("input")
                yield {"kind": "tool", "name": b.get("name") or "?", "line": n,
                       "input": inp if isinstance(inp, dict) else {"input": inp}}


def codex_items(r, n):
    if r.get("type") != "response_item":
        return
    p = r.get("payload") or {}
    pt = p.get("type")
    if pt == "message" and p.get("role") == "user":
        for kind, text in classify(text_of(p.get("content"))):
            yield {"kind": kind, "text": text, "line": n}
    elif pt == "message" and p.get("role") == "developer":
        # Codex hands hook context over as developer messages; ours open with these lines.
        txt = text_of(p.get("content")).strip()
        hook = "SessionStart" if txt.startswith("Machine:") else "UserPromptSubmit" if txt.startswith("Seat:") else ""
        if hook:
            yield {"kind": "ctx", "hook": hook, "text": txt, "line": n}
    elif pt == "message" and p.get("role") == "assistant":
        txt = text_of(p.get("content"))
        if txt.strip():
            yield {"kind": "text", "text": txt, "line": n}
    elif pt in ("function_call", "custom_tool_call"):
        raw = p.get("arguments") or p.get("input") or ""
        try:
            args = json.loads(raw) if isinstance(raw, str) else raw
        except ValueError:
            args = {"input": raw}
        if not isinstance(args, dict):
            args = {"input": raw}
        yield {"kind": "tool", "name": p.get("name") or "?", "input": args, "line": n}
    elif pt in ("function_call_output", "custom_tool_call_output"):
        out = p.get("output")
        if isinstance(out, dict):
            out = out.get("content") or out.get("output") or json.dumps(out)
        yield {"kind": "result", "text": text_of(out) if isinstance(out, list) else str(out or ""), "line": n}


def written_files(item):
    name, inp = item["name"], item["input"]
    if WRITE_TOOLS.match(name):
        yield str(inp.get("file_path") or inp.get("notebook_path") or "?")
    blob = json.dumps(inp)
    for m in PATCH_FILE.finditer(blob.replace("\\n", "\n")):
        yield m.group(1)
    if name in ("Bash", "shell", "exec_command"):
        cmds = [str(inp.get("command") or inp.get("cmd") or "")]
    elif name == "exec":  # Codex code mode: JS calling tools.exec_command({cmd:"..."})
        cmds = JS_CMD.findall(str(inp.get("input") or ""))
    else:
        cmds = []
    for cmd in cmds:
        if SHELL_WRITE.search(QUIET_REDIRECT.sub("", cmd)):
            yield "$ " + " ".join(cmd.split())[:200]


def tool_line(item):
    inp = item["input"]
    if item["name"] in ("Bash", "shell", "exec_command") and isinstance(inp, dict) and len(inp) <= 3:
        body = str(inp.get("command") or inp.get("cmd") or json.dumps(inp))
    else:
        body = json.dumps(inp, ensure_ascii=False)
    if len(body) > TOOL_INPUT_CAP:
        body = body[:TOOL_INPUT_CAP] + f" [input cut; full text at transcript line {item['line']}]"
    return f"[line {item['line']}] TOOL {item['name']}: {body}"


def cut(text, keep, line):
    if len(text) <= keep:
        return text
    h = keep * 2 // 3
    return (text[:h] + f"\n[... {len(text) - keep} chars cut; full text at transcript line {line} ...]\n"
            + text[-(keep - h):])


def build(path, reply, until):
    items = list(records(path, until))
    # Turns: an incoming message (Rio or event) starts one. The final reply of a
    # turn is its trailing run of agent text; a hook bounce discards the draft.
    rio_idx = [i for i, it in enumerate(items) if it["kind"] == "rio"]
    last_rio = rio_idx[-1] if rio_idx else -1

    # The reply under review is the transcript's last text run when not given.
    tail_texts = []
    for it in reversed(items):
        if it["kind"] == "text":
            tail_texts.append(it)
        elif it["kind"] in ("hook", "ctx") or (it["kind"] == "bounce" and not tail_texts):
            continue  # a sibling Stop hook may have bounced this same reply
        else:  # a bounce before the reply ends it: the draft it bounced is not this reply
            break
    if reply is None:
        reply = "\n\n".join(it["text"] for it in reversed(tail_texts))
        drop = {id(it) for it in tail_texts}
    else:
        norm = lambda s: " ".join(s.split())
        drop = {id(it) for it in tail_texts if norm(it["text"]) in norm(reply)}
    items = [it for it in items if id(it) not in drop]

    ctx = {}
    for it in items:
        if it["kind"] == "ctx":
            ctx[it["hook"]] = it
    ctx_text = "\n\n".join(f"({h}, line {it['line']})\n{cut(it['text'], HOOK_CTX_CAP, it['line'])}"
                           for h, it in sorted(ctx.items())) or "(none)"

    # EARLIER: Rio + final replies + events, before Rio's latest message.
    blocks = []  # (priority, text): 0 = Rio (never dropped), 1 = reply/event
    run = []
    def flush():
        if run:
            t = "\n\n".join(x["text"] for x in run)
            blocks.append([1, f"AGENT (final reply, line {run[-1]['line']}):\n{t}"])
            run.clear()
    for it in items[:max(last_rio, 0)]:
        k = it["kind"]
        if k == "text":
            run.append(it)
        elif k == "tool":
            run.clear()
        elif k == "bounce":
            run.clear()
        elif k == "rio":
            flush()
            blocks.append([0, f"RIO (line {it['line']}):\n{cut(it['text'], RIO_CAP, it['line'])}"])
        elif k == "event":
            flush()
            blocks.append([1, f"EVENT (line {it['line']}):\n{cut(it['text'], EVENT_CAP, it['line'])}"])
    flush()
    total = sum(len(b[1]) for b in blocks)
    omitted = 0
    for b in blocks:  # oldest first
        if total <= EARLIER_BUDGET:
            break
        if b[0] == 1:
            total -= len(b[1])
            b[1] = None
            omitted += 1
    earlier = [b[1] for b in blocks if b[1] is not None]
    if omitted:
        earlier.insert(0, f"({omitted} older agent replies and events omitted for length; grep the transcript)")

    latest = items[last_rio]["text"] if last_rio >= 0 else "(none found)"
    latest_line = items[last_rio]["line"] if last_rio >= 0 else "?"

    # WORK SINCE Rio's latest message.
    work, files = [], []
    for it in items[last_rio + 1:]:
        k = it["kind"]
        if k == "text":
            work.append([None, f"[line {it['line']}] AGENT: {it['text']}"])
        elif k == "tool":
            work.append([None, tool_line(it)])
            files.extend(f for f in written_files(it) if f not in files)
        elif k == "result":
            label = "RESULT (error)" if it.get("error") else "RESULT"
            work.append([it, f"[line {it['line']}] {label}: " + it["text"]])
        elif k == "event":
            work.append([it, f"[line {it['line']}] EVENT: {it['text']}"])
        elif k == "hook":
            work.append([None, f"[line {it['line']}] HOOK NOTE ({it['hook']}): {cut(it['text'], 1000, it['line'])}"])
        elif k == "bounce":
            work.append([None, f"[line {it['line']}] (a hook bounced the agent's reply; it was rewritten)"])
    total = sum(len(w[1]) for w in work)
    if total > WORK_BUDGET:
        # Cut the longest results first, down to RESULT_FLOOR each.
        for w in sorted((w for w in work if w[0] and w[0]["kind"] == "result"), key=lambda w: -len(w[1])):
            if total <= WORK_BUDGET:
                break
            new = cut(w[1], RESULT_FLOOR, w[0]["line"])
            total -= len(w[1]) - len(new)
            w[1] = new
        # Then drop the oldest steps; events are evidence the judge must see, so they go last.
        dropped = 0
        for keep_events in (True, False):
            for w in work[:-1]:
                if total <= WORK_BUDGET:
                    break
                if w[1] is not None and not (keep_events and w[0] and w[0]["kind"] == "event"):
                    total -= len(w[1])
                    w[1] = None
                    dropped += 1
        work = [w for w in work if w[1] is not None]
        if dropped:
            work.insert(0, [None, f"({dropped} older steps omitted for length; grep the transcript)"])
    work_text = "\n".join(w[1] for w in work) or "(nothing: the agent replied directly)"

    return f"""SESSION CONTEXT (hook-injected settings Rio picked: knobs, machine, reply cap):
{ctx_text}

=== EARLIER CONVERSATION (oldest first: Rio's messages whole, the agent's final reply to each, incoming events) ===
{chr(10).join(earlier) if earlier else "(none)"}

=== RIO'S LATEST MESSAGE (line {latest_line}) ===
{latest}

=== WORK SINCE RIO'S LATEST MESSAGE (agent messages, tool calls, results, incoming events; chronological) ===
{work_text}

=== FILES WRITTEN SINCE RIO'S LATEST MESSAGE ===
{chr(10).join(files) or "(none)"}

=== FINAL REPLY (being judged) ===
{reply}

=== TRANSCRIPT (raw JSONL, read-only; [line N] above points into it) ===
{path}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript")
    ap.add_argument("--reply-file")
    ap.add_argument("--until")
    a = ap.parse_args()
    if a.until and re.fullmatch(r".*T\d\d:\d\d:\d\dZ", a.until):
        a.until = a.until[:-1] + ".000Z"  # transcripts carry milliseconds
    reply = open(a.reply_file, encoding="utf-8").read() if a.reply_file else None
    sys.stdout.write(build(os.path.abspath(a.transcript), reply, a.until))


if __name__ == "__main__":
    main()
