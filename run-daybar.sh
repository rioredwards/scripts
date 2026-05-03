#!/bin/bash
set -euo pipefail

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Run DayBar
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author rio_edwards
# @raycast.authorURL https://raycast.com/rio_edwards

ROOT="/Users/rioredwards/dev/DayBar"
DERIVED="/tmp/DayBar-run-$(whoami)"

xcodebuild \
  -project "$ROOT/DayBar.xcodeproj" \
  -scheme DayBar \
  -destination 'platform=macOS' \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  build

open "$DERIVED/Build/Products/Debug/DayBar.app"
