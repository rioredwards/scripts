# AGENTS.md

Use this file as repo front door. Keep it short. Read `CLAUDE.md` for fuller architecture notes.

## Repo shape

- `src/cli.ts`: CLI entrypoint and command wiring
- `src/schema.ts`: provider enum, model lists, defaults, zod input schema
- `src/delegate.ts`: validation to provider routing boundary
- `src/providers/*.ts`: one wrapper per external agent CLI
- `test/*.test.ts`: unit tests with subprocesses mocked

## Rules

- Keep provider logic thin. Repo exists to validate input and shell out, not to reimplement provider SDK behavior.
- When adding provider, update `src/schema.ts`, `src/providers/index.ts`, provider wrapper, and tests in `test/`.
- Keep tests mock-based. Do not add tests that require real `claude`, `codex`, `agy`, `opencode`, or `cursor` binaries.
- If user-facing CLI commands or provider behavior change, update `README.md` and `CLAUDE.md` in same pass.

## Validation

- `pnpm test`
- `pnpm typecheck`

## Doc ownership

- `README.md`: human quick start and command surface
- `AGENTS.md`: agent routing, guardrails, validation
- `CLAUDE.md`: deeper architecture and Claude-specific notes
