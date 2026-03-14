#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '%s\n' "$*"
}

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Required environment variable '$name' is not set."
  fi
}

write_output() {
  local key="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >>"$GITHUB_OUTPUT"
  fi
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_true() {
  case "${1:-false}" in
  true | TRUE | True | 1 | yes | YES | on | ON)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

safe_tag_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^0-9a-z._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

repo_slug_from_remote_url() {
  local remote_url="$1"
  remote_url="${remote_url%.git}"
  remote_url="${remote_url#git@github.com:}"
  remote_url="${remote_url#ssh://git@github.com/}"
  remote_url="${remote_url#https://github.com/}"
  remote_url="${remote_url#http://github.com/}"
  printf '%s' "$remote_url"
}

merge_flag_for_method() {
  case "$1" in
  merge)
    printf '%s' '--merge'
    ;;
  squash)
    printf '%s' '--squash'
    ;;
  rebase)
    printf '%s' '--rebase'
    ;;
  *)
    fail "Unsupported merge method '$1'. Use merge, squash, or rebase."
    ;;
  esac
}

require_env UPSTREAM_OWNER
require_env UPSTREAM_REPO

BASE_BRANCH="${BASE_BRANCH:-main}"
POLICY_SCRIPT="${POLICY_SCRIPT-ci/fork-policy.sh}"
RELEASE_SELECTOR="${RELEASE_SELECTOR:-latest}"
SYNC_BRANCH_INPUT="${SYNC_BRANCH_INPUT:-}"
SYNC_BRANCH_PREFIX="${SYNC_BRANCH_PREFIX:-sync/upstream-release}"
PR_LABELS="${PR_LABELS:-upstream-sync}"
PR_TITLE_TEMPLATE="${PR_TITLE_TEMPLATE:-}"
if [[ -z "$PR_TITLE_TEMPLATE" ]]; then
  PR_TITLE_TEMPLATE='Sync upstream release {tag}'
fi
MERGE_METHOD="${MERGE_METHOD:-merge}"
DRY_RUN="${DRY_RUN:-false}"
ORIGIN_REMOTE_NAME="${ORIGIN_REMOTE_NAME:-origin}"
UPSTREAM_REMOTE_NAME="${UPSTREAM_REMOTE_NAME:-upstream}"
UPSTREAM_REMOTE_URL="${UPSTREAM_REMOTE_URL:-https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}.git}"
GH_REPO="${GH_REPO:-${GITHUB_REPOSITORY:-}}"

release_tag=""
release_url=""
sync_branch=""
pr_number=""
pr_url=""
status="completed"

repo_path="repos/${UPSTREAM_OWNER}/${UPSTREAM_REPO}"

log "Preparing remotes for ${UPSTREAM_OWNER}/${UPSTREAM_REPO}"
if git remote get-url "$UPSTREAM_REMOTE_NAME" >/dev/null 2>&1; then
  git remote set-url "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
else
  git remote add "$UPSTREAM_REMOTE_NAME" "$UPSTREAM_REMOTE_URL"
fi

if [[ -z "$GH_REPO" ]]; then
  GH_REPO="$(repo_slug_from_remote_url "$(git remote get-url "$ORIGIN_REMOTE_NAME")")"
fi

