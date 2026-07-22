#!/usr/bin/env bash
set -Eeuo pipefail

UNIT_NAME="mac-auto-power-on.service"
UNIT_PATH="/etc/systemd/system/$UNIT_NAME"
ASSUME_YES=0

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [[ "${1:-}" == "--yes" ]]; then
  ASSUME_YES=1
elif [[ $# -gt 0 ]]; then
  fail "unknown option: $1"
fi

(( EUID == 0 )) || fail "uninstallation must be run with sudo"

if [[ ! -e "$UNIT_PATH" ]]; then
  printf 'No service to remove: %s\n' "$UNIT_PATH"
  exit 0
fi

printf 'The following service will be disabled and removed: %s\n' "$UNIT_PATH"
printf 'The PCI register will not be forced into the opposite state.\n'

if (( ! ASSUME_YES )); then
  printf 'Type REMOVE to continue: '
  read -r confirmation
  [[ "$confirmation" == "REMOVE" ]] || fail "cancelled by the user"
fi

systemctl disable --now "$UNIT_NAME"
rm -f "$UNIT_PATH"
systemctl daemon-reload
systemctl reset-failed "$UNIT_NAME" >/dev/null 2>&1 || true

printf 'Uninstallation complete.\n'
