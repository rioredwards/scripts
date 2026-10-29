# Agent rules: pilot

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
| `match.content` | regex | Tool only. Whole input, excluding Edit old_string and patch removal/context lines. |
| `match.text` | regex | `on: response` only. Matches the final reply. |
| `scope` | `all` | Optional, response-only. Also enforce on retries and delegates. |
| `unless` | regex | Optional escape hatch. Matches the same subject → rule skipped. |
| `when` | `{knob, in}` | Optional. Rule applies only while session knob `knob` (`agent-knobs.json`) is one of `in`. |
| `do` | `remind` \| `deny` | `deny` is `on: tool` only. |
| `text` | string | What the agent is told. State the rule **and** what to do instead. |

Omitted `match` keys match anything; all present keys must match (AND).

- **`remind`** on a tool → runs anyway, nudge lands in the agent's context. Rio is
  never prompted.
- **`deny`** on a tool → blocked, agent sees `text` as the reason.
- **`remind`** on a response → the reply is bounced and rewritten. One retry only, unless `scope: all`.

Regexes are Oniguruma (jq): `(?i)` for case-insensitive, `[[:space:]]` classes work.

## Wiring

`run.sh <tool|response>`, hook payload on stdin.

| Rule kind | Claude event | Registered |
|---|---|---|
| `tool` | `PreToolUse`, matcher `*` | Claude settings and Codex hooks.json (`run.sh tool codex`) |
| `response` | `Stop` | Claude settings and Codex hooks.json |
| `response`, scope all | `SubagentStop` | Claude settings |

A bounced reply re-fires the whole `Stop` chain, so a hook with real side
effects must skip the pass that is about to be rewritten, otherwise one
`fallback` costs Rio two phone texts. `hooks/lib/reply-cap-lib.sh` owns that
predicate: `reply_will_be_rewritten` is true for a reply over the length cap
**or** one tripping a `response` rule. Side-effect hooks call it, not
`reply_will_bounce`. The rules half delegates to `run.sh response` and checks
for exit 2, so there is no copy of the matching logic to drift.

⚠️ Never register the `response` hook `async`, an async `Stop` hook cannot
block a stop, so it would match rules and let the reply through anyway.

## Design notes

- **Fails open.** A broken rules file must never wedge every tool call on the
  machine. `validate.sh` is where bad rules fail loudly.
- **No Node.** A `PreToolUse` hook runs on every tool call; a Node cold start is
  ~50ms of that, every time. `sh` + `jq` is ~5ms. The typed-schema benefit Rio
  wanted from zod is delivered by `validate.sh` + this table instead.
- **Replaced:** `rm-guard.sh` (now in `archive/`).
- **Not replaced:** `issue-skill-guard.sh` and `loop-reminder.sh` need per-session
  state (marker files, throttles) that this schema has no way to express. If the
  pilot survives, that is the first thing to add.

## Em dashes

File writes only (Rio, 2026-09-10: replies and other tool text are fine).
`no-em-dash-files` denies literal U+2014 in Write/Edit/MultiEdit/NotebookEdit and
apply_patch input. Edit `old_string` and patch removal/context lines are excluded so
existing characters can be removed. `no-em-dash-shell-writes` denies it in shell
commands that write a file (`cat`/`echo`/`printf` redirect, `tee`, `sed -i`,
`perl -i`); `git commit` and `gh pr/issue/api/release` are exempt.

Coverage is hook-visible text, not tool results, streamed commentary, or text
constructed by executed code. These rules do not scan or rewrite existing files.

