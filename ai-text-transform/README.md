# AI Text Transform (`aitt`)

A Unix-friendly CLI to transform text using AI. Built on top of Simon Willison's [`llm`](https://llm.datasette.io/).

## Setup

1. Install `llm`:
   ```bash
   brew install llm
   ```
2. (Optional) Install Anthropic support:
   ```bash
   llm install llm-anthropic
   llm keys set anthropic
   ```
3. Ensure this directory is in your `$PATH` or create symlinks to `aitt` in your `~/bin` or `~/.local/bin` directory.
   ```bash
   ln -s ~/scripts/ai-text-transform/aitt /usr/local/bin/aitt
   ln -s ~/scripts/ai-text-transform/aitt /usr/local/bin/ai-text-transform
   ```

## Usage

```bash
aitt condense < notes.txt
pbpaste | aitt summarize
aitt eli5 --file ./notes.md
aitt promptify --clipboard --copy
aitt custom "Turn this into a concise GitHub issue: ..."
aitt summarize --file meeting-notes.md --out summary.md
aitt --list
aitt --dry-run condense --file notes.md
```

## Adding Prompts

To add a new transform, simply create a new Markdown file in the `prompts/` directory. The filename (without `.md`) becomes the transform name.

For example, `prompts/translate-fr.md` allows you to run:
```bash
echo "Hello" | aitt translate-fr
```
