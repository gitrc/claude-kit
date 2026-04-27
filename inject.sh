#!/usr/bin/env bash
# inject.sh — Inject the claude-kit development template into a project.
# Idempotent: safe to run multiple times. Merges without clobbering user state.
#
# Usage:
#   ./inject.sh <target-directory>
#
# Update semantics:
#   - Hooks and skills are OVERWRITTEN (template-managed).
#   - settings.json is MERGED (template hooks + preserved user keys).
#   - CLAUDE.md is NEVER touched. CLAUDE.md.template is refreshed.
#   - .gitignore entries are APPENDED if missing.
#   - A VERSION stamp is written to .claude/KIT_VERSION so users can tell
#     which template version the project is on and run update-kit.sh later.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR"
KIT_VERSION=$(cat "$TEMPLATE_DIR/VERSION" 2>/dev/null || echo "0.0.0")

# --- Parse args ---
CHECK_ONLY=0
TARGET_DIR=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      echo "Usage: ./inject.sh [--check] <target-directory>"
      echo ""
      echo "  --check    Show version comparison without modifying files."
      echo ""
      echo "  Examples:"
      echo "    ./inject.sh ~/projects/my-app           # fresh install or upgrade"
      echo "    ./inject.sh --check ~/projects/my-app   # show installed vs latest"
      echo "    ./inject.sh .                           # inject into current dir"
      exit 0
      ;;
    *) TARGET_DIR="$arg" ;;
  esac
done

if [ -z "$TARGET_DIR" ]; then
  echo -e "${RED}Usage: ./inject.sh [--check] <target-directory>${NC}"
  echo "  Run with --help for full options."
  exit 1
fi

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
echo -e "${BOLD}${CYAN}  claude-kit inject (v${KIT_VERSION})${NC}"
echo -e "${DIM}  Template:  $TEMPLATE_DIR${NC}"
echo -e "${DIM}  Target:    $TARGET_DIR${NC}"

# Detect if this is an update vs a fresh install
PRIOR_VERSION=""
if [ -f "$TARGET_DIR/.claude/KIT_VERSION" ]; then
  PRIOR_VERSION=$(cat "$TARGET_DIR/.claude/KIT_VERSION" 2>/dev/null || echo "")
  if [ "$PRIOR_VERSION" = "$KIT_VERSION" ]; then
    echo -e "${DIM}  Mode:      already at v${KIT_VERSION} (re-injecting)${NC}"
  else
    echo -e "${DIM}  Mode:      upgrade ${PRIOR_VERSION:-unknown} → ${KIT_VERSION}${NC}"
  fi
else
  echo -e "${DIM}  Mode:      fresh install${NC}"
fi
echo ""

# --check mode: show version comparison + relevant changelog entries, then exit
if [ $CHECK_ONLY -eq 1 ]; then
  if [ -z "$PRIOR_VERSION" ]; then
    echo "  No claude-kit installed at $TARGET_DIR. Run without --check to install."
  elif [ "$PRIOR_VERSION" = "$KIT_VERSION" ]; then
    echo "  Up to date. (v$KIT_VERSION)"
  else
    echo -e "  ${YELLOW}Update available:${NC} v${PRIOR_VERSION} → v${KIT_VERSION}"
    if [ -f "$TEMPLATE_DIR/CHANGELOG.md" ]; then
      echo ""
      echo "  Changes since your version (from CHANGELOG.md):"
      # Print sections newer than PRIOR_VERSION, stop at PRIOR_VERSION header
      awk -v prior="## $PRIOR_VERSION " '
        /^## [0-9]/ { if (started && index($0, prior) == 1) exit; started=1 }
        started { print "    " $0 }
      ' "$TEMPLATE_DIR/CHANGELOG.md" | head -60
    fi
    echo ""
    echo "  Run without --check to apply."
  fi
  exit 0
fi

if [ "$TEMPLATE_DIR" = "$TARGET_DIR" ]; then
  echo -e "${RED}ERROR: Target is the same as the template directory.${NC}"
  exit 1
fi

# --- Copy .claude/hooks/ (overwrite — template-managed) ---
echo -e "  ${GREEN}✓${NC} Copying .claude/hooks/ (including lib/ and tests/)"
mkdir -p "$TARGET_DIR/.claude/hooks/lib" "$TARGET_DIR/.claude/hooks/tests"
cp "$TEMPLATE_DIR/.claude/hooks/"*.sh "$TARGET_DIR/.claude/hooks/"
cp "$TEMPLATE_DIR/.claude/hooks/lib/"*.sh "$TARGET_DIR/.claude/hooks/lib/"
cp "$TEMPLATE_DIR/.claude/hooks/tests/"*.sh "$TARGET_DIR/.claude/hooks/tests/"
chmod +x "$TARGET_DIR/.claude/hooks/"*.sh "$TARGET_DIR/.claude/hooks/tests/"*.sh

