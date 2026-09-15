#!/usr/bin/env bash
set -uo pipefail

cd "${1:-.}" || exit 1

if [[ -n "$(git status --porcelain)" ]]; then
  echo "⚠️  Modifications locales non commitées détectées."
  echo "    Résous ou commit ça avant de continuer, pour éviter de perdre du travail."
  git status --short
  exit 1
fi

git fetch origin --quiet
branch=$(git rev-parse --abbrev-ref HEAD)
local_hash=$(git rev-parse "$branch")
remote_hash=$(git rev-parse "origin/$branch" 2>/dev/null || echo "")

if [[ -z "$remote_hash" ]]; then
  echo "ℹ️  Pas de branche distante correspondante ($branch), rien à vérifier."
  exit 0
fi

if [[ "$local_hash" != "$remote_hash" ]]; then
  echo "🔄 Le distant a changé depuis ta dernière session. Pull en cours..."
  git pull origin "$branch"
  echo "✅ À jour. Voici ce qui a changé depuis :"
  git log --oneline "$local_hash..$remote_hash"
else
  echo "✅ Déjà à jour, aucun changement distant."
fi
