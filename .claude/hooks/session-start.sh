#!/usr/bin/env bash
# Preflight check: fires on user prompt submit. Nudges the user to run /setup
# if the project isn't configured. Uses observable state (git hooks path,
# CLAUDE.md) as the "is setup" signal — no sentinel file, and no fallible
# write to .claude/*.
#
# Emits the nudge at most once per Claude session by keying the marker on
# session_id (from the hook JSON input), NOT the bash PID ($$). Prior
# implementations used $$ which is fresh per hook invocation — making the
# "one nudge per session" promise false and firing on every prompt.

set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

input=$(cat 2>/dev/null || echo '{}')
session_id_raw=$(json_extract_string "session_id" "$input")
session_id=$(sanitize_session_id "${session_id_raw:-unknown}")
state_dir=$(session_state_dir "$session_id")
marker="$state_dir/preflight-nudged"

# Already nudged this session? Don't spam.
if [ -f "$marker" ]; then
  exit 0
fi

# Derive "is setup" from observable state.
hooks_path=$(git config core.hooksPath 2>/dev/null || echo "")
has_claude_md="no"
[ -f "$CLAUDE_PROJECT_DIR/CLAUDE.md" ] && has_claude_md="yes"

if [ "$hooks_path" = ".githooks" ] && [ "$has_claude_md" = "yes" ]; then
  # Project is configured. Silent; no need to mark.
  exit 0
fi

# Something's off — build the nudge list, emit once, mark.
nudges=""
if [ "$hooks_path" != ".githooks" ]; then
  nudges="${nudges}Git hooks not configured. "
fi
if [ ! -f "CLAUDE.md" ] && [ -f "CLAUDE.md.template" ]; then
  nudges="${nudges}CLAUDE.md.template found but not activated. "
fi

if [ -z "$nudges" ]; then
  exit 0
fi

touch "$marker" 2>/dev/null || true

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROJECT SETUP NEEDED: %sTell the user to run /setup to configure this project before doing any work."}}\n' "$nudges"