# --- Copy .claude/skills/ (overwrite — template-managed) ---
echo -e "  ${GREEN}✓${NC} Copying .claude/skills/"
mkdir -p "$TARGET_DIR/.claude/skills"
cp -r "$TEMPLATE_DIR/.claude/skills/"* "$TARGET_DIR/.claude/skills/"

# --- Merge .claude/settings.json ---
#
# Merge semantics:
#   1. Template's "hooks" object is deep-merged on top of the user's —
#      per event, the template's hook array is appended to any user hooks
#      (so both run).
#   2. All other top-level keys (permissions, env, statusLine, ...) are
#      preserved verbatim from the user's settings. Template-only keys
#      at top level are added.
#   3. If the user has no settings.json, it's created from the template.
#   4. Before any write, the user's settings.json is backed up to
#      settings.json.bak (last-write-wins backup; overwritten by subsequent
#      inject runs, which is fine — it's about the immediate revert path).
if [ -f "$TARGET_DIR/.claude/settings.json" ]; then
  cp "$TARGET_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json.bak"
  # Python is assumed because /setup already requires it for memory-dir ops.
  if python3 - "$TARGET_DIR/.claude/settings.json" "$TEMPLATE_DIR/.claude/settings.json" <<'PY'
import json, sys
target_path, template_path = sys.argv[1], sys.argv[2]
with open(target_path) as f: user = json.load(f)
with open(template_path) as f: tpl = json.load(f)

merged = dict(user)
for k, v in tpl.items():
    if k == "hooks" and isinstance(v, dict) and isinstance(merged.get(k), dict):
        merged_hooks = dict(merged[k])
        for event, entries in v.items():
            if event in merged_hooks and isinstance(merged_hooks[event], list) and isinstance(entries, list):
                # Append template hooks after user hooks (preserve user ordering).
                merged_hooks[event] = merged_hooks[event] + entries
            else:
                merged_hooks[event] = entries
        merged[k] = merged_hooks
    elif k not in merged:
        merged[k] = v
    # else: user value wins

with open(target_path, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
PY
  then
    echo -e "  ${GREEN}✓${NC} Merged .claude/settings.json (user keys preserved; template hooks appended; backup at settings.json.bak)"
  else
    # Fallback if python3 is unavailable: preserve backup, overwrite template.
    cp "$TEMPLATE_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"
    echo -e "  ${YELLOW}!${NC} python3 not found — overwrote settings.json; prior version at settings.json.bak"
  fi
else
  mkdir -p "$TARGET_DIR/.claude"
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
echo -e "  ${GREEN}✓${NC} Refreshed CLAUDE.md.template"

# --- Merge .gitignore ---
if [ -f "$TARGET_DIR/.gitignore" ]; then
  added=0
  while IFS= read -r line; do
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

# --- Stamp kit version ---
echo "$KIT_VERSION" > "$TARGET_DIR/.claude/KIT_VERSION"

echo ""
echo -e "  ${DIM}Skipped: .git/, settings.local.json, errors.log, CLAUDE.md${NC}"
echo ""
echo -e "${BOLD}${GREEN}  Done! (v${KIT_VERSION})${NC}"
echo ""

if [ -z "$PRIOR_VERSION" ]; then
  echo -e "  Next steps:"
  echo -e "    ${CYAN}cd $TARGET_DIR${NC}"
  echo -e "    ${CYAN}claude${NC}"
  echo -e "    Then run ${BOLD}/setup${NC} to activate git hooks, install LSP plugins,"
  echo -e "    and burn rules into memory."
elif [ "$PRIOR_VERSION" = "$KIT_VERSION" ]; then
  echo -e "  Re-injected at v${KIT_VERSION} (no version change)."
else
  echo -e "  Upgraded from v${PRIOR_VERSION} → v${KIT_VERSION}."
  if [ -f "$TEMPLATE_DIR/CHANGELOG.md" ]; then
    echo -e "  See ${CYAN}$TEMPLATE_DIR/CHANGELOG.md${NC} for what changed."
  fi
  echo -e "  Re-run ${BOLD}/setup${NC} only if CLAUDE.md.template gained rules you want burned to memory."
fi
echo ""
