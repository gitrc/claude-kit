---
name: ship
description: Lightweight commit, push, and open PR. Use after /review or /qa when code is ready to ship.
argument-hint: "[commit-message]"
allowed-tools: Bash, Read
---

# /ship — Commit, Push, and Open PR

Lightweight shipping workflow. Code review lives in `/review` and `/qa`. `/ship` gets code out the door — but never ships untested code.

## Steps

1. **Check for changes**: Run `git status` and `git diff --stat`. If there are no changes to ship, tell the user and stop.

2. **Ensure feature branch**: Check the current branch name.
   - If on `main` or `master`, create a new feature branch first (`git checkout -b <branch-name>`). Derive the branch name from the changes (e.g., `feat/add-auth-middleware`).
   - Otherwise, stay on the current branch.

3. **Verify before committing**: Apply the `/verify` gate.
   - Detect the project's test command (see project manifest: `package.json` scripts, `pyproject.toml`/`pytest`, `cargo test`, `go test ./...`, `sbt test`, etc.). Run it. Read the output. 0 failures.
   - Run the linter / type checker if one is configured. 0 errors.
   - If the project has no tests configured, say so explicitly rather than silently skipping — "No test suite detected. Shipping without test evidence."
   - If any verification fails, stop. Do not commit. Report the failure to the user.

4. **Determine commit message**:
   - If the user provided an argument, use it as the commit message.
   - Otherwise, generate a concise commit message from the diff (explain WHY, not WHAT).

5. **Stage files**: Stage the specific changed files shown by `git status`. NEVER use `git add -A` or `git add .`. Add files by name.

6. **Commit**: Create the commit with the message. Include the co-author trailer:
   ```
   Co-Authored-By: Claude <noreply@anthropic.com>
   ```

7. **Push**: Push with `-u` to set upstream tracking:
   ```bash
   git push -u origin <branch>
   ```

8. **Open PR**: Check if a PR already exists for this branch:
   ```bash
   gh pr view --json url 2>/dev/null
   ```
   - If a PR exists, report its URL.
   - If no PR exists, create one:
     ```bash
     gh pr create --title "<concise title>" --body "<summary of changes>"
     ```

9. **Report**: Show the PR URL to the user. If a PR existed or was just created, remind the user they can run `/pr-comments` to address review feedback once Copilot (or a human reviewer) has posted comments.

## Important

- Never force-push.
- Never push to main/master directly.
- Stage specific files only.
- Keep commit messages concise and focused on WHY.
