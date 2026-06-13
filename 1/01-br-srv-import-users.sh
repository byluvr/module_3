#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: $ENV_FILE not found." >&2
    exit 1
fi

ISO_DEVICE="${ISO_DEVICE:-/dev/sr0}"
ISO_MOUNT="${ISO_MOUNT:-/iso}"
CSV_FILE="${CSV_FILE:-$ISO_MOUNT/Users.csv}"
FSTAB=/etc/fstab

log() {
    printf '[BR-SRV user import] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
command -v samba-tool >/dev/null 2>&1 ||
    die "samba-tool was not found"
[[ -b "$ISO_DEVICE" ]] || die "$ISO_DEVICE is not a block device"
[[ "$ISO_MOUNT" == /* && "$ISO_MOUNT" != / ]] ||
    die "ISO_MOUNT must be a safe absolute path"
[[ "$CSV_FILE" == "$ISO_MOUNT/"* ]] ||
    die "CSV_FILE must be located inside $ISO_MOUNT"

log "Mounting Additional.iso"
mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    mount -o loop,ro "$ISO_DEVICE" "$ISO_MOUNT"
fi

if [[ ! -f "$CSV_FILE" ]]; then
    alternative_csv="$(
        find "$ISO_MOUNT" -maxdepth 1 -type f -iname 'users.csv' -print -quit
    )"
    [[ -n "$alternative_csv" ]] ||
        die "Users.csv was not found in $ISO_MOUNT"
    CSV_FILE="$alternative_csv"
fi

log "Adding the ISO mount to /etc/fstab"
temp_fstab="$(mktemp)"
trap 'rm -f -- "${temp_fstab:-}"' EXIT
awk -v device="$ISO_DEVICE" -v mount_point="$ISO_MOUNT" '
    /^[[:space:]]*#/ || NF == 0 {
        print
        next
    }
    $1 == device || $2 == mount_point {
        next
    }
    { print }
' "$FSTAB" > "$temp_fstab"
printf '%s %s iso9660 loop,ro,auto 0 0\n' \
    "$ISO_DEVICE" "$ISO_MOUNT" >> "$temp_fstab"
install -m 0644 "$temp_fstab" "$FSTAB"
rm -f -- "$temp_fstab"
trap - EXIT

log "Importing users from $CSV_FILE"
imported=0
while IFS=';' read -r firstname lastname role phone ou street zip city country password; do
    firstname="${firstname//$'\r'/}"
    lastname="${lastname//$'\r'/}"
    password="$(printf '%s' "$password" | tr -d '[:space:]')"

    [[ -n "$firstname" && -n "$lastname" && -n "$password" ]] ||
        continue

    username="$firstname.$lastname"
    log "Creating $username"
    samba-tool user add "$username" "$password"
    imported=$((imported + 1))
done < <(tail -n +2 "$CSV_FILE")

log "Import completed"
printf 'Imported users: %s\n' "$imported"
samba-tool user list
