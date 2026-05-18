#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_FILE="${ROOT_DIR}/workspace.yml"
SESSION_FILE="${ROOT_DIR}/.dev-session.env"

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/lib/prompt.sh"

TYPE="${TYPE:-}"
SCOPE="${SCOPE:-}"
FEATURE="${FEATURE:-}"
REPOS_CSV="${REPOS:-}"
ALL="${ALL:-}"
DRY_RUN="${DRY_RUN:-false}"
DEV_DESC="${DESC:-${DEV_DESC:-}}"

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
  sanitize_input "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[[:space:]_]+/-/g; s/[^a-z0-9.-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//'
}

is_valid_fragment() {
  [[ "$1" =~ ^[a-z0-9]+([.-][a-z0-9]+)*$ ]]
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
  echo "Select development type:"
  select option in feature fix chore; do
    if is_valid_type "${option:-}"; then
      TYPE="$option"
      break
    fi
    echo "Invalid selection. Choose 1, 2 or 3."
  done
}

prompt_scope() {
  while true; do
    read_prompt "Enter scope (example: profiles): " raw
    SCOPE="$(slugify "$raw")"
    if [[ -n "$SCOPE" ]] && is_valid_fragment "$SCOPE"; then
      break
    fi
    echo "Invalid scope. Use lowercase letters, numbers, dash or dot."
  done
}

prompt_feature() {
  while true; do
    read_prompt "Enter feature name (example: spring-profiles-rollout): " raw
    FEATURE="$(slugify "$raw")"
    if [[ -n "$FEATURE" ]] && is_valid_fragment "$FEATURE"; then
      break
    fi
    echo "Invalid feature name. Use lowercase letters, numbers, dash or dot."
  done
}

prompt_desc() {
  while true; do
    read_prompt "Enter commit description (example: add spring profiles rollout): " raw
    raw="$(trim_whitespace "$raw")"
    if [[ -n "$raw" ]]; then
      DEV_DESC="$raw"
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

branch_exists_remote() {
  local repo_dir="$1"
  local branch_name="$2"
  git -C "$repo_dir" ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1
}

process_repo() {
  local repo="$1"
  local type="$2"
  local branch_name="$3"
  local dir
  dir="${ROOT_DIR}/$(get_dir "$type")/${repo}"

  if [[ ! -d "$dir/.git" ]]; then
    echo "[FAIL] $repo: missing git repository at $dir"
    return 1
  fi

  if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
    echo "[FAIL] $repo: local changes detected. Commit/stash before running start-dev."
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY] $repo: git fetch origin --prune"
    echo "[DRY] $repo: git checkout main"
    echo "[DRY] $repo: git pull --ff-only origin main"
  else
    git -C "$dir" fetch origin --prune
    if git -C "$dir" show-ref --verify --quiet refs/heads/main; then
      git -C "$dir" checkout main >/dev/null
    else
      git -C "$dir" checkout -b main origin/main >/dev/null
    fi
    git -C "$dir" pull --ff-only origin main
  fi

  if git -C "$dir" show-ref --verify --quiet "refs/heads/${branch_name}"; then
    echo "[FAIL] $repo: branch already exists locally (${branch_name})"
    return 1
  fi

  if branch_exists_remote "$dir" "$branch_name"; then
    echo "[FAIL] $repo: branch already exists on origin (${branch_name})"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY] $repo: git checkout -b ${branch_name} origin/main"
  else
    git -C "$dir" checkout -b "$branch_name" origin/main >/dev/null
  fi

  echo "[OK] $repo: ${branch_name}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) TYPE="$2"; shift 2 ;;
      --scope) SCOPE="$2"; shift 2 ;;
      --feature) FEATURE="$2"; shift 2 ;;
      --description) DEV_DESC="$2"; shift 2 ;;
      --repos) REPOS_CSV="$2"; shift 2 ;;
      --all) ALL="true"; shift ;;
      --dry-run) DRY_RUN="true"; shift ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done
}

save_session() {
  local branch_name="$1"
  local repos_csv
  repos_csv="$(IFS=','; echo "${TARGET_REPOS[*]}")"

  {
    echo "# Generated by scripts/start-dev.sh"
    printf "DEV_TYPE=%q\n" "$TYPE"
    printf "DEV_SCOPE=%q\n" "$SCOPE"
    printf "DEV_FEATURE=%q\n" "$FEATURE"
    printf "DEV_BRANCH=%q\n" "$branch_name"
    printf "DEV_DESC=%q\n" "$DEV_DESC"
    printf "DEV_TARGET_REPOS=%q\n" "$repos_csv"
    printf "DEV_UPDATED_AT=%q\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$SESSION_FILE"
}

main() {
  local branch_name repo failures
  [[ -f "$WORKSPACE_FILE" ]] || { echo "workspace.yml not found"; exit 1; }
  parse_args "$@"
  load_repos

  if [[ -z "$TYPE" ]]; then
    prompt_type
  else
    TYPE="$(slugify "$TYPE")"
    is_valid_type "$TYPE" || { echo "Invalid type: $TYPE"; exit 1; }
  fi

  if [[ -z "$SCOPE" ]]; then
    prompt_scope
  else
    SCOPE="$(slugify "$SCOPE")"
    is_valid_fragment "$SCOPE" || { echo "Invalid scope: $SCOPE"; exit 1; }
  fi

  if [[ -z "$FEATURE" ]]; then
    prompt_feature
  else
    FEATURE="$(slugify "$FEATURE")"
    is_valid_fragment "$FEATURE" || { echo "Invalid feature name: $FEATURE"; exit 1; }
  fi

  if [[ -z "$DEV_DESC" ]]; then
    prompt_desc
  fi

  if [[ "$ALL" == "true" ]]; then
    select_all_repos
  elif [[ -n "$REPOS_CSV" ]]; then
    select_from_csv "$REPOS_CSV"
  else
    prompt_repos
  fi

  branch_name="${TYPE}/${SCOPE}/${FEATURE}"

  echo
  echo "Branch to create: $branch_name"
  echo "Commit description: $DEV_DESC"
  echo "Targets: ${TARGET_REPOS[*]:-}"
  [[ "$DRY_RUN" == "true" ]] && echo "Mode: dry-run"
  echo

  failures=0
  for repo in "${TARGET_REPOS[@]}"; do
    process_repo "$repo" "$(type_by_repo_name "$repo")" "$branch_name" || failures=$((failures + 1))
  done

  echo
  if (( failures > 0 )); then
    echo "Completed with ${failures} failure(s)."
    exit 1
  fi

  save_session "$branch_name"
  echo "Session saved: $SESSION_FILE"
  echo "Completed successfully."
}

main "$@"
