# Calendar AppleScripts

Simple Apple Calendar helpers for local automation.

## Scripts

- `list-today.applescript` — list today's events (`[calendarName]` optional)
- `list-range.applescript` — list upcoming events (`[daysAhead] [calendarName]` optional)
- `add-event.applescript` — create an event

## Usage

```bash
# List today's events across all calendars
osascript ~/scripts/calendar/list-today.applescript

# List today's events from one calendar
osascript ~/scripts/calendar/list-today.applescript "Calendar"

# List next 7 days
osascript ~/scripts/calendar/list-range.applescript 7

# Add event (date strings should be parseable by macOS, e.g. "3/4/2026 2:00 PM")
osascript ~/scripts/calendar/add-event.applescript \
  "Deep work" \
  "3/4/2026 2:00 PM" \
  "3/4/2026 3:30 PM" \
  "Calendar" \
  "Home Office" \
  "Focus block"
```

## Notes

- First run may prompt Calendar permissions for Terminal/OpenClaw.
- If you prefer, these can be wrapped in Shortcuts later for cleaner parameter parsing.
