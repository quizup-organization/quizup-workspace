#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_FILE="${ROOT_DIR}/workspace.yml"

# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/lib/prompt.sh"

REPOS_CSV="${REPOS:-}"
ALL="${ALL:-}"
DRY_RUN="${DRY_RUN:-false}"

declare -a TARGET_REPOS=()
declare -a REPO_NAMES=()
declare -a REPO_TYPES=()
declare -a REPO_BUILDS=()
declare -a REPO_ORDERS=()

get_dir() {
  case "$1" in
    library) echo "libraries" ;;
    devops)  echo "devops" ;;
    web-application) echo "web-applications" ;;
    *) echo "services" ;;
  esac
}

load_repos() {
  local lines line name type build order
  lines="$(yq -r '.repos[] | [.name, .type, .build, (.order // 999)] | @tsv' "$WORKSPACE_FILE")"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    name="$(echo "$line" | cut -f1)"
    type="$(echo "$line" | cut -f2)"
    build="$(echo "$line" | cut -f3)"
    order="$(echo "$line" | cut -f4)"
    REPO_NAMES+=("$name")
    REPO_TYPES+=("$type")
    REPO_BUILDS+=("$build")
    REPO_ORDERS+=("$order")
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
  local idx
  idx="$(repo_index_by_name "$1")"
  [[ "$idx" == "-1" ]] && echo "" && return 1
  echo "${REPO_TYPES[$idx]}"
}

build_by_repo_name() {
  local idx
  idx="$(repo_index_by_name "$1")"
  [[ "$idx" == "-1" ]] && echo "none" && return 0
  echo "${REPO_BUILDS[$idx]}"
}

order_by_repo_name() {
  local idx
  idx="$(repo_index_by_name "$1")"
  [[ "$idx" == "-1" ]] && echo "999" && return 0
  echo "${REPO_ORDERS[$idx]}"
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
  echo "Select repositories to build:"
  echo "  0) all"
  for i in "${!REPO_NAMES[@]}"; do
    printf "  %d) %s [%s / %s]\n" "$((i + 1))" "${REPO_NAMES[$i]}" "${REPO_TYPES[$i]}" "${REPO_BUILDS[$i]}"
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
        valid=false; break
      fi
      if (( idx < 1 || idx > ${#REPO_NAMES[@]} )); then
        valid=false; break
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

sort_targets_by_order() {
  local sorted repo
  sorted="$(
    for repo in "${TARGET_REPOS[@]}"; do
      printf "%s\t%s\n" "$(order_by_repo_name "$repo")" "$repo"
    done | sort -t$'\t' -k1,1n | cut -f2
  )"

  TARGET_REPOS=()
  while IFS= read -r repo; do
    [[ -n "$repo" ]] && TARGET_REPOS+=("$repo")
  done <<< "$sorted"
}

build_repo() {
  local repo="$1"
  local type="$2"
  local build="$3"
  local dir="${ROOT_DIR}/$(get_dir "$type")/${repo}"

  if [[ ! -d "$dir" ]]; then
    echo "[WARN] $repo: directory not found at $dir — skipping"
    return 0
  fi

  case "$build" in
    maven)
      echo "  · $repo (maven)"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY] cd $dir && mvn clean install -DskipTests -q"
      else
        (cd "$dir" && mvn clean install -DskipTests -q)
      fi
      ;;
    npm)
      echo "  · $repo (npm)"
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY] cd $dir && npm install --silent"
      else
        (cd "$dir" && npm install --silent)
      fi
      ;;
    none)
      echo "  · $repo (skipped — build: none)"
      ;;
    *)
      echo "[WARN] $repo: unknown build type '$build' — skipping"
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repos)   REPOS_CSV="$2"; shift 2 ;;
      --all)     ALL="true"; shift ;;
      --dry-run) DRY_RUN="true"; shift ;;
      *) echo "Unknown option: $1"; exit 1 ;;
    esac
  done
}

main() {
  [[ -f "$WORKSPACE_FILE" ]] || { echo "workspace.yml not found"; exit 1; }
  parse_args "$@"
  load_repos

  if [[ "$ALL" == "true" ]]; then
    select_all_repos
  elif [[ -n "$REPOS_CSV" ]]; then
    select_from_csv "$REPOS_CSV"
  else
    prompt_repos
  fi

  sort_targets_by_order

  echo
  echo "▶ Building ${#TARGET_REPOS[@]} repo(s)..."
  [[ "$DRY_RUN" == "true" ]] && echo "  Mode: dry-run"
  echo

  local repo failures=0
  for repo in "${TARGET_REPOS[@]}"; do
    build_repo "$repo" "$(type_by_repo_name "$repo")" "$(build_by_repo_name "$repo")" \
      || failures=$((failures + 1))
  done

  echo
  if (( failures > 0 )); then
    echo "Build completed with ${failures} failure(s)."
    exit 1
  fi
  echo "✓ Build done"
}

main "$@"

