on run argv
	if (count of argv) < 1 then
		error "Usage: osascript add-reminder.applescript <title> [due] [list] [notes]"
	end if
	
	set reminderTitle to item 1 of argv
	set dueText to ""
	set targetList to ""
	set reminderNotes to ""
	
	if (count of argv) ≥ 2 then set dueText to item 2 of argv
	if (count of argv) ≥ 3 then set targetList to item 3 of argv
	if (count of argv) ≥ 4 then set reminderNotes to item 4 of argv
	
	tell application "Reminders"
		if targetList is "" then
			set targetListRef to default list
		else
			set listMatches to (every list whose name is targetList)
			if (count of listMatches) = 0 then error "List not found: " & targetList
			set targetListRef to item 1 of listMatches
		end if
		
		if dueText is "" then
			set newReminder to make new reminder at end of reminders of targetListRef with properties {name:reminderTitle}
		else
			set dueDateVal to date dueText
			set newReminder to make new reminder at end of reminders of targetListRef with properties {name:reminderTitle, due date:dueDateVal}
		end if
		
		if reminderNotes is not "" then set body of newReminder to reminderNotes
		
		set dueOut to "(no due date)"
		if due date of newReminder is not missing value then set dueOut to ((due date of newReminder) as text)
		
		return "Created: " & (name of newReminder) & " | " & dueOut & " | " & (name of targetListRef)
	end tell
end run
