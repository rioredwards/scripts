# Rio's Scripts

- [Chaining Raycast Commands](https://csswolf.com/how-to-chain-multiple-commands-in-raycast/)

- Available Scripts and how to run them:
- `notion-hotkey-cli` - This is a CLI tool that allows you to create a new hotkey in Notion. It's installed globally via npm. Usage: `notion-hotkey-cli add --app "Test App" --command "⟡A" --name "Test Command"`. Also can see availeble commands with `notion-hotkey-cli --help`.
- `sc` - Thin text-only proxy for registered Apple Shortcuts in `shortcut-helpers/`. Run `sc` to list aliases, `sc summarize-text "text to summarize"`, or `echo "text" | sc summarize-text`.
- `codex-note-on-turn` - Codex `notify` hook that summarizes the final Codex reply, copies it to the clipboard, and triggers the phone note Shortcut pipeline.
- `note-source-to-phone` - Source-agnostic version of the note hook. Accepts a file path, literal text, or stdin, then summarizes it, copies it to the clipboard, and triggers the phone note Shortcut pipeline.
- `sync-projects` - Repo sync dashboard and guided walkthrough for cross-machine handoff. Usage: `sync-projects scan --dry-run` or `sync-projects guide`. Narrow with `sync-projects scan --dry-run --project career` or inspect JSON with `sync-projects scan --dry-run --format json --pretty`.
- `agent-router` - Stable wrapper for `/Users/rioredwards/dev/agent-router/agent-router`. Usage: `agent-router guide`, `agent-router providers --verbose`, or `agent-router delegate "prompt"`.
