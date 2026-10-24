# reply-options

When a Claude or Codex chat finishes a turn, this engine writes 1-4 categorized replies Rio could
send back. UIs (the Raycast picker, the Actions Ring) only call this CLI and read its JSON; nothing is sent to any app.

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
  `--recent [N]` prints a JSON array of up to N (default 5) non-stale sessions, any status, in
  display order: the session Rio last had on screen first (`"focused": true`, every other entry
  `false`), then by when he last focused each one (`focused_at`, null if never seen), else by
  `created_at`. It covers state files from the last 24 h plus older ones he focused since. Focus
  comes from `~/.cache/focused-session.json` (override: `FOCUSED_SESSION_FILE`), written by
  Hammerspoon's `focusedSession` feature on each focus change:
  `{v, agent, session, title, frontmost, focused_at, updated_at, recent}`, where `recent` is
  `[{agent, session, focused_at}]`, newest first, capped at 30. It keeps the last agent session
  when another app (such as Raycast) takes focus. UIs keep this order. `--force` implies
  `--generate` and always regenerates.
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

## Status and next steps (2026-10-23)

Spike, running live as a trial. Disposition: promote after Rio uses it for a few days; until then
prompt quality and the category set are drafts (`SPIKE:` comments mark shortcuts).

- UI V1: Raycast "Reply Options" in `~/dev/rio-raycast-toolbox`, opened by Hyper+Z
  (`hammerspoon://replyoptions`). Enter copies the reply, Cmd+R regenerates. Nothing is sent
  into any app.
- Mouse UI: Actions Ring bubbles, one per category, each opening
  `hammerspoon://reply-option?category=<category>` (Hammerspoon `features/replyRing.lua`). It
  copies the top `--recent` chat's first option in that category and shows it in an alert; a
  missing category says which ones the chat has. Labels are fixed per bubble: Options+ can't
  render live labels without a Logi SDK plugin. Set up by hand in Options+ (2026-10-23): a
  "Reply" folder of 8 Web Page bubbles in the global ring (replacing its Easy-Switch slot, which
  now sits inside the folder) and in the Vizhi for ChatGPT ring, which replaces the global one
  while ChatGPT is in front. Stored in each ring's `ProfileInfo.json` under
  `~/Library/Application Support/Logi/LogiPluginService/Applications/Loupedeck72/`.
- Not built yet: injection into Claude (`$.prompt.fill` mod) or Codex; MacBook picker (the hook
  also generates there once `~/scripts` pulls; `agent-toggle reply-options off` stops it).
- Unverified by a human: the Hyper+Z press, Enter-to-copy HUD, Cmd+R in the UI, and Raycast's
  one-time "Always Open Command" prompt.
- Known limit: a brand-new Claude chat may store `title: null` until its next turn.
