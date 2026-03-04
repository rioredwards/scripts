on run argv
	set targetList to ""
	set limitCount to 25
	if (count of argv) ≥ 1 then set targetList to item 1 of argv
	if (count of argv) ≥ 2 then set limitCount to (item 2 of argv as integer)
	if limitCount < 1 then set limitCount to 1
	
	with timeout of 120 seconds
		tell application "Reminders"
			if targetList is not "" then
				set listMatches to (every list whose name is targetList)
				if (count of listMatches) = 0 then error "List not found: " & targetList
				set listSet to listMatches
			else
				set listSet to lists
			end if
			
			set outputLines to {}
			set n to 0
			repeat with l in listSet
				set rems to every reminder of l
				repeat with r in rems
					if completed of r is false then
						set n to n + 1
						if n > limitCount then exit repeat
						set dueOut to "(no due date)"
						if due date of r is not missing value then set dueOut to ((due date of r) as text)
						set end of outputLines to ((name of r) & " | " & dueOut & " | " & (name of l))
					end if
				end repeat
				if n > limitCount then exit repeat
			end repeat
		end tell
	end timeout
	
	if (count of outputLines) = 0 then
		return "No open reminders"
	else
		set AppleScript's text item delimiters to linefeed
		set joinedText to outputLines as text
		set AppleScript's text item delimiters to ""
		return joinedText
	end if
end run
