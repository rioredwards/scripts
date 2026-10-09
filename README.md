# Rio's Scripts

Small personal command wrappers and automation helpers. App-sized tools live in `~/dev`; this repo keeps script-sized glue plus compatibility shims.

## Common Commands

- `agent-router` - wrapper for `~/dev/agent-router/agent-router`. Examples: `agent-router guide`, `agent-router providers --verbose`, `agent-router delegate "prompt"`.
- `aitt` - compatibility shim for `~/dev/ai-text-transform/aitt`.
- `sc` - text-only proxy for Apple Shortcuts registered in `sc-helpers/`. Run `sc` to list aliases.
- `annotate` - draw arrows, callout labels, boxes, circles and blur redactions on an image. `annotate shot.png --callout 600,400:340,306:"this chip"`. Run `annotate shot.png --grid` first to read coordinates off a labelled overlay, and `--info` for dimensions. Agents use it to point Rio at a spot instead of describing it.
- `cal-add` - create an Apple Calendar event (defaults to "Work Time Tracking"). `cal-add "Title" --start "YYYY-MM-DD HH:MM" --duration 20 [--notes ...]`; `cal-add --list` for calendar names. Needs an unlocked GUI session on the running Mac.
- `cleanshot` - minimal CleanShot X CLI firing `cleanshot://` URL commands. Run `cleanshot` to list aliases; `--dry-run` prints the URL.
- `dev-up` - start the current repo's dev server the sanctioned way in one command: finds the start script, runs it through portless in a herdr pane, waits until it answers, sets `dev-url`, prints the tailnet URL. Agents run this instead of guessing. `dev-up -- <cmd>` for an explicit command.
- `dev-ls` - what dev servers are running on this Mac, with health, URL and uptime. `dev-ls --json` for tools.
- `dev-lease` - launcher-owned servers/panes expire 12 hours after launch or reuse. `release TOKEN` cleans task-owned servers unless reused; `stop TOKEN` explicitly stops one. `dev-ls kill` requires one owned target. Untracked servers remain untouched. `dev-lease install` installs the Mini-only five-minute sweep across both Macs; offline Macs retry next sweep. Browser activity does not renew leases. Logs: `~/Library/Logs/dev-lease.log`.
- `dev-scan` - what this Mac has to run, as JSON, for tools: `dev-scan apps`, `dev-scan worktrees <dir>`, `dev-scan scripts <dir>`. Start-script detection mirrors `dev-up`. Meant to be run over ssh too: the answers describe the machine it ran on.
- `hooks/turn-end/` - end-of-turn hooks: per-agent adapters feed `dispatch`, which summarizes, speaks, texts, publishes, and indexes each reply.
- `pm` - the one door to the project manager (`~/dev/project-manager`): `pm` talks to it, `pm daily` runs today's routine (`--headless` for no prompts), `pm last` prints the newest journal entry. `pm-daily` is a shim for `pm daily`. The desktop app runs the routine on its own at 06:30 weekdays.
- `pr-loc` - markdown LOC breakdown of the current branch's diff by kind (logic/tests/docs/config/generated) and subsystem, for PR bodies. `pr-loc [base]`.
- `text-phone-summary` - source-agnostic note pipeline helper for a file path, literal text, or stdin.
- `process-text-for-speech` - prepares text for speech via `aitt`.
- `summarize-for-note` - summarizes text for the note pipeline via `aitt`.
- `grok-stt`, `grok-tts` - Grok speech helpers.
- `agent-audio-prune` - signed Swift binary that caps disposable iCloud audio; source and tests live in `agent-audio-pruner/`.
- `run-todaybar.sh`, `todaybar-watchdog.sh` - local daily-driver status helpers.
- `keyfor` - the one way to read an API key: `keyfor NAME` or `keyfor --run NAME -- cmd`. Keys live in an age-encrypted store in `~/.dotfiles`.
- `agent-budget` - LOC appetite for the work in a repo: `set <loc>`, `status` (exit 1 when over), `clear`. Enforced by `hooks/loc-budget.sh`.
- `agent-toggle` - flip machine-local agent-hook knobs (speak, audio, text, ...) from anywhere, including over SSH. `agent-toggle` lists them.
- `agent-hooks-env.sh` - shared profile loader sourced by hook scripts (env, then local, then synced profile).
- `agy-write-guard` - Antigravity pre-tool hook that denies write tools unless `AGY_WRITE_GUARD=allow`.
- `automation-cue.sh` - show or hide a fullscreen automation cue via Hammerspoon: `start` | `stop`.
- `send-to-claude` - send a message to the Claude desktop app and print its reply.
- `send-to-chatgpt` - drive the ChatGPT web app in a dedicated logged-in Chrome and return its reply.
- `web-research` - multi-pass Brave search, extract sources, optional `aitt` synthesis. `web-research <topic> [--raw]`.
- `content-pipeline` - source (stdin, clipboard, text) through an `aitt` transform to output routes.
- `click-tool` - let an agent see on-screen text with coordinates and click it (OCR plus cliclick).
- `ax-dialog` - read and click native macOS permission dialogs through the Accessibility tree.
- `pr-review` - review a GitHub PR locally with Claude Code. `pr-review [--model ID] [PR_NUMBER]`.
- `install-pr-review` - drop the Claude auto PR-review workflow into a repo. `install-pr-review [REPO_PATH]`.
- `recap-repo-audio` - spoken re-entry recap for a repo, cached (recon bundle, `aitt`, `grok-tts`).
- `claude-token-audit.sh` - where Claude Code token and quota burn went, per session, cost-weighted.
- `narration-context`, `narration-body`, `narration-title`, `narration-render`, `narration-spoken` - stages of the turn-narration pipeline used by `hooks/turn-end/`.
- `git-commit-selector.sh` - pick a previous commit message with fzf, ready for `git commit -m`.
- `git-quicklog.sh` - last two commits with short stats.
- `tests/run-all.sh` - run every test; non-zero exit if any fails.

