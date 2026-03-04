on run argv
	set targetCalendar to ""
	if (count of argv) ≥ 1 then set targetCalendar to item 1 of argv
	
	tell application "Calendar"
		set nowDate to current date
		set startOfDay to nowDate
		set time of startOfDay to 0
		set endOfDay to startOfDay + (24 * 60 * 60)
		
		if targetCalendar is not "" then
			set calList to (every calendar whose name is targetCalendar)
			if (count of calList) = 0 then error "Calendar not found: " & targetCalendar
		else
			set calList to calendars
		end if
		
		set outputLines to {}
		repeat with cal in calList
			set evts to (every event of cal whose start date ≥ startOfDay and start date < endOfDay)
			repeat with e in evts
				set lineText to (name of e) & " | " & ((start date of e) as text) & " -> " & ((end date of e) as text) & " | " & (name of cal)
				set end of outputLines to lineText
			end repeat
		end repeat
	end tell
	
	if (count of outputLines) = 0 then
		return "No events today"
	else
		set AppleScript's text item delimiters to linefeed
		set joinedText to outputLines as text
		set AppleScript's text item delimiters to ""
		return joinedText
	end if
end run
