# Notion Hotkey CLI

A simple CLI tool to add hotkeys to a Notion database.

## Setup

1. Create a `.env` file with your Notion credentials:
```
NOTION_TOKEN=your_notion_api_key
NOTION_DATABASE_ID=your_database_id
```

2. Install dependencies:
```bash
npm install
```

3. (Optional) Install globally to use from anywhere:
```bash
sudo npm install -g .
```

**Note**: When installed globally, the script will automatically find the `.env` file in the project directory, so you can run it from anywhere on your system.

## Usage

### Add a single hotkey

```bash
# Using the script directly
node index.cjs add -a "VS Code" -c "Cmd+Shift+P" -n "Command Palette"

# Or if installed globally
notion-hotkey-cli add -a "VS Code" -c "Cmd+Shift+P" -n "Command Palette"
```

Or using long options:
```bash
node index.cjs add --app "VS Code" --command "Cmd+Shift+P" --name "Command Palette"
```

### Add multiple hotkeys

#### From a JSON file

Create a JSON file with your hotkeys (e.g., `hotkeys.json`):
```json
[
  {
    "app": "VS Code",
    "command": "⌘⇧P",
    "name": "Command Palette"
  },
  {
    "app": "Chrome",
    "command": "⌘T",
    "name": "New Tab"
  }
]
```

Then run:
```bash
notion-hotkey-cli add-multiple --file hotkeys.json
```

#### From a JSON string

Pass JSON data directly as a command line argument:
```bash
notion-hotkey-cli add-multiple --json '[{"app":"VS Code","command":"⌘B","name":"Toggle Sidebar"},{"app":"VS Code","command":"⌘J","name":"Toggle Terminal"}]'
```

#### Single hotkey via add-multiple command

```bash
notion-hotkey-cli add-multiple -a "VS Code" -c "⌘P" -n "Quick Open"
```

## Available Commands

- `add` - Add a single hotkey
- `add-multiple` - Add multiple hotkeys from a JSON file or command line

## Requirements

- Node.js
- Notion API key
- Notion database ID

## Available apps:
- 🔍 Finder
- 📝 Notes
- 📸 TextSniper
- 🔨 Hammerspoon
- 🚀 Raycast
- 📸 Cleanshot
- 🔥 Vim
- 🍎Mac
- 💻iTerm
- 👾Git
- 🌞Chrome
- 🦕VSCode
- 🐧Linux
