#!/usr/bin/env bash
set -euo pipefail

base_ref="${ORIGIN_REMOTE_NAME:-origin}/${BASE_BRANCH:-main}"

git rev-parse --verify "$base_ref" >/dev/null 2>&1

mapfile -t conflicted_paths < <(git diff --name-only --diff-filter=U -- .github/workflows)
if [[ ${#conflicted_paths[@]} -gt 0 ]]; then
  git rm -f --quiet -- "${conflicted_paths[@]}"
fi

git restore --source "$base_ref" --staged --worktree -- .github/workflows

printf 'Restored fork-owned workflows from %s.\n' "$base_ref"
