# Git Hooks

This repository uses [Lefthook](https://lefthook.dev/) to manage Git hooks.

## Setup

Install Lefthook, then install the configured hooks:

```sh
brew install lefthook
lefthook install
```

If Lefthook is already available through another package manager, `lefthook install` is the only repository setup step.

## Commit Message Format

Commit messages must use a Conventional Commit style prefix, include one or more Jira keys, and describe the change clearly:

```text
feat(parser): KAN-123 add quoted path support
fix: KAN-123 prevent duplicate terminal sessions
chore(ci): KAN-123, KAN-456 tighten release checks
```

Allowed types are:

```text
build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test
```

The validator allows Git-generated merge commits, Git-generated revert commits, and `fixup!` or `squash!` commits for autosquash workflows.
