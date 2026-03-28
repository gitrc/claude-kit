#!/usr/bin/env bash
# Preflight check: fires on first user prompt, checks if /setup has been run.
# Uses a marker file so it only fires once per session.
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

# Only run once — check for session marker
marker="/tmp/claude-preflight-$$"
if [ -f "$marker" ] 2>/dev/null; then
  exit 0
fi

# Try to get session-scoped marker using CLAUDE env if available
# Fall back to checking .initialized file
if [ -f "$CLAUDE_PROJECT_DIR/.claude/.initialized" ]; then
  # Project already set up — check if anything drifted
  hooks_path=$(git config core.hooksPath 2>/dev/null || echo "")
  if [ "$hooks_path" = ".githooks" ] && [ -f "$CLAUDE_PROJECT_DIR/CLAUDE.md" ]; then
    touch "$marker" 2>/dev/null
    exit 0
  fi
fi

touch "$marker" 2>/dev/null

nudges=""

# Check git hooks
hooks_path=$(git config core.hooksPath 2>/dev/null || echo "")
if [ "$hooks_path" != ".githooks" ]; then
  nudges="${nudges}Git hooks not configured. "
fi

# Check CLAUDE.md
if [ ! -f "CLAUDE.md" ] && [ -f "CLAUDE.md.template" ]; then
  nudges="${nudges}CLAUDE.md.template found but not activated. "
fi

if [ -z "$nudges" ]; then
  exit 0
fi

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"PROJECT SETUP NEEDED: ${nudges}Tell the user to run /setup to configure this project before doing any work.\"}}"
