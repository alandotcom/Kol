#!/bin/bash
# Reveal <private> data in unified logs for com.alandotcom.Kol.
# One-time setup — persists across reboots until the plist is removed.
# See: man 5 os_log, Apple's "Customizing Logging Behavior While Debugging"
set -euo pipefail
sudo mkdir -p /Library/Preferences/Logging/Subsystems/
sudo cp "$(dirname "$0")/com.alandotcom.Kol.plist" /Library/Preferences/Logging/Subsystems/
sudo chmod 644 /Library/Preferences/Logging/Subsystems/com.alandotcom.Kol.plist
echo "Debug logging enabled for com.alandotcom.Kol — new log entries will show private data."
