---
name: pr-comments
description: Review and address GitHub Copilot (or any) PR review comments. Auto-detects PR from current branch.
argument-hint: "[pr-number]"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent
---

Address all open review comments on a GitHub Pull Request.

## Step 1: Identify the PR
If an argument was provided, use PR #$ARGUMENTS.
Otherwise, auto-detect from the current branch:
```
gh pr view --json number,title,url,headRefName
```
If no PR is found, tell the user and stop.

## Step 2: Pull All Open Comments
Fetch all review comments (pending and active):
```
gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
```
Also fetch review threads to identify which are resolved vs unresolved:
```
gh pr view {number} --json reviewDecision,reviews,comments
```
Filter to only **unresolved** comment threads.

## Step 3: Analyze and Address Each Comment

Apply the `/address-review` policy for every comment. In short:
- Read the referenced file and line for full context before judging the suggestion.
- Verify the suggestion against actual codebase reality — never trust blindly.
- Push back with technical reasoning when the reviewer is wrong, contradicts CLAUDE.md conventions, or violates YAGNI.
- No performative agreement in replies — no "Great catch!", no "You're absolutely right!", no gratitude. State the fix or the pushback.
- Style nits with no substance: just implement, don't argue.
- Questions: prepare a direct answer.

Make fixes with the Edit tool, one comment at a time.

## Step 4: Verify Before Pushing

Apply the `/verify` gate before committing:
- Run the test suite. Read the output. 0 failures.
- Run the linter / type checker if the project has one. 0 errors.
- If a fix was supposed to resolve a specific bug, re-run the reproduction case.

If anything fails, fix it before moving on. Never push a "probably works" fix in response to review feedback — that triggers another review round and erodes trust.

## Step 5: Commit and Push
After all comments are addressed and verification passes:
1. Stage changed files: `git add <specific files>`
2. Commit with a message like: `fix: address PR review comments`
3. Push: `git push`

## Step 6: Reply to Each Comment Thread
For each comment that was addressed:
1. Reply to the comment thread explaining what was done:
   ```
   gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies -f body="..."
   ```
2. **Resolve the thread** if the fix fully addresses it. Use the GraphQL API:
   ```
   gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) { thread { isResolved } } }'
   ```

To get the thread node ID, use:
```
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") { pullRequest(number: PR_NUM) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { body databaseId } } } } } } }'
```

## Step 7: Summary
Report to the user:
- How many comments were addressed
- How many threads were resolved
- Any comments that need human judgment
- Remind them to re-run `/pr-comments` after Copilot's next pass
