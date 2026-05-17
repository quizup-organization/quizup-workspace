#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_FILE="${ROOT_DIR}/workspace.yml"
SESSION_FILE="${ROOT_DIR}/.dev-session.env"

REPOS_CSV="${REPOS:-}"
ALL="${ALL:-}"

declare -a TARGET_REPOS=()
declare -a REPO_NAMES=()
declare -a REPO_TYPES=()

green() { printf "\033[32m%s\033[0m" "$1"; }
yellow() { printf "\033[33m%s\033[0m" "$1"; }
red() { printf "\033[31m%s\033[0m" "$1"; }

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
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done
}

print_session() {
  echo "=== Active dev session ==="
  if [[ -f "$SESSION_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$SESSION_FILE"
    echo "Type        : ${DEV_TYPE:-n/a}"
    echo "Scope       : ${DEV_SCOPE:-n/a}"
    echo "Feature     : ${DEV_FEATURE:-n/a}"
    echo "Branch      : ${DEV_BRANCH:-n/a}"
    echo "Description : ${DEV_DESC:-n/a}"
    echo "Repos       : ${DEV_TARGET_REPOS:-n/a}"
    echo "Updated at  : ${DEV_UPDATED_AT:-n/a}"
  else
    echo "No active session file (.dev-session.env)."
  fi
  echo
}

print_repo_status() {
  local repo="$1"
  local type="$2"
  local dir branch dirty count branch_label dirty_label
  dir="${ROOT_DIR}/$(get_dir "$type")/${repo}"

  if [[ ! -d "$dir/.git" ]]; then
    printf "%-28s %-17s %-20s %-10s\n" "$repo" "$type" "MISSING_REPO" "n/a"
    return
  fi

  branch="$(git -C "$dir" branch --show-current)"
  [[ -z "$branch" ]] && branch="DETACHED"

  count="$(git -C "$dir" status --short | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    dirty="clean"
    dirty_label="$(green "$dirty")"
  else
    dirty="dirty($count)"
    dirty_label="$(red "$dirty")"
  fi

  if [[ "$branch" == "main" ]]; then
    branch_label="$(green "$branch")"
  else
    branch_label="$(yellow "$branch")"
  fi

  printf "%-28s %-17s %-20s %-10b\n" "$repo" "$type" "$branch_label" "$dirty_label"
}

main() {
  local repo
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

  print_session

  echo "=== Repository status ==="
  printf "%-28s %-17s %-20s %-10s\n" "Repository" "Type" "Branch" "State"
  printf "%-28s %-17s %-20s %-10s\n" "----------------------------" "-----------------" "--------------------" "----------"

  for repo in "${TARGET_REPOS[@]}"; do
    print_repo_status "$repo" "$(type_by_repo_name "$repo")"
  done
}

main "$@"

