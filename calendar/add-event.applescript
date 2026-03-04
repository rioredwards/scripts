on run argv
	if (count of argv) < 3 then
		error "Usage: osascript add-event.applescript <title> <start> <end> [calendar] [location] [notes]"
	end if
	
	set eventTitle to item 1 of argv
	set startText to item 2 of argv
	set endText to item 3 of argv
	set targetCalendar to ""
	set eventLocation to ""
	set eventNotes to ""
	
	if (count of argv) ≥ 4 then set targetCalendar to item 4 of argv
	if (count of argv) ≥ 5 then set eventLocation to item 5 of argv
	if (count of argv) ≥ 6 then set eventNotes to item 6 of argv
	
	set startDate to date startText
	set endDate to date endText
	if endDate ≤ startDate then error "End must be after start"
	
	tell application "Calendar"
		if targetCalendar is "" then
			set cal to first calendar
		else
			set calList to (every calendar whose name is targetCalendar)
			if (count of calList) = 0 then error "Calendar not found: " & targetCalendar
			set cal to item 1 of calList
		end if
		
		tell cal
			set newEvent to make new event with properties {summary:eventTitle, start date:startDate, end date:endDate}
			if eventLocation is not "" then set location of newEvent to eventLocation
			if eventNotes is not "" then set description of newEvent to eventNotes
		end tell
		
		return "Created: " & eventTitle & " | " & ((start date of newEvent) as text) & " -> " & ((end date of newEvent) as text) & " | " & (name of cal)
	end tell
end run
