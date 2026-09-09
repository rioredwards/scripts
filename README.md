# Rio's Scripts

Small personal command wrappers and automation helpers. App-sized tools live in `~/dev`; this repo keeps script-sized glue plus compatibility shims.

## Common Commands

- `agent-router` - wrapper for `~/dev/agent-router/agent-router`. Examples: `agent-router guide`, `agent-router providers --verbose`, `agent-router delegate "prompt"`.
- `aitt` - compatibility shim for `~/dev/ai-text-transform/aitt`.
- `sc` - text-only proxy for Apple Shortcuts registered in `sc-helpers/`. Run `sc` to list aliases.
- `cal-add` - create an Apple Calendar event (defaults to "Work Time Tracking"). `cal-add "Title" --start "YYYY-MM-DD HH:MM" --duration 20 [--notes ...]`; `cal-add --list` for calendar names. Needs an unlocked GUI session on the running Mac.
- `cleanshot` - minimal CleanShot X CLI firing `cleanshot://` URL commands. Run `cleanshot` to list aliases; `--dry-run` prints the URL.
- `dev-up` - start the current repo's dev server the sanctioned way in one command: finds the start script, runs it through portless in a herdr pane, waits until it answers, sets `dev-url`, prints the tailnet URL. Agents run this instead of guessing. `dev-up -- <cmd>` for an explicit command.
- `dev-ls` - what dev servers are running on this Mac, with health, URL and uptime. `dev-ls --json` for tools.
- `dev-scan` - what this Mac has to run, as JSON, for tools: `dev-scan apps`, `dev-scan worktrees <dir>`, `dev-scan scripts <dir>`. Start-script detection mirrors `dev-up`. Meant to be run over ssh too: the answers describe the machine it ran on.
- `hooks/note-on-turn/` - hook scripts for summarizing final agent replies into the phone note pipeline.
- `pr-loc` - markdown LOC breakdown of the current branch's diff by kind (logic/tests/docs/config/generated) and subsystem, for PR bodies. `pr-loc [base]`.
- `text-phone-summary` - source-agnostic note pipeline helper for a file path, literal text, or stdin.
- `process-text-for-speech` - prepares text for speech via `aitt`.
- `summarize-for-note` - summarizes text for the note pipeline via `aitt`.
- `grok-stt`, `grok-tts` - Grok speech helpers.
- `agent-audio-prune` - signed Swift binary that caps disposable iCloud audio; source and tests live in `agent-audio-pruner/`.
- `run-todaybar.sh`, `todaybar-watchdog.sh` - local daily-driver status helpers.

## Dotfiles Script Links

Several commands here are symlinks into `~/.dotfiles/scripts/` so they stay on PATH:

- `brew-add.sh`
- `brew-install-layered.sh`
- `check-brew-sync.sh`
- `drift-check.sh`
- `install-git-hooks.sh`
- `keychain-to-launchd-env.sh`
- `maintenance-doctor.sh`
- `path_drift_audit.py`
- `re-sync-codex-skills.sh`
- `remove-keychain-api-key.sh`
- `setup-hammerspoon-cli.sh`
- `setup-keychain-api-key.sh`
- `validate-recent-projects.sh`

Archived or old one-off scripts live in `archive/`.
