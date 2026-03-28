#!/usr/bin/env bash
# StopFailure handler: notifies user when API errors kill a response.
# Cannot block (output ignored by Claude Code) — notification only.
set -euo pipefail

input=$(cat)

# Safe JSON extraction — no python3 dependency
error_type=$(echo "$input" | grep -o '"matcher"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"matcher"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
error_type="${error_type:-unknown}"

# Map error types to human-readable messages
case "$error_type" in
  rate_limit)
    msg="Rate limited. Wait a moment and retry."
    ;;
  authentication_failed)
    msg="Auth failed. Check your API key or run: claude auth"
    ;;
  billing_error)
    msg="Billing error. Check your account at console.anthropic.com"
    ;;
  server_error)
    msg="Anthropic server error. Transient — retry in a few seconds."
    ;;
  max_output_tokens)
    msg="Hit max output tokens. Response was truncated — send a follow-up to continue."
    ;;
  invalid_request)
    msg="Invalid request error. This may indicate a bug — check the transcript."
    ;;
  *)
    msg="API error ($error_type). Check connection and retry."
    ;;
esac

# Cross-platform notification
if [[ "$(uname)" == "Darwin" ]]; then
  osascript -e "display notification \"$msg\" with title \"Claude Code Error\" sound name \"Basso\"" 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "Claude Code Error" "$msg" 2>/dev/null || true
fi

# Log for debugging (project-scoped)
log_dir="${CLAUDE_PROJECT_DIR:-.}/.claude"
echo "$(date -Iseconds 2>/dev/null || date) StopFailure: $error_type — $msg" >> "$log_dir/errors.log" 2>/dev/null || true

exit 0
