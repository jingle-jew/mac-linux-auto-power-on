#!/usr/bin/env bash
set -Eeuo pipefail

UNIT_NAME="mac-auto-power-on.service"
UNIT_PATH="/etc/systemd/system/$UNIT_NAME"
ASSUME_YES=0

fail() {
  printf 'Erreur: %s\n' "$*" >&2
  exit 1
}

if [[ "${1:-}" == "--yes" ]]; then
  ASSUME_YES=1
elif [[ $# -gt 0 ]]; then
  fail "option inconnue: $1"
fi

(( EUID == 0 )) || fail "la désinstallation doit être exécutée avec sudo"

if [[ ! -e "$UNIT_PATH" ]]; then
  printf 'Aucun service à retirer: %s\n' "$UNIT_PATH"
  exit 0
fi

printf 'Le service suivant sera désactivé et supprimé: %s\n' "$UNIT_PATH"
printf 'Le registre PCI ne sera pas remis dans l’état opposé.\n'

if (( ! ASSUME_YES )); then
  printf 'Tapez REMOVE pour continuer: '
  read -r confirmation
  [[ "$confirmation" == "REMOVE" ]] || fail "annulé par l’utilisateur"
fi

systemctl disable --now "$UNIT_NAME"
rm -f "$UNIT_PATH"
systemctl daemon-reload
systemctl reset-failed "$UNIT_NAME" >/dev/null 2>&1 || true

printf 'Désinstallation terminée.\n'
