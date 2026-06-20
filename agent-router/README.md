# agent-router

Small TypeScript CLI that sends one prompt to one installed agent CLI.

## What it does

- Validates prompt and provider input with `zod`
- Routes to provider-specific wrappers in `src/providers/`
- Returns plain text by default or structured JSON with `--json`

## Quick start

```zsh
pnpm install
./agent-router guide
./agent-router providers --verbose
./agent-router delegate "your prompt"

# Same commands through pnpm, if preferred:
pnpm dev -- providers
pnpm dev -- models --provider codex
pnpm dev -- delegate "your prompt"
pnpm dev -- delegate --prompt "your prompt" --provider opencode --json
```

## Commands

- `pnpm dev -- delegate "your prompt"`: run default provider (`claude`)
- `pnpm dev -- delegate --prompt "your prompt" --provider <name> --model <name>`: choose provider/model explicitly
- `pnpm dev -- guide`: show progressive usage guide for agents
- `pnpm dev -- providers`: list supported providers
- `pnpm dev -- providers --verbose`: show provider binaries, defaults, and wrapper behavior
- `pnpm dev -- models --provider <name>`: list known models for one provider
- `pnpm test`: run unit tests only, with provider subprocesses mocked
- `pnpm typecheck`: run `tsc --noEmit`

## Providers

- `claude`: runs `claude --print`
- `codex`: runs `codex exec --output-last-message ... --ephemeral`
- `antigravity`: runs `agy -p` and pipes prompt over stdin
- `opencode`: runs `opencode run <prompt> --format json` and extracts text events
- `cursor`: shells out to `cursor-delegate.sh` (from the `cursor-delegate` skill); default mode is `ask` (read-only). Override with `CURSOR_MODE=plan|ask|edit` and `--model` via `CURSOR_MODEL`.

Provider CLIs must already be installed and authenticated on your machine.

Agents should start with `./agent-router guide` instead of reading `src/`. Source inspection is only needed when changing wrapper behavior.

## Docs

- `AGENTS.md`: repo-specific guardrails for coding agents
- `CLAUDE.md`: deeper architecture and repo notes for Claude Code
