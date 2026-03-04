# Reminders AppleScripts

Simple Apple Reminders helpers for local automation.

## Scripts

- `list-today.applescript` — list reminders due today (`[listName]` optional)
- `list-open.applescript` — list open reminders (`[listName] [limit]` optional)
- `add-reminder.applescript` — create a reminder

## Usage

```bash
# List reminders due today across all lists
osascript ~/scripts/reminders/list-today.applescript

# List reminders due today from one list
osascript ~/scripts/reminders/list-today.applescript "Reminders"

# List open reminders (first 25)
osascript ~/scripts/reminders/list-open.applescript

# List open reminders from one list, limit 10
osascript ~/scripts/reminders/list-open.applescript "Reminders" 10

# Add reminder without due date
osascript ~/scripts/reminders/add-reminder.applescript "Test reminder"

# Add reminder with due date/list/notes
osascript ~/scripts/reminders/add-reminder.applescript \
  "Submit expense report" \
  "3/4/2026 5:00 PM" \
  "Reminders" \
  "For February receipts"
```

## Notes

- First run may prompt Reminders permissions for Terminal/OpenClaw.
- Date text should be parseable by macOS (e.g. `3/4/2026 5:00 PM`).
