#!/usr/bin/env bash

# Remove terminal escape sequences and non-printable control characters.
sanitize_input() {
  local raw="$1"
  local esc
  local sanitized

  esc=$'\033'

  # Drop CSI sequences (e.g. ESC [ D from arrow keys), then strip remaining control chars.
  sanitized="$(printf '%s' "$raw" | sed -E "s/${esc}\\[[0-9;?]*[[:alpha:]]//g")"
  sanitized="$(printf '%s' "$sanitized" | tr -d '[:cntrl:]')"
  sanitized="$(printf '%s' "$sanitized" | tr -d '\r')"

  printf '%s' "$sanitized"
}

trim_whitespace() {
  local raw="$1"
  printf '%s' "$raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

read_prompt() {
  local prompt="$1"
  local __result_var="$2"
  local __raw

  if [[ -t 0 ]]; then
    # Use readline for robust interactive editing when available.
    read -e -r -p "$prompt" __raw
  else
    read -r -p "$prompt" __raw
  fi

  printf -v "$__result_var" '%s' "$(sanitize_input "$__raw")"
}

