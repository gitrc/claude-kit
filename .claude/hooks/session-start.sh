#!/usr/bin/env bash
# Preflight check: fires on user prompt submit, nudges the user to run /setup
# if the project isn't configured. Uses observable state (git hooks path,
# CLAUDE.md) as the "is setup" signal — no sentinel file (writes to .claude/
# are blocked by the harness, so a sentinel can never be created).
#
# Only emits one nudge per shell-parent session via a PID-scoped marker.
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

# Per-session single-shot nudge
marker="/tmp/claude-preflight-$$"
if [ -f "$marker" ] 2>/dev/null; then
  exit 0
fi

# Derive "is setup" from observable state — if both signals look good, done.
hooks_path=$(git config core.hooksPath 2>/dev/null || echo "")
has_claude_md="no"
[ -f "$CLAUDE_PROJECT_DIR/CLAUDE.md" ] && has_claude_md="yes"

if [ "$hooks_path" = ".githooks" ] && [ "$has_claude_md" = "yes" ]; then
  touch "$marker" 2>/dev/null
  exit 0
fi

# Something's not configured — build the nudge list
touch "$marker" 2>/dev/null

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

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"PROJECT SETUP NEEDED: ${nudges}Tell the user to run /setup to configure this project before doing any work.\"}}"
