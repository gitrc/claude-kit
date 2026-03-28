#!/usr/bin/env bash
# Cross-platform notification when Claude needs attention
# Fires on Notification events (permission prompts, idle, etc.)

if [[ "$(uname)" == "Darwin" ]]; then
  osascript -e 'display notification "Claude Code needs your attention" with title "Claude Code" sound name "Ping"' 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "Claude Code" "Claude Code needs your attention" 2>/dev/null || true
fi
