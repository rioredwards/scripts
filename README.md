# Rio's Scripts

Small personal command wrappers and automation helpers. App-sized tools live in `~/dev`; this repo keeps script-sized glue plus compatibility shims.

## Common Commands

- `agent-router` - wrapper for `~/dev/agent-router/agent-router`. Examples: `agent-router guide`, `agent-router providers --verbose`, `agent-router delegate "prompt"`.
- `aitt` - compatibility shim for `~/dev/ai-text-transform/aitt`.
- `sc` - text-only proxy for Apple Shortcuts registered in `sc-helpers/`. Run `sc` to list aliases.
- `cleanshot` - minimal CleanShot X CLI firing `cleanshot://` URL commands. Run `cleanshot` to list aliases; `--dry-run` prints the URL.
- `hooks/note-on-turn/` - hook scripts for summarizing final agent replies into the phone note pipeline.
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
