#!/usr/bin/env bash
# inject.sh — Inject the Claude Code development template into an existing project.
# Merges without clobbering. Safe to run multiple times (idempotent).
#
# Usage:
#   ./inject.sh <target-directory>
#   curl -sL <raw-url>/inject.sh | bash -s -- <target-directory>
#
# Or clone + inject:
#   npx degit your-username/coding-template /tmp/coding-template
#   /tmp/coding-template/inject.sh ~/projects/my-app

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Resolve template directory (where this script lives) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR"

# --- Parse args ---
TARGET_DIR="${1:-}"

if [ -z "$TARGET_DIR" ]; then
  echo -e "${RED}Usage: ./inject.sh <target-directory>${NC}"
  echo ""
  echo "  Examples:"
  echo "    ./inject.sh ~/projects/my-app"
  echo "    ./inject.sh ."
  exit 1
fi

# Resolve to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")"

if [ ! -d "$TARGET_DIR" ]; then
  echo -e "${YELLOW}Target directory does not exist: $TARGET_DIR${NC}"
  read -p "Create it? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    mkdir -p "$TARGET_DIR"
    echo -e "${GREEN}Created $TARGET_DIR${NC}"
  else
    echo "Aborted."
    exit 1
  fi
fi

echo ""
echo -e "${BOLD}${CYAN}  Claude Code Template — Inject${NC}"
echo -e "${DIM}  Template:  $TEMPLATE_DIR${NC}"
echo -e "${DIM}  Target:    $TARGET_DIR${NC}"
echo ""

# --- Safety check: don't inject into the template itself ---
if [ "$TEMPLATE_DIR" = "$TARGET_DIR" ]; then
  echo -e "${RED}ERROR: Target is the same as the template directory.${NC}"
  exit 1
fi

# --- Copy .claude/hooks/ (overwrite — template-managed) ---
echo -e "  ${GREEN}✓${NC} Copying .claude/hooks/"
mkdir -p "$TARGET_DIR/.claude/hooks"
cp "$TEMPLATE_DIR/.claude/hooks/"*.sh "$TARGET_DIR/.claude/hooks/"
chmod +x "$TARGET_DIR/.claude/hooks/"*.sh

# --- Copy .claude/skills/ (overwrite — template-managed) ---
echo -e "  ${GREEN}✓${NC} Copying .claude/skills/"
mkdir -p "$TARGET_DIR/.claude/skills"
cp -r "$TEMPLATE_DIR/.claude/skills/"* "$TARGET_DIR/.claude/skills/"

# --- Merge .claude/settings.json ---
if [ -f "$TARGET_DIR/.claude/settings.json" ]; then
  # Target has existing settings — check if it has hooks
  if grep -q '"hooks"' "$TARGET_DIR/.claude/settings.json" 2>/dev/null; then
    echo -e "  ${YELLOW}!${NC} .claude/settings.json exists with hooks — ${BOLD}backing up${NC} to settings.json.bak"
    cp "$TARGET_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json.bak"
  fi
  # Overwrite with template settings (hooks config is the template's job)
  cp "$TEMPLATE_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"
  echo -e "  ${GREEN}✓${NC} Updated .claude/settings.json (backup saved if existed)"
else
  cp "$TEMPLATE_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"
  echo -e "  ${GREEN}✓${NC} Created .claude/settings.json"
fi

# --- Copy .githooks/ ---
echo -e "  ${GREEN}✓${NC} Copying .githooks/"
mkdir -p "$TARGET_DIR/.githooks"
cp "$TEMPLATE_DIR/.githooks/"* "$TARGET_DIR/.githooks/"
chmod +x "$TARGET_DIR/.githooks/"*

# --- Copy CLAUDE.md.template ---
cp "$TEMPLATE_DIR/CLAUDE.md.template" "$TARGET_DIR/CLAUDE.md.template"
echo -e "  ${GREEN}✓${NC} Copied CLAUDE.md.template"

# --- Merge .gitignore ---
if [ -f "$TARGET_DIR/.gitignore" ]; then
  added=0
  while IFS= read -r line; do
    # Skip empty lines and comments for matching
    if [ -z "$line" ] || [[ "$line" == \#* ]]; then
      continue
    fi
    if ! grep -qxF "$line" "$TARGET_DIR/.gitignore" 2>/dev/null; then
      echo "$line" >> "$TARGET_DIR/.gitignore"
      added=$((added + 1))
    fi
  done < "$TEMPLATE_DIR/.gitignore"
  if [ $added -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Merged .gitignore ($added entries added)"
  else
    echo -e "  ${GREEN}✓${NC} .gitignore already up to date"
  fi
else
  cp "$TEMPLATE_DIR/.gitignore" "$TARGET_DIR/.gitignore"
  echo -e "  ${GREEN}✓${NC} Created .gitignore"
fi

# --- Skip list ---
echo ""
echo -e "  ${DIM}Skipped: .git/, settings.local.json, .initialized, errors.log${NC}"

# --- Done ---
echo ""
echo -e "${BOLD}${GREEN}  Done!${NC}"
echo ""
echo -e "  Next steps:"
echo -e "    ${CYAN}cd $TARGET_DIR${NC}"
echo -e "    ${CYAN}claude${NC}"
echo -e "    Then run ${BOLD}/setup${NC} to activate git hooks, install LSP plugins,"
echo -e "    and burn rules into memory."
echo ""
