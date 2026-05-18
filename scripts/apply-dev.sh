#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_FILE="${ROOT_DIR}/workspace.yml"
SESSION_FILE="${ROOT_DIR}/.dev-session.env"

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/lib/prompt.sh"

TYPE="${TYPE:-}"
DESC="${DESC:-}"
REPOS_CSV="${REPOS:-}"
ALL="${ALL:-}"
DRY_RUN="${DRY_RUN:-false}"
SESSION_BRANCH=""

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

is_valid_type() {
  [[ "$1" == "feature" || "$1" == "fix" || "$1" == "chore" ]]
}

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]_]+/-/g; s/[^a-z0-9.-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//'
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

prompt_type() {
  echo "Select commit type:"
  select option in feature fix chore; do
    if is_valid_type "${option:-}"; then
      TYPE="$option"
      break
    fi
    echo "Invalid selection. Choose 1, 2 or 3."
  done
}

prompt_desc() {
  while true; do
    read_prompt "Enter commit description: " raw
    raw="$(trim_whitespace "$raw")"
    if [[ -n "$raw" ]]; then
      DESC="$raw"
      break
    fi
    echo "Description is required."
  done
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

prompt_repos() {
  local i
  echo "Select repositories:"
  echo "  0) all"
  for i in "${!REPO_NAMES[@]}"; do
    printf "  %d) %s [%s]\n" "$((i + 1))" "${REPO_NAMES[$i]}" "${REPO_TYPES[$i]}"
  done

  while true; do
    local selection old_ifs valid idx repo
    local -a idxs picked

    read_prompt "Choice (0 or comma-separated numbers): " selection
    selection="$(trim_whitespace "$selection")"
    if [[ "$selection" == "0" ]]; then
      select_all_repos
      return
    fi

    old_ifs="$IFS"
    IFS=',' read -r -a idxs <<< "$selection"
    IFS="$old_ifs"

    valid=true
    picked=()
    TARGET_REPOS=()
    for idx in "${idxs[@]}"; do
      idx="$(trim_whitespace "$idx")"
      if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
        valid=false
        break
      fi
      if (( idx < 1 || idx > ${#REPO_NAMES[@]} )); then
        valid=false
        break
      fi
      repo="${REPO_NAMES[$((idx - 1))]}"
      if ! repo_already_selected "$repo"; then
        TARGET_REPOS+=("$repo")
        picked+=("$repo")
      fi
    done

    if [[ "$valid" == true && ${#picked[@]} -gt 0 ]]; then
      return
    fi
    echo "Invalid selection."
  done
}

process_repo() {
  local repo="$1"
  local type="$2"
  local dir
  local branch
  local message

  dir="${ROOT_DIR}/$(get_dir "$type")/${repo}"

  if [[ ! -d "$dir/.git" ]]; then
    echo "[FAIL] $repo: missing git repository at $dir"
    return 1
  fi

  branch="$(git -C "$dir" branch --show-current)"
  if [[ -z "$branch" || "$branch" == "main" ]]; then
    echo "[FAIL] $repo: current branch is '$branch'. Switch to a feature branch first."
    return 1
  fi

  if [[ -n "$SESSION_BRANCH" && "$branch" != "$SESSION_BRANCH" ]]; then
    echo "[FAIL] $repo: current branch '$branch' does not match active dev branch '$SESSION_BRANCH'."
    return 1
  fi

  if [[ -z "$(git -C "$dir" status --porcelain)" ]]; then
    echo "[SKIP] $repo: no local changes"
    return 0
  fi

  message="${TYPE}(${repo}): ${DESC}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY] $repo: git add -A"
    echo "[DRY] $repo: git commit -m \"$message\""
    echo "[DRY] $repo: git push -u origin $branch"
    return 0
  fi

  git -C "$dir" add -A
  if git -C "$dir" diff --cached --quiet; then
    echo "[SKIP] $repo: nothing to commit after staging"
    return 0
  fi

  git -C "$dir" commit -m "$message"
  git -C "$dir" push -u origin "$branch"
  echo "[OK] $repo: committed and pushed on $branch"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) TYPE="$2"; shift 2 ;;
      --description) DESC="$2"; shift 2 ;;
      --repos) REPOS_CSV="$2"; shift 2 ;;
      --all) ALL="true"; shift ;;
      --dry-run) DRY_RUN="true"; shift ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done
}

load_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$SESSION_FILE"
    SESSION_BRANCH="${DEV_BRANCH:-}"

    [[ -z "$TYPE" && -n "${DEV_TYPE:-}" ]] && TYPE="$DEV_TYPE"
    [[ -z "$DESC" && -n "${DEV_DESC:-}" ]] && DESC="$DEV_DESC"
    [[ -z "$REPOS_CSV" && -n "${DEV_TARGET_REPOS:-}" ]] && REPOS_CSV="$DEV_TARGET_REPOS"
  fi
}

main() {
  local failures repo
  [[ -f "$WORKSPACE_FILE" ]] || { echo "workspace.yml not found"; exit 1; }
  parse_args "$@"
  load_repos
  load_session

  if [[ -z "$TYPE" ]]; then
    prompt_type
  else
    TYPE="$(slugify "$TYPE")"
    is_valid_type "$TYPE" || { echo "Invalid type: $TYPE"; exit 1; }
  fi

  if [[ -z "$DESC" ]]; then
    prompt_desc
  fi

  if [[ "$ALL" == "true" ]]; then
    select_all_repos
  elif [[ -n "$REPOS_CSV" ]]; then
    select_from_csv "$REPOS_CSV"
  else
    prompt_repos
  fi

  echo
  echo "Commit type: $TYPE"
  echo "Description: $DESC"
  [[ -n "$SESSION_BRANCH" ]] && echo "Active branch from session: $SESSION_BRANCH"
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