## Dotfiles Script Links

Several commands here are symlinks into `~/.dotfiles/scripts/` so they stay on PATH:

- `brew-add.sh`
- `brew-install-layered.sh`
- `check-brew-sync.sh`
- `check-home-paths.sh`
- `dirs-to-launchd-env.sh`
- `dotfiles-autosync`
- `dotfiles-autosync.plist`
- `drift-check.sh`
- `git-sync`
- `herdr-start.sh`
- `install-git-hooks.sh`
- `maintenance-doctor.sh`
- `path_drift_audit.py`
- `re-sync-codex-skills.sh`
- `recent-projects-refresh.sh`
- `refresh-recent-projects.py`
- `setup-hammerspoon-cli.sh`
- `tmux-layout.sh`
- `tmux-new-pane.sh`
- `tmux-new-session.sh`
- `tmux-start.sh`
- `validate-recent-projects.sh`

These are created by `stow .` in `~/.dotfiles`, which can only partly unfold into this real directory. They are tracked as relative links so both Macs see the same set; after adding a script under `~/.dotfiles/scripts/`, run `stow .` there and commit the new link here.

Archived or old one-off scripts live in `archive/`.

## MacBook wake

The Mini's SSH config runs `macbook-wake HOST PORT` before connecting to `macbook`
or its MagicDNS name. Unreachable hosts get the tested home-LAN wake packet and
up to 30 seconds to respond; authentication and commands still run once in SSH.
`ssh -G` and control requests do not wake it. Python 3, nc, route, arp and ifconfig
are macOS dependencies, verified on both Macs.

`macbook-wake --check HOST PORT` only checks reachability. Background callers also
set `MACBOOK_NO_WAKE=1` for SSH to prevent a wake if it sleeps between checks.
The five-minute session summarizer uses both and opens no persistent connection.

Home router and MacBook MAC addresses live in `~/.config/macbook-wake.json`.
The Mini's current address and broadcast are discovered, not fixed. A different
router fails explicitly. If the MacBook changes its private Wi-Fi address, update
the configured address and retest. SSH's `~/.ssh/rc` holds idle sleep on MacBooks
only for the command's lifetime; it releases the hold on exit.
