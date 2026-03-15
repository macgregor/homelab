#!/bin/bash
# Ensure Chrome/Chromium is running with remote debugging enabled
# Used by the chrome-devtools MCP server hook

CHROME_DEBUG_PORT=9222
CHROME_PROFILE_DIR="$HOME/.chrome-debug-profile"

# Check if already running
if curl -s http://127.0.0.1:$CHROME_DEBUG_PORT/json/version >/dev/null 2>&1; then
    exit 0
fi

# Find browser binary
BROWSER=$(command -v chromium-browser || command -v chromium || command -v google-chrome || command -v google-chrome-stable)
if [ -z "$BROWSER" ]; then
    echo "No Chrome/Chromium browser found" >&2
    exit 1
fi

# Start with remote debugging
"$BROWSER" \
    --remote-debugging-port=$CHROME_DEBUG_PORT \
    --user-data-dir="$CHROME_PROFILE_DIR" \
    >/dev/null 2>&1 &

sleep 2

if curl -s http://127.0.0.1:$CHROME_DEBUG_PORT/json/version >/dev/null 2>&1; then
    exit 0
else
    echo "Failed to start browser with remote debugging" >&2
    exit 1
fi
