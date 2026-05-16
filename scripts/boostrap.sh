#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$(pwd)/workspace.yml"
ORG=$(yq '.organization' "$WORKSPACE")

get_dir() {
  case "$1" in
    library) echo "libraries" ;;
    devops)  echo "devops" ;;
    web-application)     echo "web-applications" ;;
    *)       echo "services" ;;
  esac
}

# --- .env ---
if [ ! -f .env ]; then
  cp .env.example .env
  echo "  ✓ .env créé depuis .env.example — remplis les variables manquantes et relance make init"
  exit 0
fi

set -a && source .env && set +a

[ -z "${QUIZUP_GITHUB_USERNAME:-}" ] && { echo "✗ QUIZUP_GITHUB_USERNAME manquant dans .env"; exit 1; }
[ -z "${QUIZUP_GITHUB_PASSWORD:-}" ]  && { echo "✗ QUIZUP_GITHUB_PASSWORD manquant dans .env";  exit 1; }

# --- settings.xml → ~/.m2/settings.xml ---
echo "▶ Configuration Maven..."
mkdir -p ~/.m2
envsubst < settings.xml > ~/.m2/settings.xml
echo "  ✓ settings.xml copié dans ~/.m2"

# --- Clone ---
echo "▶ Cloning repos..."
while IFS= read -r line; do
  repo=$(echo "$line" | cut -f1)
  type=$(echo "$line" | cut -f2)
  folder=$(get_dir "$type")
  dest="$folder/$repo"

  mkdir -p "$folder"
  [ -d "$dest" ] \
    && echo "  · $repo already exists" \
    || git clone "git@github.com:$ORG/$repo.git" "$dest"
done < <(yq '.repos[] | [.name, .type] | @tsv' "$WORKSPACE")

# --- Build ---
echo "▶ Building..."
while IFS= read -r line; do
  repo=$(echo "$line" | cut -f1)
  type=$(echo "$line" | cut -f2)
  build=$(echo "$line" | cut -f3)
  dir="$(get_dir "$type")/$repo"

  case "$build" in
    maven) echo "  · $repo (maven)" && (cd "$dir" && mvn clean install -DskipTests -q) ;;
    npm)   echo "  · $repo (npm)"   && (cd "$dir" && npm install --silent) ;;
    none)  ;;
  esac
done < <(yq '[.repos | sort_by(.order // 999) | .[] | [.name, .type, .build] | @tsv] | .[]' "$WORKSPACE")

echo "✓ Done"