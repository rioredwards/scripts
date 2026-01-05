#!/bin/bash

# opens the keyboard-shortcut-script-generator chatgpt app in chrome

# Function to check if Hammerspoon is running
is_hammerspoon_running() {
    pgrep -f "Hammerspoon" > /dev/null 2>&1
}

# Function to show warning overlay using Hammerspoon
show_warning_overlay() {
    if is_hammerspoon_running; then
        echo "Hammerspoon is running, showing warning overlay..."
        
        # Use direct hs.alert call (the working method)
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.alert.closeAll(); hs.alert.show(\"⚠️  CONSOLE SCRIPT ACTIVE - DO NOT TOUCH ANYTHING\", {atScreenEdge = 2, fadeInDuration = 0.5, displayDuration = 0, textFont = \"Arial Bold\", textSize = 18, radius = 10, strokeColor = {red = 1, green = 0.5, blue = 0, alpha = 1}, strokeWidth = 2, fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95}})"' > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✅ Warning overlay displayed successfully"
        else
            echo "❌ Hammerspoon overlay failed, using native notification"
            show_native_notification "⚠️  Console Script Active" "Please do not touch your mouse or keyboard"
        fi
    else
        echo "Hammerspoon is not running, using native notification"
        show_native_notification "⚠️  Console Script Active" "Please do not touch your mouse or keyboard"
    fi
}

# Function to show native macOS notification
show_native_notification() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\""
}


# Function to hide warning overlay
hide_warning_overlay() {
    if is_hammerspoon_running; then
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.alert.closeAll()"' > /dev/null 2>&1
        echo "✅ Warning overlay hidden"
    fi
}

# Function to show completion message
show_completion_message() {
    if is_hammerspoon_running; then
        osascript -e 'tell application "Hammerspoon" to execute lua code "hs.alert.show(\"✅ Console setup completed!\", {atScreenEdge = 2, fadeInDuration = 0.5, displayDuration = 3, textFont = \"Arial Bold\", textSize = 16, radius = 8, strokeColor = {red = 0, green = 0.8, blue = 0, alpha = 1}, strokeWidth = 2, fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95}})"' > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✅ Completion message displayed via Hammerspoon"
        else
            echo "❌ Hammerspoon completion message failed, using native notification"
            show_native_notification "✅ Console Setup Complete" "Console app has been configured for AppLogger monitoring"
        fi
    else
        show_native_notification "✅ Console Setup Complete" "Console app has been configured for AppLogger monitoring"
    fi
}


# Set up logging
# LOG_FILE="/tmp/add_shortcuts_debug.log"
# echo "$(date): Starting add_shortcuts_from_screenshot.sh" > "$LOG_FILE"

# Function to log messages
log_message() {
    echo "$(date): $1"
}

log_message "Script started"

# Show warning overlay
show_warning_overlay

# wait for user confirmation after screenshot is taken
log_message "Waiting for user confirmation to continue"
osascript -e 'display dialog "Load clipboard with a screenshot of keyboard shortcuts\n\nHint:\n⌘⇧4 - Take screenshot\n⌥⌃space - search screenshots" buttons {"OK", "Cancel"} default button "OK"'
if [ $? -ne 0 ]; then
    # User cancelled, exit early
    log_message "User cancelled, exiting"
    exit 0
fi

log_message "User confirmed, proceeding with script"

# open chrome in background, then focus on it, then open the link
log_message "Opening Chrome with ChatGPT app"
open -a "Google Chrome"
log_message "Waiting 3 seconds for Chrome to open"
sleep 1
log_message "Focusing on Chrome"
osascript -e 'tell application "Google Chrome" to activate'
log_message "Waiting 1 second for Chrome to be focused"
sleep 1
log_message "Opening ChatGPT app"
osascript -e 'tell application "Google Chrome" to open location "https://chatgpt.com/g/g-p-687da160df4481919a1b23c3f2eb3f60-keyboard-shortcut-script-generator/project"'
log_message "Waiting 2 seconds for ChatGPT app to open"
sleep 2

# paste the screenshot into the chatgpt app
log_message "Pasting screenshot into ChatGPT app (Cmd+V)"
osascript -e 'tell application "System Events" to keystroke "v" using command down'

# wait for the screenshot to be pasted
log_message "Waiting 1 seconds for screenshot to be pasted"
sleep 1

# wait for user confirmation that the prompt is ready to be submitted
log_message "Waiting for user confirmation that prompt is ready to be submitted"
osascript -e 'display dialog "Submit this screenshot?" buttons {"OK", "Cancel"} default button "OK"'
if [ $? -ne 0 ]; then
    # User cancelled, exit early
    log_message "User cancelled after pasting screenshot"
    exit 0
fi

# press enter to submit the screenshot
log_message "Pressing Enter to submit screenshot"
osascript -e 'tell application "System Events" to keystroke return'

# wait for user confirmation that the response is ready
log_message "Waiting for user confirmation that AI response is ready"
osascript -e 'display dialog "Wait for the response to complete, then press OK to copy it." buttons {"OK", "Cancel"} default button "OK"'
if [ $? -ne 0 ]; then
    # User cancelled, exit early
    log_message "User cancelled after submitting screenshot"
    exit 0
fi

# select the copy button for the response message (press shift + tab 5 times)
log_message "Navigating to copy button (Shift+Tab 8 times)"
osascript -e 'tell application "System Events" to repeat 8 times
    keystroke tab using shift down
end repeat'

# press enter to copy the response
log_message "Pressing Enter to copy the response"
osascript -e 'tell application "System Events" to keystroke return'

# wait for the clipboard to be updated
log_message "Waiting 1 second for clipboard to be updated"
sleep 1

# close the browser tab
log_message "Closing browser tab"
osascript -e 'tell application "System Events" to keystroke "w" using command down'

# Open iTerm for manual execution
log_message "Opening iTerm for manual script execution"
open -a "iTerm"

# wait for iTerm to open
log_message "Waiting 1 second for iTerm to open"
sleep 1

# create a new tab in iTerm using cmd+t
log_message "Creating a new tab in iTerm"
osascript -e 'tell application "iTerm" to activate'
osascript -e 'tell application "System Events" to keystroke "t" using command down'

# Just show an alert with hammerspoon that the script is done and the user can paste and run the script
log_message "Showing alert with hammerspoon that the script is done and the user can paste and run the script"
osascript -e 'tell application "Hammerspoon" to execute lua code "hs.alert.closeAll(); hs.alert.show(\"The script is done. You can paste and run the script in iTerm.\", {atScreenEdge = 2, fadeInDuration = 0.5, displayDuration = 0, textFont = \"Arial Bold\", textSize = 18, radius = 10, strokeColor = {red = 1, green = 0.5, blue = 0, alpha = 1}, strokeWidth = 2, fillColor = {red = 0.1, green = 0.1, blue = 0.1, alpha = 0.95}})"'

# wait for user confirmation that the script is done
log_message "Waiting for user confirmation that the script is done"
osascript -e 'display dialog "The script is done. You can paste and run the script in iTerm." buttons {"OK", "Cancel"} default button "OK"'


# paste the script into iTerm
# log_message "Pasting script into iTerm"
# osascript -e 'tell application "System Events" to keystroke "v" using command down'


# press enter to run the script
# log_message "Pressing Enter to run the script"
# osascript -e 'tell application "System Events" to keystroke return'
