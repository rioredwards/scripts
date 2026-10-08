# scripts

**Class:** `personal`

## Stage & appetite

- **Stage: live, daily-use personal tooling.** Hooks and scripts here run on every agent turn on both Macs.
- **P1** a hook or script breaks the day-to-day. **P2** friction hit daily. **P3** nice-to-have.
- Appetite per issue: one session. Bigger than that gets split.

## Tests

`sh tests/run-all.sh` runs every test (shell, Python, rules validation) and exits non-zero on any failure. Run it after any hook or script change. Add new tests as `tests/<name>-test.sh` so the runner picks them up.

## Routing

| Task | Read first |
| --- | --- |
| Editing a hook or hook rule | `hooks/rules/README.md` |
| Running or adding tests | `tests/run-all.sh` |
