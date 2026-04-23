#!/usr/bin/env bash
# Context monitor: tracks tool calls per session and transcript size.
# Nudges the user to /compact when context is getting heavy.
# Cost: one file read + one counter increment per tool call.
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

input=$(cat)
session_id_raw=$(json_extract_string "session_id" "$input")
session_id=$(sanitize_session_id "${session_id_raw:-unknown}")
transcript_path=$(json_extract_string "transcript_path" "$input")
state_dir=$(session_state_dir "$session_id")
counter_file="$state_dir/turns"

# Increment turn counter. Defend against corrupted counter files (non-numeric)
# by resetting silently rather than exploding under set -e.
turns=1
if [ -f "$counter_file" ]; then
  prev=$(cat "$counter_file" 2>/dev/null || echo "")
  if [[ "$prev" =~ ^[0-9]+$ ]]; then
    turns=$(( prev + 1 ))
  fi
fi
echo "$turns" > "$counter_file"

# Only check every 20 turns to minimize overhead.
if (( turns % 20 != 0 )); then
  exit 0
fi

transcript_kb=0
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  transcript_bytes=$(wc -c < "$transcript_path" 2>/dev/null || echo 0)
  transcript_kb=$(( transcript_bytes / 1024 ))
fi

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
