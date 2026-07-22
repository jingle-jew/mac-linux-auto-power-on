#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/profiles"
UNIT_TEMPLATE="$SCRIPT_DIR/systemd/mac-auto-power-on.service.in"
UNIT_PATH="/etc/systemd/system/mac-auto-power-on.service"
APPLY=0
ASSUME_YES=0
PCI_DEVICE_OVERRIDE=""

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Sans --apply, le script effectue uniquement un diagnostic.

Options:
  --apply                 Installer et activer le service systemd
  --yes                   Ne pas demander de taper APPLY
  --pci-device BDF        Limiter la détection à une fonction PCI précise
  --list-profiles         Afficher les profils disponibles
  -h, --help              Afficher cette aide
USAGE
}

fail() {
  printf 'Erreur: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Avertissement: %s\n' "$*" >&2
}

profile_value() {
  local file="$1" key="$2"
  awk -F= -v wanted="$key" '
    $0 !~ /^[[:space:]]*#/ && $1 == wanted {
      sub(/^[^=]*=/, "")
      print
      exit
    }
  ' "$file"
}

normalize_bdf() {
  local value="${1,,}"
  if [[ "$value" =~ ^[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]]; then
    printf '0000:%s\n' "$value"
  elif [[ "$value" =~ ^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]$ ]]; then
    printf '%s\n' "$value"
  else
    fail "BDF PCI invalide: $1"
  fi
}

