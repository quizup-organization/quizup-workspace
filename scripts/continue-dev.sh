#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_FILE="${ROOT_DIR}/workspace.yml"
SESSION_FILE="${ROOT_DIR}/.dev-session.env"

REPOS_CSV="${REPOS:-}"
ALL="${ALL:-}"
DRY_RUN="${DRY_RUN:-false}"
SESSION_BRANCH=""

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/lib/prompt.sh"

declare -a TARGET_REPOS=()
declare -a REPO_NAMES=()
declare -a REPO_TYPES=()

get_dir() {
  case "$1" in
    library) echo "libraries" ;;
    devops) echo "devops" ;;
    web-application) echo "web-applications" ;;
    *) echo "services" ;;
  esac
}

load_repos() {
  local lines line name type
  lines="$(yq -r '.repos[] | [.name, .type] | @tsv' "$WORKSPACE_FILE")"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    name="$(echo "$line" | cut -f1)"
    type="$(echo "$line" | cut -f2)"
    REPO_NAMES+=("$name")
    REPO_TYPES+=("$type")
  done <<< "$lines"
}

repo_index_by_name() {
  local target="$1"
  local i
  for i in "${!REPO_NAMES[@]}"; do
    if [[ "${REPO_NAMES[$i]}" == "$target" ]]; then
      echo "$i"
      return 0
    fi
  done
  echo "-1"
}

type_by_repo_name() {
  local target="$1"
  local idx
  idx="$(repo_index_by_name "$target")"
  if [[ "$idx" == "-1" ]]; then
    echo ""
    return 1
  fi
  echo "${REPO_TYPES[$idx]}"
}

repo_already_selected() {
  local target="$1"
  local repo
  for repo in "${TARGET_REPOS[@]:-}"; do
    [[ "$repo" == "$target" ]] && return 0
  done
  return 1
}

select_all_repos() {
  TARGET_REPOS=("${REPO_NAMES[@]}")
}

select_from_csv() {
  local csv="$1"
  local old_ifs repo item
  old_ifs="$IFS"
  IFS=',' read -r -a items <<< "$csv"
  IFS="$old_ifs"

  for item in "${items[@]}"; do
    repo="$(echo "$item" | xargs)"
    [[ -z "$repo" ]] && continue
    if [[ "$(repo_index_by_name "$repo")" == "-1" ]]; then
      echo "Unknown repository: $repo"
      exit 1
    fi
    if ! repo_already_selected "$repo"; then
      TARGET_REPOS+=("$repo")
    fi
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repos) REPOS_CSV="$2"; shift 2 ;;
      --all) ALL="true"; shift ;;
      --dry-run) DRY_RUN="true"; shift ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done
}

load_session() {
  if [[ ! -f "$SESSION_FILE" ]]; then
    echo "No active session file found: $SESSION_FILE"
    echo "Run 'make start-dev' first."
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$SESSION_FILE"

  SESSION_BRANCH="${DEV_BRANCH:-}"
  [[ -z "$SESSION_BRANCH" ]] && { echo "Invalid session: DEV_BRANCH is missing."; exit 1; }

  if [[ -z "$REPOS_CSV" && -n "${DEV_TARGET_REPOS:-}" ]]; then
    REPOS_CSV="$DEV_TARGET_REPOS"
  fi
}

branch_exists_remote() {
  local repo_dir="$1"
  local branch_name="$2"
  git -C "$repo_dir" ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1
}

process_repo() {
  local repo="$1"
  local type="$2"
  local dir
  local has_local_branch=false
  local has_remote_branch=false

  dir="${ROOT_DIR}/$(get_dir "$type")/${repo}"

  if [[ ! -d "$dir/.git" ]]; then
    echo "[FAIL] $repo: missing git repository at $dir"
    return 1
  fi

  if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
    echo "[FAIL] $repo: local changes detected. Commit/stash before running continue-dev."
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY] $repo: git fetch origin --prune"
  else
    git -C "$dir" fetch origin --prune
  fi

  if git -C "$dir" show-ref --verify --quiet "refs/heads/${SESSION_BRANCH}"; then
    has_local_branch=true
  fi

  if branch_exists_remote "$dir" "$SESSION_BRANCH"; then
    has_remote_branch=true
  fi

  if [[ "$has_local_branch" == "false" && "$has_remote_branch" == "false" ]]; then
    echo "[FAIL] $repo: branch '${SESSION_BRANCH}' not found locally or on origin."
    return 1
  fi

  if [[ "$has_local_branch" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY] $repo: git checkout ${SESSION_BRANCH}"
    else
      git -C "$dir" checkout "$SESSION_BRANCH" >/dev/null
    fi
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY] $repo: git checkout -b ${SESSION_BRANCH} origin/${SESSION_BRANCH}"
    else
      git -C "$dir" checkout -b "$SESSION_BRANCH" "origin/${SESSION_BRANCH}" >/dev/null
    fi
  fi

  if [[ "$has_remote_branch" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY] $repo: git pull --ff-only origin ${SESSION_BRANCH}"
    else
      git -C "$dir" pull --ff-only origin "$SESSION_BRANCH"
    fi
  else
    echo "[WARN] $repo: no remote branch origin/${SESSION_BRANCH}; local branch only."
  fi

  echo "[OK] $repo: ${SESSION_BRANCH}"
}

main() {
  local failures repo
  [[ -f "$WORKSPACE_FILE" ]] || { echo "workspace.yml not found"; exit 1; }

  parse_args "$@"
  load_repos
  load_session

  if [[ "$ALL" == "true" ]]; then
    select_all_repos
  elif [[ -n "$REPOS_CSV" ]]; then
    select_from_csv "$REPOS_CSV"
  else
    echo "No repositories selected. Use --repos, --all, or set DEV_TARGET_REPOS in the session file."
    exit 1
  fi

  echo
  echo "Session branch: $SESSION_BRANCH"
  echo "Targets: ${TARGET_REPOS[*]:-}"
  [[ "$DRY_RUN" == "true" ]] && echo "Mode: dry-run"
  echo

  failures=0
  for repo in "${TARGET_REPOS[@]}"; do
    process_repo "$repo" "$(type_by_repo_name "$repo")" || failures=$((failures + 1))
  done

  echo
  if (( failures > 0 )); then
    echo "Completed with ${failures} failure(s)."
    exit 1
  fi

  echo "Completed successfully."
}

main "$@"

