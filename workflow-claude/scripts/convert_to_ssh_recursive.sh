#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="${1:-$HOME}"

echo "Recherche de tous les repos git sous $ROOT_DIR ..."

find "$ROOT_DIR" -type d -name ".git" 2>/dev/null | while read -r git_dir; do
  repo="$(dirname "$git_dir")"
  pushd "$repo" > /dev/null || continue

  current_url=$(git remote get-url origin 2>/dev/null)

  if [[ -z "$current_url" ]]; then
    echo "— $repo : pas de remote origin, ignoré"
  elif [[ "$current_url" == https://github.com/* ]]; then
    repo_path="${current_url#https://github.com/}"
    repo_path="${repo_path%.git}"
    new_url="git@github.com:${repo_path}.git"
    git remote set-url origin "$new_url"
    echo "✅ $repo : $current_url -> $new_url"
  else
    echo "— $repo : déjà en SSH ou remote non-GitHub ($current_url)"
  fi

  popd > /dev/null
done

echo "Terminé."
