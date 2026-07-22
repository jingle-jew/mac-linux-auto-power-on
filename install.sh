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

Without --apply, the script only performs a diagnostic.

Options:
  --apply                 Install and enable the systemd service
  --yes                   Do not prompt for the APPLY confirmation
  --pci-device BDF        Restrict detection to a specific PCI function
  --list-profiles         List available hardware profiles
  -h, --help              Show this help message
USAGE
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
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
    fail "Invalid PCI BDF: $1"
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

  [[ "$PROFILE_ID" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || fail "invalid profile_id in $file"
  [[ -n "$DESCRIPTION" && "$DESCRIPTION" != *$'\n'* ]] || fail "invalid description in $file"
  [[ "$PROFILE_SYSTEM_PRODUCT" =~ ^[A-Za-z0-9][A-Za-z0-9,._+-]*$ ]] || fail "invalid system_product in $file"
  [[ "$PCI_VENDOR_DEVICE" =~ ^[0-9a-f]{4}:[0-9a-f]{4}$ ]] || fail "invalid pci_vendor_device in $file"
  [[ "$PCI_CLASS" =~ ^[0-9a-f]{4}$ ]] || fail "invalid pci_class in $file"
  [[ "$REGISTER" =~ ^0x[0-9a-f]+\.[bwl]$ ]] || fail "invalid register in $file"
  [[ "$OPERATION" == "masked-write" || "$OPERATION" == "write" ]] || fail "invalid operation in $file"
  [[ "$WRITE_VALUE" =~ ^(0x)?[0-9a-f]+$ ]] || fail "invalid write_value in $file"

  if [[ "$OPERATION" == "masked-write" ]]; then
    [[ "$WRITE_MASK" =~ ^(0x)?[0-9a-f]+$ ]] || fail "invalid write_mask in $file"
  elif [[ -n "$WRITE_MASK" ]]; then
    fail "write_mask must be empty for a write operation in $file"
  fi

  [[ -n "$SOURCE_NOTE" && "$SOURCE_NOTE" != *$'\n'* ]] || fail "invalid source_note in $file"
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
        printf 'Install the pciutils package using the package manager for your distribution.\n'
      fi
      ;;
  esac
}

hex_to_dec() {
  local value="${1#0x}"
  [[ "$value" =~ ^[0-9A-Fa-f]+$ ]] || fail "invalid hexadecimal value: $1"
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
      (($#)) || fail "--pci-device requires a value"
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
      fail "unknown option: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == "Linux" ]] || fail "this script only runs on Linux"
[[ -d "$PROFILE_DIR" ]] || fail "profile directory not found: $PROFILE_DIR"
[[ -r "$UNIT_TEMPLATE" ]] || fail "systemd template not found: $UNIT_TEMPLATE"

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
  printf 'The lspci program is missing.\nSuggested command: ' >&2
  package_hint >&2
  fail "install pciutils and run the script again"
}

SYSTEM_PRODUCT="$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\000\r\n' || true)"
SYSTEM_VERSION="$(cat /sys/class/dmi/id/product_version 2>/dev/null | tr -d '\000\r\n' || true)"
[[ -n "$SYSTEM_PRODUCT" ]] || fail "the DMI model could not be determined; no PCI write will be performed"

PCI_LIST="$(lspci -Dn)"
[[ -n "$PCI_LIST" ]] || fail "lspci returned no devices"

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
  printf '\nNo compatible hardware profile was found.\n' >&2
  printf 'Distribution       : %s\n' "$DISTRO_NAME" >&2
  printf 'DMI model          : %s\n' "$SYSTEM_PRODUCT" >&2
  if [[ -n "$PCI_DEVICE_OVERRIDE" ]]; then
    printf 'Required PCI device: %s\n' "$PCI_DEVICE_OVERRIDE" >&2
  fi
  printf 'Detected ISA/LPC controllers:\n' >&2
  lspci -nn | grep -Ei 'ISA bridge|LPC' >&2 || true
  fail "no PCI write was performed"
fi

(( MATCH_COUNT == 1 )) || fail "multiple profiles matched; no PCI write was performed"

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
printf 'DMI model        : %s\n' "$SYSTEM_PRODUCT"
printf 'DMI version      : %s\n' "${SYSTEM_VERSION:-unknown}"
printf 'Profile          : %s\n' "$PROFILE_ID"
printf 'Description      : %s\n' "$DESCRIPTION"
printf 'PCI function     : %s\n' "$PCI_DEVICE"
printf 'PCI identifier   : %s\n' "$PCI_VENDOR_DEVICE"
printf 'Register         : %s\n' "$REGISTER"
printf 'Operation        : %s\n' "$OPERATION"
printf 'Source/validation: %s\n' "$SOURCE_NOTE"
printf 'Planned command  : %s\n\n' "$COMMAND_DISPLAY"

if [[ -z "$SETPCI_PATH" ]]; then
  printf 'setpci is missing. Suggested command: '
  package_hint
  (( ! APPLY )) || fail "install pciutils before applying the configuration"
fi

if [[ -z "$SYSTEMD_PATH" ]]; then
  warn "systemctl is missing; service installation is not possible"
  (( ! APPLY )) || fail "systemd is required for --apply"
fi

if (( ! APPLY )); then
  printf 'Diagnostic complete. No changes were made.\n'
  printf 'To install: sudo ./install.sh --apply\n'
  exit 0
fi

(( EUID == 0 )) || fail "--apply must be run with sudo"
[[ -n "$SETPCI_PATH" ]] || fail "setpci is missing"
[[ -n "$SYSTEMD_PATH" ]] || fail "systemctl is missing"
[[ -d /run/systemd/system ]] || fail "systemd does not appear to be the active service manager on this system"
[[ ! -e "$UNIT_PATH" ]] || fail "$UNIT_PATH already exists; uninstall or inspect it before continuing"

BEFORE_VALUE="$($SETPCI_PATH -s "$PCI_DEVICE" "$REGISTER")" || fail "unable to read the register"
printf 'Current register value: %s\n' "$BEFORE_VALUE"

if (( ! ASSUME_YES )); then
  printf '\nThis operation will create %s, enable the service, and write to the specified PCI register.\n' "$UNIT_PATH"
  printf 'Type APPLY to continue: '
  read -r confirmation
  [[ "$confirmation" == "APPLY" ]] || fail "cancelled by the user"
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
  fail "activation failed; the newly installed service was removed"
fi

AFTER_VALUE="$($SETPCI_PATH -s "$PCI_DEVICE" "$REGISTER")" || fail "the service was installed, but the register could not be read again"
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
  warn "register verification failed; the service was removed"
  warn "before=$BEFORE_VALUE after=$AFTER_VALUE expected=$WRITE_VALUE mask=${WRITE_MASK:-none}"
  warn "the value written to the register may remain active until the next power cycle"
  exit 2
fi

printf '\nInstallation successful.\n'
printf 'Value before: %s\n' "$BEFORE_VALUE"
printf 'Value after: %s\n' "$AFTER_VALUE"
printf 'Service: %s\n' "$UNIT_PATH"
printf 'Then perform a real power-loss and power-restoration test.\n'
