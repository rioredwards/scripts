on run argv
	set targetList to ""
	if (count of argv) ≥ 1 then set targetList to item 1 of argv
	
	with timeout of 120 seconds
		tell application "Reminders"
			set nowDate to current date
			set startOfDay to nowDate
			set time of startOfDay to 0
			set endOfDay to startOfDay + (24 * 60 * 60)
			
			if targetList is not "" then
				set listMatches to (every list whose name is targetList)
				if (count of listMatches) = 0 then error "List not found: " & targetList
				set listSet to listMatches
			else
				set listSet to lists
			end if
			
			set outputLines to {}
			repeat with l in listSet
				set rems to every reminder of l
				repeat with r in rems
					if completed of r is false then
						if due date of r is not missing value then
							set dueDateVal to due date of r
							if dueDateVal ≥ startOfDay and dueDateVal < endOfDay then
								set dueText to (dueDateVal as text)
								set bodyText to ""
								if body of r is not missing value and body of r is not "" then set bodyText to " | " & body of r
								set end of outputLines to ((name of r) & " | " & dueText & " | " & (name of l) & bodyText)
							end if
						end if
					end if
				end repeat
			end repeat
		end tell
	end timeout
	
	if (count of outputLines) = 0 then
		return "No reminders due today"
	else
		set AppleScript's text item delimiters to linefeed
		set joinedText to outputLines as text
		set AppleScript's text item delimiters to ""
		return joinedText
	end if
end run
