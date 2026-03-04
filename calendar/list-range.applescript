on run argv
	set daysAhead to 7
	set targetCalendar to ""
	if (count of argv) ≥ 1 then set daysAhead to (item 1 of argv as integer)
	if (count of argv) ≥ 2 then set targetCalendar to item 2 of argv
	
	tell application "Calendar"
		set startDate to current date
		set endDate to startDate + (daysAhead * 24 * 60 * 60)
		
		if targetCalendar is not "" then
			set calList to (every calendar whose name is targetCalendar)
			if (count of calList) = 0 then error "Calendar not found: " & targetCalendar
		else
			set calList to calendars
		end if
		
		set outputLines to {}
		repeat with cal in calList
			set evts to (every event of cal whose start date ≥ startDate and start date ≤ endDate)
			repeat with e in evts
				set lineText to (name of e) & " | " & ((start date of e) as text) & " -> " & ((end date of e) as text) & " | " & (name of cal)
				set end of outputLines to lineText
			end repeat
		end repeat
	end tell
	
	if (count of outputLines) = 0 then
		return "No events in range"
	else
		set AppleScript's text item delimiters to linefeed
		set joinedText to outputLines as text
		set AppleScript's text item delimiters to ""
		return joinedText
	end if
end run
