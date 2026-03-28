#!/usr/bin/env bash
# Lightweight context monitor: tracks turns and transcript size.
# Nudges user to /compact when context is getting large.
# Cost: one file read + one counter increment per tool call. Zero tokens until threshold.
set -euo pipefail

input=$(cat)

# Safe JSON extraction — no eval, no python3 dependency
extract_json_string() {
  echo "$input" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

session_id=$(extract_json_string "session_id")
session_id="${session_id:-unknown}"
transcript_path=$(extract_json_string "transcript_path")

counter_file="/tmp/claude-turns-${session_id}"

# Increment turn counter
if [ -f "$counter_file" ]; then
  turns=$(( $(cat "$counter_file") + 1 ))
else
  turns=1
fi
echo "$turns" > "$counter_file"

# Only check every 20 turns to minimize overhead
if (( turns % 20 != 0 )); then
  exit 0
fi

# Check transcript size if path available
transcript_kb=0
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  transcript_bytes=$(wc -c < "$transcript_path" 2>/dev/null || echo 0)
  transcript_kb=$(( transcript_bytes / 1024 ))
fi

# Nudge thresholds
if (( transcript_kb > 800 )); then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "CONTEXT MONITOR: Session is at $turns tool calls, transcript ~${transcript_kb}KB. Context is getting heavy. Recommend running /compact soon to maintain response quality. Remind the user."
  }
}
EOF
elif (( turns >= 100 )) && (( turns % 40 == 0 )); then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "CONTEXT MONITOR: $turns tool calls this session. If responses feel degraded, suggest /compact to the user."
  }
}
EOF
fi

exit 0
