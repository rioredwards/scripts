# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```zsh
pnpm install          # install deps
pnpm dev -- delegate "your prompt"                      # run CLI (default: claude)
pnpm dev -- delegate --prompt "your prompt"             # equivalent flag form
pnpm dev -- delegate --prompt "your prompt" --provider codex  # use codex
pnpm dev -- delegate --prompt "your prompt" --provider codex --model gpt-4.1
pnpm dev -- delegate --prompt "your prompt" --json      # JSON output
pnpm test             # unit tests (vitest, no real subprocess)
pnpm typecheck        # tsc --noEmit
```

Run a single test file: `pnpm test test/delegate.test.ts`

## Architecture

Non-interactive CLI that routes prompts to agent binaries (`claude`, `codex`, `agy`).

```
src/schema.ts           -- zod schema for DelegateInput + DelegateResult; exports ProviderName
src/delegate.ts         -- validates input, routes to provider
src/providers/
  claude.ts             -- runs claude --print <prompt> via execa
  codex.ts              -- runs codex exec --output-last-message <tmp> --ephemeral <prompt>
  antigravity.ts        -- runs agy run <prompt> via execa
  index.ts              -- routes by ProviderName; re-exports ProviderName from schema
  utils.ts              -- shared toFailureResult helper
src/cli.ts              -- commander CLI, one subcommand: delegate
test/delegate.test.ts   -- unit tests; providers/index.js is vi.mock'd (no real subprocess)
```

Data flow: `cli.ts` parses args → `delegate.ts` validates with zod → `providers/index.ts` routes to the right provider → result bubbles back up.

## Key decisions

- `claude.ts` strips `ANTHROPIC_API_KEY` (`extendEnv: false`) so `claude` uses OAuth plan credits.
- `codex.ts` strips `OPENAI_API_KEY` (`extendEnv: false`) for the same reason; writes output to a tmp file via `--output-last-message` then cleans up in `finally`.
- `ProviderName` is derived from the zod enum in `schema.ts` (`DelegateInput["provider"]`) so adding a provider only requires updating the enum + switch.
- Tests mock `../src/providers/index.js` entirely -- no real subprocess in unit tests.
- `cli.ts` strips a leading `--` from `process.argv[2]` to handle pnpm's arg passthrough quirk.
