#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

today_hkt="$(TZ=Asia/Hong_Kong date +'%Y-%m-%d')"
since_hkt="$(TZ=Asia/Hong_Kong date -d 'today 00:00' +'%Y-%m-%dT%H:%M:%S%z')"
branch="${GITHUB_REF_NAME:-$(git branch --show-current)}"
bot_email="41898282+github-actions[bot]@users.noreply.github.com"

if [[ -z "$branch" ]]; then
  echo "::error::Cannot determine the branch to update."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "::error::Working tree is not clean; refusing to rewrite history."
  exit 1
fi

original_head="$(git rev-parse HEAD)"
mapfile -t today_commits < <(git log --first-parent --since="$since_hkt" --format='%H%x09%s' "$original_head")

if ((${#today_commits[@]} == 0)); then
  echo "No commits were created today in Hong Kong time."
  exit 0
fi

is_automated_data_commit() {
  local commit_sha="$1"
  local subject="$2"
  local author_email changed_paths path

  author_email="$(git show -s --format=%ae "$commit_sha")"
  if [[ "$author_email" != "$bot_email" ]] && \
    [[ "$subject" != "Update admission data" && "$subject" != "Update basic and schedule data ("* ]]; then
    return 1
  fi

  changed_paths="$(git diff-tree --no-commit-id --no-renames --name-only -r "$commit_sha")"
  [[ -n "$changed_paths" ]] || return 1

  while IFS= read -r path; do
    [[ "$path" == data/* ]] || return 1
  done <<< "$changed_paths"
}

declare -A automated_data_commits=()
oldest_data_commit=""
data_commit_count=0

for entry in "${today_commits[@]}"; do
  commit_sha="${entry%%$'\t'*}"
  subject="${entry#*$'\t'}"
  if is_automated_data_commit "$commit_sha" "$subject"; then
    automated_data_commits["$commit_sha"]=1
    oldest_data_commit="$commit_sha"
    data_commit_count=$((data_commit_count + 1))
  fi
done

if ((data_commit_count <= 1)); then
  echo "There are fewer than two automated data commits today; nothing to squash."
  exit 0
fi

base_commit="$(git rev-parse -q --verify "${oldest_data_commit}^" 2>/dev/null || true)"
if [[ -z "$base_commit" ]]; then
  echo "::error::The oldest automated data commit has no parent; refusing to rewrite the root commit."
  exit 1
fi

if ! git cat-file -e "${original_head}:data" 2>/dev/null; then
  echo "::error::The current tree has no data directory to consolidate."
  exit 1
fi

mapfile -t commits_after_base < <(git rev-list --first-parent --reverse "${base_commit}..${original_head}")

if ((${#commits_after_base[@]} == 0)); then
  echo "No commits exist after the consolidation base."
  exit 0
fi

rewrite_started=false
restore_original_history_on_failure() {
  local exit_code=$?
  trap - EXIT
  if ((exit_code != 0)) && [[ "$rewrite_started" == true ]]; then
    git reset --hard "$original_head" >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}
trap restore_original_history_on_failure EXIT

rewrite_started=true
git reset --hard "$base_commit"

for commit_sha in "${commits_after_base[@]}"; do
  if [[ -n "${automated_data_commits[$commit_sha]:-}" ]]; then
    continue
  fi

  parent_commit="$(git rev-parse "${commit_sha}^1")"
  if ! git diff --quiet "$parent_commit" "$commit_sha"; then
    if ! git diff --binary --full-index "$parent_commit" "$commit_sha" | git apply --index --3way; then
      echo "::error::Could not replay manual commit ${commit_sha}; restoring the original history."
      exit 1
    fi
  fi

  git -c user.name="github-actions[bot]" \
    -c user.email="$bot_email" \
    commit --allow-empty -C "$commit_sha"
done

git restore --source="$original_head" --staged --worktree -- data
if ! git diff --cached --quiet -- data; then
  git -c user.name="github-actions[bot]" \
    -c user.email="$bot_email" \
    commit -m "Consolidate swimming pool data ($today_hkt)"
else
  echo "The final data tree is already present; no consolidated data commit is needed."
fi

git push --force-with-lease origin "HEAD:refs/heads/${branch}"
rewrite_started=false