Claude subagent registration follows [the hook reference](https://code.claude.com/docs/en/hooks#subagentstop). New registrations require a fresh Claude session.

## Railway

Agents never change prod. `railway-mcp-read-only` denies every Railway MCP write tool
(set/create/delete/update/connect/generate, redeploy, restart, accept-deploy, railway-agent)
plus `list-variables`, so values never reach a transcript. `railway-cli-read-only` denies the
`railway` CLI subcommands that write, deploy, or expose variables (`up`, `down`, `variables`,
`run`, `shell`, `ssh`, `connect`, `api`, and the rest); `status`, `logs`, `metrics`, `list`,
`deployment list`, `service list`, `domain list`, `docs` stay open. Deny list, not allow
list, so `railway logs && railway up` cannot slip through. Ledger: L-0114.

## Neon and Vercel

Agents must not touch the production database (Oct 2026: a preview build seeded production Neon).
These hooks inspect tool input text, not the authority held by the OS user. They do not
inspect executed script files, resolve runtime-built hosts, isolate browser sessions, or
stop an unrestricted user from changing the hooks. The runner also fails open on missing
dependencies or invalid configuration. Passing hook tests proves matching,
not absence of production access. Revoke production-capable credentials at the provider;
removing a local file alone leaves its other copies valid. Vercel access remains available for normal app operations. A production deployment can run
code with database authority even when its credentials are hidden; these hooks do not
claim to isolate that authority.

Production DB credential protection is tracked in
[keep production DB credentials restricted while allowing Vercel operations](https://github.com/rioredwards/scripts/issues/36).

`neon-direct-connection` denies any shell or MCP call carrying a Neon endpoint host or connection
string (`ep-*.neon.tech`, `postgres://...neon.tech`, `-h`/`PGHOST=`/`host=` with a `.neon.tech`
host); no read exception. `neon-cli-read-only` allows only `neonctl` projects/branches list|get,
`me`, orgs list, operations list, help, version. `neon-api-read-only` keeps `console.neon.tech/api`
GET-only and never fetches `connection_uri` or `reveal_password`; a write Rio approved in chat for
that exact call passes with a `RIO_NEON_WRITE_OK=1 ` prefix, credential paths still blocked.
The three Vercel rules retain their historical `read-only` IDs but now guard credential
retrieval: CLI `pull`, `env pull|get|run`, and API environment/decrypt/connection paths; MCP
environment, secret and connection retrieval tools. Ordinary CLI/API/MCP operations, including
login, build, dev, preview deploys and project changes, are permitted. Existing global approval
rules still apply to production deployment, production configuration, merging, spending and destructive actions.
Production DB command/API access and credential retrieval remain prohibited. On 2026-10-29,
all 18 Neon variables in the existing Vercel console were verified Secret and Production-only,
with no Shared variables linked. This snapshot does not prove every credential location is protected.
Browser access is outside this guard scope; no browser isolation, separate Mac login/VM, or
new-token experiment is required.

CLI checks match an invocation, not a word: the lowercase token must sit at a command position
(start, after `;`, `&&`, `|`, newline, backtick, `$(`/`<(`, a subshell `(` or `{`, `then`/`do`,
a shell's `-c '`, `ssh host`, through npx/pnpm/env/keyfor wrappers) and end at whitespace, `;`,
`&` or the end. So `grep vercel`, `build(vercel):`, `"neon|vercel"` and commit messages pass
while `vercel ls && vercel env pull` denies. Misses: hosts or methods built at runtime, a script
file run later. False denies: heredoc prose that holds a CLI call at a command position (a line
starting with lowercase `vercel`, `vc` or `neon` plus a word, a backticked call, a markdown table
cell), and a shell command that merely mentions an API host with a credential path (`connection_uri`,
`/env`, `decrypt`). Edit such docs with the file tools.
Ledger: L-0114.

## UI tests

Common test launchers require `RIO_UI_TEST_MODE=headless` (inspect the config and
launch helper first), `approved` (explicit consent for this run), or `isolated`
(verified unused target that cannot steal active-desktop focus/input). Visible
launches reject the headless declaration. Have a timeout and independent stop
command ready before visible tests. Another monitor or Space alone is not isolation.

These Claude/Codex gates match direct launches, common SSH/timeout wrappers, and
explicit visible JS launches. They rely on agent verification, not OS enforcement;
indirect scripts and unusual command chains still follow the shared global rule.

## Raw tabs

`no-writing-raw-tabs` denies a Bash command or file write that has a Sheets write verb
(API, gws, gog, gspread) plus a `<Name>-Raw` tab name. Rio pastes those tabs from the
distributor exports. Misses: tab name built without a literal `-Raw`, a script file run
later, MCP sheet tools. Also blocks a call that reads a Raw tab and writes another tab in one script.
