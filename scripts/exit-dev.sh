#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_FILE="${ROOT_DIR}/workspace.yml"
SESSION_FILE="${ROOT_DIR}/.dev-session.env"

REPOS_CSV="${REPOS:-}"
ALL="${ALL:-}"
DRY_RUN="${DRY_RUN:-false}"

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

prompt_repos() {
  local i
  echo "Select repositories to exit dev mode:"
  echo "  0) all"
  for i in "${!REPO_NAMES[@]}"; do
    printf "  %d) %s [%s]\n" "$((i + 1))" "${REPO_NAMES[$i]}" "${REPO_TYPES[$i]}"
  done

  while true; do
    local selection old_ifs valid idx repo
    local -a idxs picked

    read -r -p "Choice (0 or comma-separated numbers): " selection
    selection="$(echo "$selection" | xargs)"
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
      idx="$(echo "$idx" | xargs)"
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

process_repo() {
  local repo="$1"
  local type="$2"
  local dir
  dir="${ROOT_DIR}/$(get_dir "$type")/${repo}"

  if [[ ! -d "$dir/.git" ]]; then
    echo "[FAIL] $repo: missing git repository at $dir"
    return 1
  fi

  if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
    echo "[FAIL] $repo: local changes detected. Commit/stash before running exit-dev."
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY] $repo: git fetch origin --prune"
    echo "[DRY] $repo: git checkout main"
    echo "[DRY] $repo: git pull --ff-only origin main"
    echo "[OK] $repo: main (dry-run)"
    return 0
  fi

  git -C "$dir" fetch origin --prune
  if git -C "$dir" show-ref --verify --quiet refs/heads/main; then
    git -C "$dir" checkout main >/dev/null
  else
    git -C "$dir" checkout -b main origin/main >/dev/null
  fi
  git -C "$dir" pull --ff-only origin main
  echo "[OK] $repo: main"
}

clear_session_if_present() {
  if [[ -f "$SESSION_FILE" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY] remove session file: $SESSION_FILE"
    else
      rm -f "$SESSION_FILE"
      echo "Session removed: $SESSION_FILE"
    fi
  fi
}

main() {
  local failures repo
  [[ -f "$WORKSPACE_FILE" ]] || { echo "workspace.yml not found"; exit 1; }
  parse_args "$@"
  load_repos

  if [[ "$ALL" == "true" ]]; then
    select_all_repos
  elif [[ -n "$REPOS_CSV" ]]; then
    select_from_csv "$REPOS_CSV"
  else
    select_all_repos
  fi

  echo
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

  clear_session_if_present
  echo "Completed successfully."
}

main "$@"

