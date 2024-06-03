#!/bin/bash
# Change the background of iTerm2 to a random image from a directory
osascript -e 'tell application "iTerm"
	set imageDirectory to "/Users/rioedwards/Pictures/iterm_bg_photos/"
	set images to (list folder (imageDirectory) without invisibles)
	set image to some item of images
	tell current session of current window
		set background image to imageDirectory & image
	end tell
end tell'
