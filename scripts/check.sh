#!/usr/bin/env bash
set -euo pipefail

REQUIRED=("git" "docker" "yq" "java" "mvn" "npm")

install_hint() {
  case "$1" in
    git)    echo "brew install git" ;;
    docker) echo "https://docs.docker.com/get-docker" ;;
    yq)     echo "brew install yq" ;;
    java)   echo "brew install --cask temurin" ;;
    mvn)    echo "brew install maven" ;;
    npm)    echo "brew install node" ;;
  esac
}

OK=true
for cmd in "${REQUIRED[@]}"; do
  if command -v "$cmd" &>/dev/null; then
    echo "  ✓ $cmd"
  else
    echo "  ✗ $cmd — $(install_hint "$cmd")"
    OK=false
  fi
done

$OK || { echo ""; echo "Fix missing dependencies and retry."; exit 1; }