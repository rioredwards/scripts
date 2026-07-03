#!/bin/bash
# Change the background of iTerm2 to a random image from a directory
osascript -e 'tell application "iTerm2"
  tell current session of current window
    set background image to "/Users/rioedwards/Pictures/Desktop Photos/Desktop_Photo_1.jpg" 
  end tell
end tell'
