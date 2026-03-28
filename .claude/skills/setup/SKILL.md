---
name: setup
description: First-time project setup — git hooks, .gitignore, LSP plugins, and burns CLAUDE.md rules into persistent memory.
allowed-tools: Read, Write, Glob, Grep, Bash
---

Initialize this project for Claude Code development.

## Step 1: Git Hooks Setup
Configure git to use the project's custom hooks:
```bash
git config core.hooksPath .githooks
```
Verify the hooks are executable:
```bash
chmod +x .githooks/pre-commit .githooks/pre-push
```
Report to the user that git hooks are active.

## Step 2: Ensure .gitignore
Read the existing `.gitignore` (or create one if it doesn't exist). Ensure these entries are present — append any that are missing:

```
# Claude Code
.claude/settings.local.json
.claude/errors.log
.claude/.initialized
CLAUDE.md.template

# Secrets
.env
.env.*
!.env.example
*.pem
*.key
credentials.json
service-account*.json

# OS
.DS_Store
Thumbs.db

# Python
__pycache__/
*.pyc
.venv/
venv/
```

Do NOT overwrite existing entries. Only append missing ones. Preserve the existing file content.

## Step 3: Auto-Install LSP Plugins
Detect which languages are present in the project and install matching LSP plugins for real-time type checking. Check for these indicators and install if found:

| Indicator | Plugin |
|-----------|--------|
| `*.py` files or `pyproject.toml` or `requirements.txt` | `claude plugin install pyright-lsp` |
| `package.json` or `tsconfig.json` or `*.ts`/`*.tsx` | `claude plugin install typescript-lsp` |
| `Cargo.toml` or `*.rs` | `claude plugin install rust-analyzer-lsp` |
| `pom.xml` or `build.gradle` or `*.java` | `claude plugin install jdtls-lsp` |
| `Package.swift` or `*.swift` | `claude plugin install swift-lsp` |
| `build.sbt` or `*.scala` | `claude plugin install jdtls-lsp` |
| `go.mod` or `*.go` | `claude plugin install gopls-lsp` |
| `*.kt` or `build.gradle.kts` | `claude plugin install kotlin-lsp` |

Use `glob` to check for file presence. Only install plugins for languages actually used. Report which plugins were installed.

If a plugin install fails (e.g., not available), note it and continue — don't block init.

## Step 4: Burn Rules into Memory

### Why This Exists
CLAUDE.md instructions can be deprioritized during long sessions or context compaction.
Memories are loaded fresh into every conversation and are harder to ignore.
This skill "burns in" the non-negotiable rules so they persist reliably.

### Instructions

1. **Always read `CLAUDE.md.template`** for the non-negotiable rules to burn into memory. This is the template's source of truth — never use the project's existing `CLAUDE.md` for this step, since that contains project-specific content. If `CLAUDE.md.template` doesn't exist, tell the user and stop.
   - If no `CLAUDE.md` exists at the project root, copy `CLAUDE.md.template` to `CLAUDE.md`.
   - If `CLAUDE.md` already exists, leave it alone — the user's project conventions take priority. Optionally suggest they merge any useful rules from the template.

2. **Extract non-negotiable rules** from CLAUDE.md. These are rules that should NEVER be violated regardless of context. Look for:
   - Security requirements
   - Code review requirements
   - Testing requirements
   - Commit/push conventions
   - Production code standards (12-factor, structured logging, etc.)
   - Delegation & context hygiene rules
   - Anything marked as "must", "always", "never", "required", "non-negotiable"

3. **Read the existing MEMORY.md** in the memory directory to avoid duplicates.
   Memory directory: find it by checking the path pattern `~/.claude/projects/*/memory/MEMORY.md`
   or use the current project's memory path.

4. **Create feedback-type memory files** for each non-negotiable rule.
   Write each to the project memory directory with this format:

   ```markdown
   ---
   name: rule-short-name
   description: One line describing when this rule applies
   type: feedback
   ---

   [The rule itself]

   **Why:** [Why this rule exists — from CLAUDE.md context]

   **How to apply:** [When and where to apply this rule]
   ```

5. **Update MEMORY.md** index with pointers to each new memory file.

6. **Mark setup complete**: Run `touch .claude/.initialized` so the preflight hook knows not to nag on future sessions.

7. **Report** what was done:
   - Git hooks status
   - Each rule that was burned into memory
   - Any existing memories that were updated vs created new
   - Confirm the memory directory path used

## Important
- Do NOT duplicate rules that already exist in memory
- Do NOT save ephemeral or code-derivable information
- Focus on behavioral rules that guide HOW Claude should work, not WHAT the codebase contains
- Keep each memory focused on a single rule for clarity
