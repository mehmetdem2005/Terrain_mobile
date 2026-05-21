# Project instructions for Claude Code

## PR auto-merge policy

The repo owner (mehmetdem2005) has granted standing authorization: after
Claude creates a pull request in this repository, Claude may immediately
call `mcp__github__merge_pull_request` to merge it without asking for
per-PR confirmation.

- **Merge method:** `squash` (one commit per PR, clean history)
- **Scope:** Only PRs that Claude itself authored in the current session
- **Exceptions — still ask before merging if:**
  - CI is failing or required checks are red
  - The PR has unresolved review comments from a human
  - The PR touches `CLAUDE.md`, `.github/`, branch protection, or secrets
  - The base branch is `main` and the change is large (>500 LOC) or risky
- **After merging:** report the merge URL in chat so the user sees it
