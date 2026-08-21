# Agent rules — pilot

Prose in `AGENTS.md` is advisory; a hook is not. This turns "write another guard
script" into "add a JSON entry".

Add a rule → edit `rules.json` → run `./validate.sh`. No restart needed for
`tool` rules; Claude re-reads the file every call.

## Schema

Every field. There is nothing else.

| Field | Values | Notes |
|---|---|---|
| `id` | string | Unique. Shown to the agent when a `response` rule fires. |
| `on` | `tool` \| `response` | When it is checked. |
| `match.tool` | regex | `on: tool` only. Matches the tool name (`Bash`, `Edit`, …). |
| `match.input` | regex | `on: tool` only. Matches `tool_input.command`, else the whole input as JSON. |
| `match.text` | regex | `on: response` only. Matches the final reply. |
| `unless` | regex | Optional escape hatch. Matches the same subject → rule skipped. |
| `do` | `remind` \| `deny` | `deny` is `on: tool` only. |
| `text` | string | What the agent is told. State the rule **and** what to do instead. |

Omitted `match` keys match anything; all present keys must match (AND).

- **`remind`** on a tool → runs anyway, nudge lands in the agent's context. Rio is
  never prompted.
- **`deny`** on a tool → blocked, agent sees `text` as the reason.
- **`remind`** on a response → the reply is bounced and rewritten. One retry only.

Regexes are Oniguruma (jq): `(?i)` for case-insensitive, `[[:space:]]` classes work.

## Wiring

`run.sh <tool|response>`, hook payload on stdin.

| Rule kind | Claude event | Registered |
|---|---|---|
| `tool` | `PreToolUse`, matcher `*` | ✅ in `.dotfiles/.claude/settings.json` |
| `response` | `Stop` | ✅ in `.dotfiles/.claude/settings.json` |

A bounced reply re-fires the whole `Stop` chain, so a hook with real side
effects must skip the pass that is about to be rewritten — otherwise one
`fallback` costs Rio two phone texts. `hooks/lib/reply-cap-lib.sh` owns that
predicate: `reply_will_be_rewritten` is true for a reply over the length cap
**or** one tripping a `response` rule. Side-effect hooks call it, not
`reply_will_bounce`. The rules half delegates to `run.sh response` and checks
for exit 2, so there is no copy of the matching logic to drift.

⚠️ Never register the `response` hook `async` — an async `Stop` hook cannot
block a stop, so it would match rules and let the reply through anyway.

## Design notes

- **Fails open.** A broken rules file must never wedge every tool call on the
  machine. `validate.sh` is where bad rules fail loudly.
- **No Node.** A `PreToolUse` hook runs on every tool call; a Node cold start is
  ~50ms of that, every time. `sh` + `jq` is ~5ms. The typed-schema benefit Rio
  wanted from zod is delivered by `validate.sh` + this table instead.
- **Replaced:** `hooks/rm-guard.sh` (still on disk, unregistered).
- **Not replaced:** `issue-skill-guard.sh` and `loop-reminder.sh` need per-session
  state (marker files, throttles) that this schema has no way to express. If the
  pilot survives, that is the first thing to add.
