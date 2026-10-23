# reply-options

When a Claude or Codex chat finishes a turn, this engine writes 1-4 categorized replies Rio could
send back. UIs (the Raycast picker) only call this CLI and read its JSON; nothing is sent to any app.

## How it runs

- **Eager:** `hooks/turn-end/dispatch` forks a detached `generate` on every real Claude or Codex
  turn, after its empty-reply and delegate guards, before narration. Failures land in the state
  file (`status: "error"`) and `~/.cache/reply-options/generate.log` (kept under 1000 lines).
- **Lazy:** `get --generate` makes a missing, stale or failed one from the transcript. **Knob:**
  `AGENT_REPLY_OPTIONS` (default `on`); `agent-toggle reply-options off` stops eager calls.
- **Spend:** one OpenAI Responses call per new reply (`llm_json`, strict schema, no reasoning),
  charged to its own `reply-options` bucket in `call-budget-lib.sh`, capped at 400 a day.
  Model `gpt-6-luna`, override with `REPLY_OPTIONS_MODEL`. Measured about 2.0-2.2 s per call.
- **Skips:** Codex prompt suggestions (`{"suggestion":...}`) exit 0, no file. Other agents never fork.

## CLI

```sh
reply-options generate --agent claude|codex --session ID --cwd DIR --transcript PATH [--force] < reply
reply-options get --latest [--generate]
reply-options get --session ID [--generate] [--force]
reply-options get --recent [N]
```

- `generate` reads the agent reply on stdin and writes the state file. It dedupes per
  (session, reply hash): the same reply again makes no call unless the last try failed or
  `--force` is given. Prunes state files older than 3 days.
- `get` prints one state object as compact JSON, with `title` and `stale` filled in.
  `--recent [N]` prints a JSON array of up to N (default 5) non-stale sessions from the last 24 h,
  newest first, any status. `--force` implies `--generate` and always regenerates.
- Failures exit 1 with one line on stderr (`reply-options: ...`); usage errors exit 2.

## State

`~/.cache/reply-options/<agent>-<session>.json` (override dir: `REPLY_OPTIONS_DIR`), written
atomically (tmp + mv).

```json
{
  "v": 1,
  "status": "ready|error|skipped",
  "agent": "claude|codex",
  "session": "...", "title": "chat title or null", "cwd": "...", "transcript": "...",
  "reply_sha": "16 hex of sha256", "reply_excerpt": "first ~200 chars, newlines as spaces",
  "created_at": "ISO-8601, seconds", "model": "gpt-6-luna", "ms": 2028, "stale": false,
  "error": null, "skip_reason": null,
  "options": [
    {"id": "o1", "category": "accept", "color": "green", "label": "Run the sync", "text": "..."}
  ]
}
```

- `options` is non-empty only when `status` is `ready` (1-4 items, ids `o1`..`oN` in model order).
  `skipped` means the model judged the reply a pure report and gave a `skip_reason`. `error`
  carries `error` (API failure, spent cap, not 1-4 options, or a text with [ or {; 0 needs a skip_reason). `ms` is the model call's latency.
- `category` and its fixed `color` token:

  | category | color | meaning |
  | --- | --- | --- |
  | accept | green | yes, go ahead |
  | reject | red | no, don't |
  | redirect | orange | different approach or goal |
  | narrow | yellow | smaller scope |
  | explain | blue | say it again, plainer |
  | clarify | blue | pointed question about one point |
  | verify | purple | prove it first |
  | defer | gray | not now |

  UIs map tokens to their own palette and render an unknown category or color gray, never drop it.
  A category can repeat (two accepts for "go with A" and "go with B").
- `title` (stored at `generate` time; a null Codex one is retried at `get`): Claude desktop store
  (`~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`, `cliSessionId`
  match) or Codex `~/.codex/state_5.sqlite` `threads` (`name`, else `title`, read-only).
- `stale` (at `get` time): the transcript has a user line newer than `created_at`, meaning Rio
  already answered. Not file mtime: both agents append bookkeeping lines after Stop.

## Prompt

Input: Rio's last prompt (`reply_last_prompt`, 2000 chars) and the reply's last 12000 chars (the
ask is usually at the end). Output: `label` (1-4 words) and `text` in Rio's voice.
