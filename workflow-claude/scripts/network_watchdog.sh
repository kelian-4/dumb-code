#!/usr/bin/env bash
set -uo pipefail

# Format : "chemin_du_repo|branche_a_surveiller"
REPOS=(
  # "/chemin/vers/repo1|dev"
  # "/chemin/vers/repo2|dev"
)

CHECK_URL="https://github.com"
CHECK_INTERVAL=15

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

is_network_up() {
  curl -s -o /dev/null --max-time 5 "$CHECK_URL"
}

sync_repo() {
  local repo_path="$1"
  local branch="$2"

  if [[ ! -d "$repo_path/.git" ]]; then
    log "⚠️  $repo_path n'est pas un repo git valide, ignoré."
    return
  fi

  pushd "$repo_path" > /dev/null || return

  git fetch origin "$branch" --quiet 2>/dev/null
  local remote_hash
  remote_hash=$(git rev-parse "origin/$branch" 2>/dev/null)
  if [[ -z "$remote_hash" ]]; then
    log "⚠️  $repo_path : branche distante '$branch' introuvable."
    popd > /dev/null
    return
  fi

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  if [[ "$current_branch" == "$branch" ]]; then
    local local_hash
    local_hash=$(git rev-parse "$branch" 2>/dev/null)
    if [[ "$local_hash" == "$remote_hash" ]]; then
      log "— $repo_path [$branch] : deja synchronise."
    else
      log "🔄 Divergence detectee sur $repo_path [$branch]. Pull en cours..."
      if git pull origin "$branch" --quiet; then
        log "✅ $repo_path rattrape."
      else
        log "❌ Echec du pull sur $repo_path (conflit possible, a verifier manuellement)."
      fi
    fi
  else
    local local_ref_hash
    local_ref_hash=$(git rev-parse "$branch" 2>/dev/null || echo "")
    if [[ "$local_ref_hash" != "$remote_hash" ]]; then
      log "🔄 Divergence detectee sur $repo_path [$branch] (branche non active). Mise a jour de la ref..."
      git fetch origin "${branch}:${branch}" --quiet 2>/dev/null \
        && log "✅ Ref '$branch' mise a jour sur $repo_path." \
        || log "❌ Echec de mise a jour sur $repo_path."
    else
      log "— $repo_path [$branch] : deja synchronise (branche non active)."
    fi
  fi

  popd > /dev/null
}

sync_all_repos() {
  log "🌐 Reseau de retour apres coupure. Verification de tous les repos..."
  for entry in "${REPOS[@]}"; do
    repo_path="${entry%%|*}"
    branch="${entry##*|}"
    sync_repo "$repo_path" "$branch"
  done
  log "🌐 Verification terminee."
}

log "Demarrage du watchdog reseau (verification toutes les ${CHECK_INTERVAL}s)."

was_down=false

while true; do
  if is_network_up; then
    if [[ "$was_down" == true ]]; then
      sync_all_repos
      was_down=false
    fi
  else
    if [[ "$was_down" == false ]]; then
      log "🔴 Reseau indisponible."
    fi
    was_down=true
  fi
  sleep "$CHECK_INTERVAL"
done
