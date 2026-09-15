#!/usr/bin/env bash
set -uo pipefail

# Format : "chemin_du_repo|branche_a_surveiller"
REPOS=(
  # "/chemin/vers/repo1|dev"
  # "/chemin/vers/repo2|dev"
)

INTERVAL=60

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_and_pull() {
  local repo_path="$1"
  local watch_branch="$2"

  if [[ ! -d "$repo_path/.git" ]]; then
    log "⚠️  $repo_path n'est pas un repo git valide, ignoré."
    return
  fi

  pushd "$repo_path" > /dev/null || return

  git fetch origin "$watch_branch" --quiet 2>/dev/null

  local remote_hash
  remote_hash=$(git rev-parse "origin/$watch_branch" 2>/dev/null)
  if [[ -z "$remote_hash" ]]; then
    log "⚠️  $repo_path : la branche distante '$watch_branch' n'existe pas."
    popd > /dev/null
    return
  fi

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  if [[ "$current_branch" == "$watch_branch" ]]; then
    local local_hash
    local_hash=$(git rev-parse "$watch_branch" 2>/dev/null)

    if [[ "$local_hash" == "$remote_hash" ]]; then
      log "— $repo_path [$watch_branch] : aucun changement."
    else
      log "🔄 Changement détecté sur $repo_path [$watch_branch] (branche courante). Pull en cours..."
      if git pull origin "$watch_branch" --quiet; then
        log "✅ $repo_path mis à jour."
      else
        log "❌ Échec du pull sur $repo_path (conflit possible, à résoudre manuellement)."
      fi
    fi
  else
    local local_ref_hash
    local_ref_hash=$(git rev-parse "$watch_branch" 2>/dev/null || echo "")

    if [[ "$local_ref_hash" == "$remote_hash" ]]; then
      log "— $repo_path [$watch_branch] : aucun changement (branche non active)."
    else
      log "🔄 Changement détecté sur $repo_path [$watch_branch] (branche non active, mise à jour de la réf locale)..."
      if git fetch origin "${watch_branch}:${watch_branch}" --quiet 2>/dev/null; then
        log "✅ Réf locale de '$watch_branch' mise à jour sur $repo_path."
      else
        log "❌ Échec de mise à jour de '$watch_branch' sur $repo_path (peut-être déjà divergente localement)."
      fi
    fi
  fi

  popd > /dev/null
}

log "Démarrage de la surveillance (${#REPOS[@]} repo(s), intervalle ${INTERVAL}s). Ctrl+C pour arrêter."

while true; do
  for entry in "${REPOS[@]}"; do
    repo_path="${entry%%|*}"
    branch="${entry##*|}"
    check_and_pull "$repo_path" "$branch"
  done
  sleep "$INTERVAL"
done
