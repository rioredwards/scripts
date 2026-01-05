#!/bin/bash

# Console App Workflow Script
# This script manages the Console app state and configures it for AppLogger monitoring

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

# Function to check if accessibility permissions are granted
check_accessibility_permissions() {
    osascript -e 'tell application "System Events" to keystroke ""' > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Accessibility permissions are required for this script to work."
        echo "Please grant accessibility permissions to Terminal/your terminal app:"
        echo "1. Go to System Preferences > Security & Privacy > Privacy > Accessibility"
        echo "2. Click the lock icon to make changes"
        echo "3. Add Terminal (or your terminal app) to the list"
        echo "4. Check the box next to Terminal"
        echo "5. Restart your terminal and run this script again"
        exit 1
    fi
}

# Function to check if Console app is running
is_console_running() {
    pgrep -f "Console" > /dev/null 2>&1
}

# Function to close Console app
close_console() {
    osascript -e 'tell application "Console" to quit'
    sleep 1
}

# Function to open Console app
open_console() {
    open -a Console
    sleep 2
}

# Function to resize Console to bottom half using Raycast
resize_console_bottom_half() {
    open -g raycast://extensions/raycast/window-management/bottom-half
    sleep 1
}

# Function to press down arrow
press_down_arrow() {
    osascript -e 'tell application "System Events" to key code 125'
    sleep 0.5
}

# Function to activate Action->AppLogger menu item
activate_applogger() {
    osascript -e 'tell application "System Events" to tell process "Console" to click menu item "AppLogger" of menu "Action" of menu bar 1'
    sleep 0.5
}

# Function to activate Action->Start Streaming menu item
start_streaming() {
    osascript -e 'tell application "System Events" to tell process "Console" to click menu item "Start Streaming" of menu "Action" of menu bar 1'
    sleep 0.5
}

# Function to activate Action->Search menu item
activate_search() {
    osascript -e 'tell application "System Events" to tell process "Console" to click menu item "Search" of menu "Action" of menu bar 1'
    sleep 0.5
}

# Main execution
echo "Starting Console app workflow..."

# Show warning overlay
echo "Showing warning overlay..."
show_warning_overlay

# Check accessibility permissions first
echo "Checking accessibility permissions..."
check_accessibility_permissions
echo "✅ Accessibility permissions confirmed"

# Step 1: Check if Console is open
if is_console_running; then
    echo "Console app is running. Closing it..."
    close_console
else
    echo "Console app is not running."
fi

# Step 3: Open Console app
echo "Opening Console app..."
open_console

# Step 4: Resize to bottom half using Raycast
echo "Resizing Console to bottom half of screen..."
# resize_console_bottom_half # Disabled for now

# Step 5: Press down arrow
echo "Pressing down arrow..."
press_down_arrow

# Step 6: Activate Action->AppLogger
echo "Activating AppLogger menu item..."
activate_applogger

# Step 7: Activate Action->Start Streaming
echo "Starting streaming..."
start_streaming

# Step 8: Activate Action->Search
echo "Activating search..."
activate_search

# Hide warning overlay and show completion message
echo "Hiding warning overlay..."
hide_warning_overlay

# Show completion message
show_completion_message

echo "Console app workflow completed!"