validate_profile() {
  local file="$1"

  PROFILE_ID="$(profile_value "$file" profile_id)"
  DESCRIPTION="$(profile_value "$file" description)"
  PROFILE_SYSTEM_PRODUCT="$(profile_value "$file" system_product)"
  PCI_VENDOR_DEVICE="$(profile_value "$file" pci_vendor_device)"
  PCI_CLASS="$(profile_value "$file" pci_class)"
  REGISTER="$(profile_value "$file" register)"
  OPERATION="$(profile_value "$file" operation)"
  WRITE_VALUE="$(profile_value "$file" write_value)"
  WRITE_MASK="$(profile_value "$file" write_mask)"
  SOURCE_NOTE="$(profile_value "$file" source_note)"

  [[ "$PROFILE_ID" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "profile_id invalide dans $file"
  [[ -n "$DESCRIPTION" && "$DESCRIPTION" != *$'\n'* ]] || fail "description invalide dans $file"
  [[ "$PROFILE_SYSTEM_PRODUCT" =~ ^[A-Za-z0-9][A-Za-z0-9,._+-]*$ ]] || fail "system_product invalide dans $file"
  [[ "$PCI_VENDOR_DEVICE" =~ ^[0-9a-f]{4}:[0-9a-f]{4}$ ]] || fail "pci_vendor_device invalide dans $file"
  [[ "$PCI_CLASS" =~ ^[0-9a-f]{4}$ ]] || fail "pci_class invalide dans $file"
  [[ "$REGISTER" =~ ^0x[0-9a-f]+\.[bwl]$ ]] || fail "register invalide dans $file"
  [[ "$OPERATION" == "masked-write" || "$OPERATION" == "write" ]] || fail "operation invalide dans $file"
  [[ "$WRITE_VALUE" =~ ^(0x)?[0-9a-f]+$ ]] || fail "write_value invalide dans $file"

  if [[ "$OPERATION" == "masked-write" ]]; then
    [[ "$WRITE_MASK" =~ ^(0x)?[0-9a-f]+$ ]] || fail "write_mask invalide dans $file"
  elif [[ -n "$WRITE_MASK" ]]; then
    fail "write_mask doit être vide pour une opération write dans $file"
  fi

  [[ -n "$SOURCE_NOTE" && "$SOURCE_NOTE" != *$'\n'* ]] || fail "source_note invalide dans $file"
}

list_profiles() {
  local file
  shopt -s nullglob
  for file in "$PROFILE_DIR"/*.conf; do
    validate_profile "$file"
    printf '%-38s %-12s %s [%s]\n' \
      "$PROFILE_ID" "$PROFILE_SYSTEM_PRODUCT" "$DESCRIPTION" "$PCI_VENDOR_DEVICE"
  done
}

package_hint() {
  local id="${DISTRO_ID:-unknown}" like=" ${DISTRO_ID_LIKE:-} "

  case "$id" in
    debian|ubuntu|linuxmint|pop)
      printf 'sudo apt update && sudo apt install pciutils\n'
      ;;
    fedora)
      printf 'sudo dnf install pciutils\n'
      ;;
    rhel|centos|rocky|almalinux)
      printf 'sudo dnf install pciutils\n'
      ;;
    *)
      if [[ "$like" == *" debian "* ]]; then
        printf 'sudo apt update && sudo apt install pciutils\n'
      elif [[ "$like" == *" fedora "* || "$like" == *" rhel "* ]]; then
        printf 'sudo dnf install pciutils\n'
      else
        printf 'Installez le paquet pciutils avec le gestionnaire de paquets de votre distribution.\n'
      fi
      ;;
  esac
}

hex_to_dec() {
  local value="${1#0x}"
  [[ "$value" =~ ^[0-9A-Fa-f]+$ ]] || fail "valeur hexadécimale invalide: $1"
  printf '%d\n' "$((16#$value))"
}

while (($#)); do
  case "$1" in
    --apply)
      APPLY=1
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    --pci-device)
      shift
      (($#)) || fail "--pci-device exige une valeur"
      PCI_DEVICE_OVERRIDE="$(normalize_bdf "$1")"
      ;;
    --list-profiles)
      list_profiles
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "option inconnue: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == "Linux" ]] || fail "ce script fonctionne uniquement sous Linux"
[[ -d "$PROFILE_DIR" ]] || fail "dossier de profils absent: $PROFILE_DIR"
[[ -r "$UNIT_TEMPLATE" ]] || fail "modèle systemd absent: $UNIT_TEMPLATE"

DISTRO_ID="unknown"
DISTRO_ID_LIKE=""
DISTRO_NAME="Linux"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_ID_LIKE="${ID_LIKE:-}"
  DISTRO_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
fi

command -v lspci >/dev/null 2>&1 || {
  printf 'Le programme lspci est absent.\nCommande suggérée: ' >&2
  package_hint >&2
  fail "installez pciutils puis relancez le script"
}

SYSTEM_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\000\r\n' || true)"
SYSTEM_VERSION="$(cat /sys/class/dmi/id/product_version 2>/dev/null | tr -d '\000\r\n' || true)"
[[ -n "$SYSTEM_PRODUCT" ]] || fail "le modèle DMI est introuvable; aucune écriture PCI ne sera effectuée"

PCI_LIST="$(lspci -Dn)"
[[ -n "$PCI_LIST" ]] || fail "lspci n’a retourné aucun périphérique"

MATCH_COUNT=0
MATCH_PROFILE=""
MATCH_LINE=""

shopt -s nullglob
for profile in "$PROFILE_DIR"/*.conf; do
  validate_profile "$profile"
  [[ "$SYSTEM_PRODUCT" == "$PROFILE_SYSTEM_PRODUCT" ]] || continue

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    bdf="$(awk '{print $1}' <<<"$line")"
    class="$(awk '{print $2}' <<<"$line" | tr -d ':')"
    id="$(awk '{print $3}' <<<"$line")"

    [[ "$id" == "$PCI_VENDOR_DEVICE" ]] || continue
    [[ "$class" == "$PCI_CLASS" ]] || continue
    [[ -z "$PCI_DEVICE_OVERRIDE" || "$bdf" == "$PCI_DEVICE_OVERRIDE" ]] || continue

    MATCH_COUNT=$((MATCH_COUNT + 1))
    MATCH_PROFILE="$profile"
    MATCH_LINE="$line"
  done <<<"$PCI_LIST"
done

if (( MATCH_COUNT == 0 )); then
  printf '\nAucun profil matériel compatible n’a été trouvé.\n' >&2
  printf 'Distribution       : %s\n' "$DISTRO_NAME" >&2
  printf 'Modèle DMI         : %s\n' "$SYSTEM_PRODUCT" >&2
  if [[ -n "$PCI_DEVICE_OVERRIDE" ]]; then
    printf 'Fonction PCI exigée: %s\n' "$PCI_DEVICE_OVERRIDE" >&2
  fi
  printf 'Contrôleurs ISA/LPC détectés:\n' >&2
  lspci -nn | grep -Ei 'ISA bridge|LPC' >&2 || true
  fail "aucune écriture PCI n’a été effectuée"
fi

(( MATCH_COUNT == 1 )) || fail "plusieurs profils correspondent; aucune écriture PCI n’a été effectuée"

validate_profile "$MATCH_PROFILE"
PCI_DEVICE="$(awk '{print $1}' <<<"$MATCH_LINE")"
SETPCI_PATH="$(command -v setpci || true)"
SYSTEMD_PATH="$(command -v systemctl || true)"

if [[ "$OPERATION" == "masked-write" ]]; then
  SETPCI_ARGUMENT="$REGISTER=$WRITE_VALUE:$WRITE_MASK"
else
  SETPCI_ARGUMENT="$REGISTER=$WRITE_VALUE"
fi

COMMAND_DISPLAY="${SETPCI_PATH:-setpci} -s $PCI_DEVICE $SETPCI_ARGUMENT"

printf '\nDistribution      : %s\n' "$DISTRO_NAME"
printf 'Modèle DMI       : %s\n' "$SYSTEM_PRODUCT"
printf 'Version DMI      : %s\n' "${SYSTEM_VERSION:-inconnue}"
printf 'Profil           : %s\n' "$PROFILE_ID"
printf 'Description      : %s\n' "$DESCRIPTION"
printf 'Fonction PCI     : %s\n' "$PCI_DEVICE"
printf 'Identifiant PCI  : %s\n' "$PCI_VENDOR_DEVICE"
printf 'Registre         : %s\n' "$REGISTER"
printf 'Opération        : %s\n' "$OPERATION"
printf 'Source/validation: %s\n' "$SOURCE_NOTE"
printf 'Commande prévue  : %s\n\n' "$COMMAND_DISPLAY"

if [[ -z "$SETPCI_PATH" ]]; then
  printf 'setpci est absent. Commande suggérée: '
  package_hint
  (( ! APPLY )) || fail "installez pciutils avant l’installation"
fi

if [[ -z "$SYSTEMD_PATH" ]]; then
  warn "systemctl est absent; l’installation du service n’est pas possible"
  (( ! APPLY )) || fail "systemd est requis pour --apply"
fi

if (( ! APPLY )); then
  printf 'Diagnostic terminé. Aucune modification effectuée.\n'
  printf 'Pour installer: sudo ./install.sh --apply\n'
  exit 0
fi

(( EUID == 0 )) || fail "--apply doit être exécuté avec sudo"
[[ -n "$SETPCI_PATH" ]] || fail "setpci est absent"
[[ -n "$SYSTEMD_PATH" ]] || fail "systemctl est absent"
[[ -d /run/systemd/system ]] || fail "systemd ne semble pas être le gestionnaire actif de cette machine"
[[ ! -e "$UNIT_PATH" ]] || fail "$UNIT_PATH existe déjà; désinstallez ou inspectez-le avant de continuer"

BEFORE_VALUE="$($SETPCI_PATH -s "$PCI_DEVICE" "$REGISTER")" || fail "lecture du registre impossible"
printf 'Valeur actuelle du registre: %s\n' "$BEFORE_VALUE"

if (( ! ASSUME_YES )); then
  printf '\nCette opération va créer %s, activer le service et écrire dans le registre PCI indiqué.\n' "$UNIT_PATH"
  printf 'Tapez APPLY pour continuer: '
  read -r confirmation
  [[ "$confirmation" == "APPLY" ]] || fail "annulé par l’utilisateur"
fi

TMP_UNIT="$(mktemp)"
cleanup() {
  rm -f "$TMP_UNIT"
}
trap cleanup EXIT

sed \
  -e "s|@SETPCI@|$SETPCI_PATH|g" \
  -e "s|@PCI_DEVICE@|$PCI_DEVICE|g" \
  -e "s|@SETPCI_ARGUMENT@|$SETPCI_ARGUMENT|g" \
  "$UNIT_TEMPLATE" > "$TMP_UNIT"

install -o root -g root -m 0644 "$TMP_UNIT" "$UNIT_PATH"

if ! systemctl daemon-reload || ! systemctl enable --now mac-auto-power-on.service; then
  systemctl disable --now mac-auto-power-on.service >/dev/null 2>&1 || true
  rm -f "$UNIT_PATH"
  systemctl daemon-reload >/dev/null 2>&1 || true
  fail "activation échouée; le nouveau service a été retiré"
fi

AFTER_VALUE="$($SETPCI_PATH -s "$PCI_DEVICE" "$REGISTER")" || fail "service installé, mais relecture du registre impossible"
AFTER_DEC="$(hex_to_dec "$AFTER_VALUE")"
VALUE_DEC="$(hex_to_dec "$WRITE_VALUE")"

VERIFIED=0
if [[ "$OPERATION" == "masked-write" ]]; then
  MASK_DEC="$(hex_to_dec "$WRITE_MASK")"
  if (( (AFTER_DEC & MASK_DEC) == (VALUE_DEC & MASK_DEC) )); then
    VERIFIED=1
  fi
elif (( AFTER_DEC == VALUE_DEC )); then
  VERIFIED=1
fi

if (( ! VERIFIED )); then
  systemctl disable --now mac-auto-power-on.service >/dev/null 2>&1 || true
  rm -f "$UNIT_PATH"
  systemctl daemon-reload >/dev/null 2>&1 || true
  warn "la vérification du registre a échoué; le service a été retiré"
  warn "avant=$BEFORE_VALUE après=$AFTER_VALUE attendu=$WRITE_VALUE masque=${WRITE_MASK:-aucun}"
  warn "la valeur écrite dans le registre peut rester active jusqu’au prochain cycle d’alimentation"
  exit 2
fi

printf '\nInstallation réussie.\n'
printf 'Valeur avant: %s\n' "$BEFORE_VALUE"
printf 'Valeur après: %s\n' "$AFTER_VALUE"
printf 'Service: %s\n' "$UNIT_PATH"
printf 'Effectuez ensuite un test réel de perte et de retour d’alimentation.\n'
