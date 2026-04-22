#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $(basename "$0") <commit-range>" >&2
  exit 1
fi

range="$1"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

commits=()
while IFS= read -r commit; do
  commits+=("$commit")
done < <(git rev-list --reverse "$range")

if [[ ${#commits[@]} -eq 0 ]]; then
  echo "commit-lint: no commits found in range '$range'."
  exit 0
fi

status=0

for commit in "${commits[@]}"; do
  subject="$(git log --format=%s -n 1 "$commit")"
  echo "commit-lint: checking $commit $subject"

  if ! git log --format=%B -n 1 "$commit" | "$script_dir/commit-lint.sh"; then
    status=1
    echo "commit-lint: failed for commit $commit" >&2
  fi
done

exit "$status"
