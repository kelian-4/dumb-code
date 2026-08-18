#!/usr/bin/env bash

set -euo pipefail

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

sudo -v

(
while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
done
) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

trap 'rm -f "$TMPFILE"; kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

###############################################################################
# Language
###############################################################################

LANG_CODE="${LC_MESSAGES:-${LANG:-en}}"

if [[ "$LANG_CODE" == fr* ]]; then
    TXT_SYNC="Synchronisation des channels..."
    TXT_EVAL="Évaluation de la configuration..."
    TXT_PACKAGES="Paquets"
    TXT_SUMMARY="Résumé"
    TXT_DOWNLOAD="Taille totale du téléchargement"
    TXT_UNPACKED="Taille totale décompressée"
    TXT_CONFIRM="Appliquer ces modifications ? [O/n] "
    TXT_REBUILD="Reconstruction du système..."
    TXT_CANCEL="Annulé."
    TXT_UPTODATE="Le système est déjà à jour."
    DEFAULT_REPLY="O"
else
    TXT_SYNC="Synchronizing channels..."
    TXT_EVAL="Evaluating configuration..."
    TXT_PACKAGES="Packages"
    TXT_SUMMARY="Summary"
    TXT_DOWNLOAD="Total download size"
    TXT_UNPACKED="Total unpacked size"
    TXT_CONFIRM="Apply these changes? [Y/n] "
    TXT_REBUILD="Rebuilding system..."
    TXT_CANCEL="Cancelled."
    TXT_UPTODATE="System is already up to date."
    DEFAULT_REPLY="Y"
fi

###############################################################################
# Arguments
###############################################################################

UPDATE=0
ARGS=()

for arg in "$@"; do
    if [[ "$arg" == "--update" ]]; then
        UPDATE=1
    else
        ARGS+=("$arg")
    fi
done

###############################################################################
# Update channels
###############################################################################

if (( UPDATE )); then
    echo ":: $TXT_SYNC"
    sudo nix-channel --update
fi

###############################################################################
# Dry build
###############################################################################

echo ":: $TXT_EVAL"

if ! sudo nixos-rebuild dry-build "${ARGS[@]}" >"$TMPFILE" 2>&1; then
    cat "$TMPFILE"
    exit 1
fi

###############################################################################
# Packages
###############################################################################

PACKAGES=$(
grep -oE '/nix/store/[^ ]+\.drv' "$TMPFILE" |
sed -E 's#.*/[a-z0-9]{32}-##; s/\.drv$//' |
awk '!seen[$0]++'
)

FETCH_LINE=$(grep "will be fetched" "$TMPFILE" || true)

if [[ -z "$PACKAGES" && -z "$FETCH_LINE" ]]; then
    echo "$TXT_UPTODATE"
    exit 0
fi

PACKAGE_COUNT=$(printf '%s\n' "$PACKAGES" | grep -c .)

echo ":: $TXT_PACKAGES ($PACKAGE_COUNT)"
echo

if command -v column >/dev/null 2>&1; then
    printf '%s\n' "$PACKAGES" | column
else
    printf '%s\n' "$PACKAGES"
fi

###############################################################################
# Summary
###############################################################################

echo
echo ":: $TXT_SUMMARY"
echo

if [[ -n "$FETCH_LINE" ]]; then
    DOWNLOAD_SIZE=$(echo "$FETCH_LINE" | sed -E 's/.*\(([0-9.]+ [A-Za-z]+) download,.*/\1/')
    UNPACKED_SIZE=$(echo "$FETCH_LINE" | sed -E 's/.*, ([0-9.]+ [A-Za-z]+) unpacked.*/\1/')

    printf "  %-32s %s\n" "$TXT_DOWNLOAD:" "$DOWNLOAD_SIZE"
    printf "  %-32s %s\n" "$TXT_UNPACKED:" "$UNPACKED_SIZE"
fi

###############################################################################
# Confirmation
###############################################################################

echo
read -rp "$TXT_CONFIRM" ANSWER
ANSWER=${ANSWER:-$DEFAULT_REPLY}

case "$ANSWER" in
    [oOyY]*)

        echo
        echo ":: $TXT_REBUILD"

	if command -v nh >/dev/null 2>&1; then
    if [[ "${NIXOS_CONFIG:-/etc/nixos/configuration.nix}" == "/etc/nixos/configuration.nix" ]]; then
        nh os switch -f '<nixpkgs/nixos>' "${ARGS[@]}"
    else
        nh os switch -f '<nixpkgs/nixos>' -- \
            -I "nixos-config=${NIXOS_CONFIG}" \
            "${ARGS[@]}"
    fi
elif command -v nom >/dev/null 2>&1; then
    sudo nixos-rebuild switch "${ARGS[@]}" |& nom
else
    sudo nixos-rebuild switch "${ARGS[@]}"
fi
        ;;

    *)

        echo "$TXT_CANCEL"
        exit 0
        ;;

esac