if [[ -z "$GH_REPO" || "$GH_REPO" != */* ]]; then
  fail "Failed to determine the fork repository slug for gh commands."
fi

git fetch --no-tags "$ORIGIN_REMOTE_NAME" "+refs/heads/${BASE_BRANCH}:refs/remotes/${ORIGIN_REMOTE_NAME}/${BASE_BRANCH}"
git fetch "$UPSTREAM_REMOTE_NAME" --force --prune --tags "+refs/heads/*:refs/remotes/${UPSTREAM_REMOTE_NAME}/*"

log "Resolving upstream release with selector '$RELEASE_SELECTOR'"
if [[ "$RELEASE_SELECTOR" == "latest" ]]; then
  release_json="$(gh api "${repo_path}/releases/latest")"
else
  releases_json="$(gh api --paginate "${repo_path}/releases?per_page=100" | jq -cs 'add')"

  if [[ "$RELEASE_SELECTOR" == "prerelease" ]]; then
    release_json="$(jq -cr 'map(select((.draft | not) and .prerelease)) | first // empty' <<<"$releases_json")"
  else
    release_json="$(jq -cr --arg pattern "$RELEASE_SELECTOR" 'map(select((.draft | not) and (.tag_name | test($pattern)))) | first // empty' <<<"$releases_json")"
  fi

  if [[ -z "$release_json" ]]; then
    fail "No upstream release matched selector '$RELEASE_SELECTOR'."
  fi
fi

release_tag="$(jq -r '.tag_name' <<<"$release_json")"
release_url="$(jq -r '.html_url // empty' <<<"$release_json")"

if [[ -z "$release_tag" || "$release_tag" == "null" ]]; then
  fail "Failed to resolve an upstream release tag."
fi

write_output release_tag "$release_tag"
write_output release_url "$release_url"

tag_commit="$(git rev-list -n 1 "refs/tags/${release_tag}^{commit}")"
if [[ -z "$tag_commit" ]]; then
  fail "Tag '${release_tag}' was not fetched from the upstream remote."
fi

if git merge-base --is-ancestor "$tag_commit" "${ORIGIN_REMOTE_NAME}/${BASE_BRANCH}"; then
  log "Upstream tag ${release_tag} is already contained in ${ORIGIN_REMOTE_NAME}/${BASE_BRANCH}."
  status="up_to_date"
  write_output sync_branch ""
  write_output pr_number ""
  write_output pr_url ""
  write_output status "$status"
  exit 0
fi

safe_tag="$(safe_tag_name "$release_tag")"
if [[ -z "$safe_tag" ]]; then
  safe_tag="release"
fi

if [[ -n "$SYNC_BRANCH_INPUT" ]]; then
  sync_branch="$SYNC_BRANCH_INPUT"
else
  sync_branch="${SYNC_BRANCH_PREFIX}-${safe_tag}"
fi

upstream_ref="${UPSTREAM_OWNER}/${UPSTREAM_REPO}"
pr_title="$(
  python3 - "$PR_TITLE_TEMPLATE" "$release_tag" "$BASE_BRANCH" "$upstream_ref" <<'PY'
import sys

template, tag, base_branch, upstream = sys.argv[1:]
print(template.replace('{tag}', tag).replace('{base_branch}', base_branch).replace('{upstream}', upstream))
PY
)"

log "Creating sync branch ${sync_branch} from ${BASE_BRANCH}"
git checkout -B "$sync_branch" "${ORIGIN_REMOTE_NAME}/${BASE_BRANCH}"
merge_had_conflicts=false
if ! git merge --no-ff --no-commit "$release_tag"; then
  merge_had_conflicts=true
  log "Merge reported conflicts; applying fork policy before deciding whether to fail."
fi

if [[ -n "$POLICY_SCRIPT" ]]; then
  if [[ ! -f "$POLICY_SCRIPT" ]]; then
    fail "Policy script '$POLICY_SCRIPT' was not found."
  fi

  log "Applying fork policy via ${POLICY_SCRIPT}"
  env \
    BASE_BRANCH="$BASE_BRANCH" \
    ORIGIN_REMOTE_NAME="$ORIGIN_REMOTE_NAME" \
    RELEASE_TAG="$release_tag" \
    SYNC_BRANCH="$sync_branch" \
    UPSTREAM_OWNER="$UPSTREAM_OWNER" \
    UPSTREAM_REPO="$UPSTREAM_REPO" \
    UPSTREAM_REMOTE_NAME="$UPSTREAM_REMOTE_NAME" \
    bash "$POLICY_SCRIPT"
else
  log "No policy script configured; skipping policy step."
fi

git add -A
git rm --cached --quiet --force --ignore-unmatch .fork-sync-kit

if $merge_had_conflicts; then
  unmerged_files="$(git diff --name-only --diff-filter=U)"
  if [[ -n "$unmerged_files" ]]; then
    printf 'Unresolved merge conflicts remain:\n%s\n' "$unmerged_files" >&2
    exit 1
  fi
fi

git commit --no-edit --allow-empty

write_output sync_branch "$sync_branch"

if is_true "$DRY_RUN"; then
  status="dry_run"
  write_output pr_number ""
  write_output pr_url ""
  write_output status "$status"
  log "Dry run enabled; skipping push and PR operations."
  exit 0
fi

log "Pushing ${sync_branch} to ${ORIGIN_REMOTE_NAME}"
git push --force-with-lease --set-upstream "$ORIGIN_REMOTE_NAME" "$sync_branch"

body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
{
  printf 'This PR syncs upstream release **%s** into `%s`.\n\n' "$release_tag" "$BASE_BRANCH"
  printf -- '- Upstream repository: `%s/%s`\n' "$UPSTREAM_OWNER" "$UPSTREAM_REPO"
  printf -- '- Release: %s\n' "$release_url"
  printf -- '- Sync branch: `%s`\n' "$sync_branch"
  printf -- '- Generated by `fork-sync-kit`\n'
} >"$body_file"

label_args=()
label_edit_args=()
if [[ -n "$PR_LABELS" ]]; then
  IFS=',' read -r -a raw_labels <<<"$PR_LABELS"
  for raw_label in "${raw_labels[@]}"; do
    label="$(trim "$raw_label")"
    if [[ -n "$label" ]]; then
      label_args+=(--label "$label")
      label_edit_args+=(--add-label "$label")
    fi
  done
fi

existing_json="$(gh pr list --repo "$GH_REPO" --state open --head "$sync_branch" --base "$BASE_BRANCH" --json number,url | jq '.[0] // empty')"
if [[ -n "$existing_json" ]]; then
  pr_number="$(jq -r '.number' <<<"$existing_json")"
  pr_url="$(jq -r '.url' <<<"$existing_json")"
  gh pr edit "$pr_number" --repo "$GH_REPO" --title "$pr_title" --body-file "$body_file" >/dev/null
  if [[ ${#label_edit_args[@]} -gt 0 ]]; then
    gh pr edit "$pr_number" --repo "$GH_REPO" "${label_edit_args[@]}" >/dev/null
  fi
  status="updated"
  log "Updated PR #${pr_number}"
else
  gh pr create \
    --repo "$GH_REPO" \
    --base "$BASE_BRANCH" \
    --head "$sync_branch" \
    --title "$pr_title" \
    --body-file "$body_file" \
    "${label_args[@]}" >/dev/null
  pr_number="$(gh pr list --repo "$GH_REPO" --state open --head "$sync_branch" --base "$BASE_BRANCH" --json number --jq '.[0].number')"
  pr_url="$(gh pr view "$pr_number" --repo "$GH_REPO" --json url --jq '.url')"
  status="created"
  log "Created PR #${pr_number}"
fi

merge_flag="$(merge_flag_for_method "$MERGE_METHOD")"
gh pr merge "$pr_number" --repo "$GH_REPO" --auto "$merge_flag" >/dev/null

write_output pr_number "$pr_number"
write_output pr_url "$pr_url"
write_output status "$status"

log "Sync completed with status '${status}'"
