#!/usr/bin/env bash
set -euo pipefail

commit_msg_file="${1:-}"

if [[ -z "$commit_msg_file" || ! -f "$commit_msg_file" ]]; then
  echo "Commit message validation could not find the commit message file." >&2
  exit 1
fi

subject="$(sed -n '1p' "$commit_msg_file")"
subject="${subject%$'\r'}"

# Let Git-generated workflow commits through.
if [[ "$subject" =~ ^Merge[[:space:]] ]] ||
  [[ "$subject" =~ ^Revert[[:space:]]\" ]] ||
  [[ "$subject" =~ ^(fixup|squash)![[:space:]] ]]; then
  exit 0
fi

types="build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test"
jira_key='[A-Z][A-Z0-9]+-[0-9]+'
header_pattern="^(${types})(\([a-z0-9][a-z0-9._/-]*\))?!?: (.+)$"
jira_prefix_pattern="^(${jira_key})([ ,]+${jira_key})* (.+)$"
vague_summary_pattern='^(wip|misc|update|updates|change|changes|fix|fixes|stuff|work)$'

fail() {
  cat >&2 <<'EOF'
Invalid commit message.

Expected:
  feat(parser): KAN-123 add quoted path support
  fix: KAN-123 prevent duplicate terminal sessions
  chore(ci): KAN-123, KAN-456 tighten release checks

Rules:
  - start with one of: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test
  - optional scope must be lowercase, for example: feat(parser):
  - include one or more Jira keys immediately after the type/scope
  - write a clear summary after the Jira key, at least 8 characters long
  - keep the first line at 100 characters or less
EOF
  exit 1
}

if [[ ${#subject} -gt 100 ]]; then
  fail
fi

if ! [[ "$subject" =~ $header_pattern ]]; then
  fail
fi

message_after_type="${BASH_REMATCH[3]}"

if ! [[ "$message_after_type" =~ $jira_prefix_pattern ]]; then
  fail
fi

summary="${BASH_REMATCH[3]}"
summary_lower="$(printf '%s' "$summary" | tr '[:upper:]' '[:lower:]')"

if [[ ${#summary} -lt 8 ]] || [[ "$summary_lower" =~ $vague_summary_pattern ]]; then
  fail
fi
