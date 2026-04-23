#!/usr/bin/env bash
# update-kit.sh — Re-run inject.sh against the current project to pull in the
# latest claude-kit hooks, skills, and template rules.
#
# Must be run from within an already-injected project (one that has
# .claude/KIT_VERSION from a prior inject.sh run).
#
# Usage:
#   /path/to/claude-kit/update-kit.sh        # updates the current dir
#   /path/to/claude-kit/update-kit.sh /some/project
#
# Behavior is identical to inject.sh in "update mode" — settings.json is
# merged (not clobbered), CLAUDE.md is never touched, and user customizations
# in those two files are preserved.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")"

if [ ! -d "$TARGET_DIR/.claude" ]; then
  echo "ERROR: $TARGET_DIR does not appear to be a claude-kit project (.claude/ missing)." >&2
  echo "Use inject.sh for a fresh install instead." >&2
  exit 1
fi

exec "$SCRIPT_DIR/inject.sh" "$TARGET_DIR"
