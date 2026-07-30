# Scopes — scripts

The **scope** half of `type/scope`, used for both commit subjects and the
`SUBSYSTEM` field of agent reports. Types are global and live in
`~/.dotfiles/.agents/commit-types.md`.

A scope names an area of the product someone could care about. If a name here
only makes sense to whoever has the file open, it is the wrong name.

Machine-read by `response-contract`. Parser takes the backticked name at the
start of each bullet — keep that shape.

- `hooks` — agent lifecycle hooks and the toggles that arm them.
- `routing` — handing a prompt to another agent CLI and getting it back.
- `notify` — turn-end notices: phone texts, notes, summaries.
- `audio` — speech in and out: TTS voices, recap audio, sidecars.
- `mac` — driving the machine: dialogs, clicks, screenshots, Shortcuts.
- `contract` — the response contract and its vocabulary.
- `portability` — surviving two Macs: home paths, symlinks, host guards.

## What changed from raw history

Seeded from 117 commits by `scope-scan`, then curated. History named individual
scripts — `agent-router`, `send-to-chatgpt`, `grok-tts`, `cleanshot`, `sesh` —
which reads fine in a commit and badly in a report: it says which file was open,
not what got better. The names above are jobs instead of filenames.
`agent-router` and `send-to-chatgpt` both became `routing`; `grok-tts` and
`audio-note-to-file` both became `audio`.

`scripts` was dropped outright. A scope equal to the repo name carries no
information — every commit here is in `scripts`.

Run `scope-scan` any time to see drift in both directions.
