#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="${1:-$HOME/code}"
BRANCH_NAME="${2:-dev}"

echo "Création de la branche '$BRANCH_NAME' sur tous les repos sous $ROOT_DIR ..."

find "$ROOT_DIR" -type d -name ".git" 2>/dev/null | while read -r git_dir; do
  repo="$(dirname "$git_dir")"
  pushd "$repo" > /dev/null || continue

  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo "— $repo : la branche '$BRANCH_NAME' existe déjà localement, ignoré."
  else
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    git checkout -b "$BRANCH_NAME" --quiet
    if git push -u origin "$BRANCH_NAME" --quiet 2>/dev/null; then
      echo "✅ $repo : branche '$BRANCH_NAME' créée et poussée."
    else
      echo "⚠️  $repo : branche '$BRANCH_NAME' créée localement, mais échec du push (pas de remote ? auth ?)."
    fi
    git checkout "$current_branch" --quiet
  fi

  popd > /dev/null
done

echo "Terminé."
