#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
JAIL_CONFIG=/etc/fail2ban/jail.d/sshd.local

[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: $ENV_FILE not found" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

SSH_PORT="${SSH_PORT:-2026}"
MAX_RETRY="${MAX_RETRY:-3}"
FIND_TIME="${FIND_TIME:-600}"
BAN_TIME="${BAN_TIME:-60}"
FAIL2BAN_BACKEND="${FAIL2BAN_BACKEND:-systemd}"

log() {
    printf '[HQ-SRV fail2ban] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

validate_positive_integer() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[1-9][0-9]*$ ]] ||
        die "$name must be a positive integer"
}

[[ $EUID -eq 0 ]] || die "run this script as root"
validate_positive_integer SSH_PORT "$SSH_PORT"
validate_positive_integer MAX_RETRY "$MAX_RETRY"
validate_positive_integer FIND_TIME "$FIND_TIME"
validate_positive_integer BAN_TIME "$BAN_TIME"
(( SSH_PORT <= 65535 )) ||
    die "SSH_PORT must be from 1 to 65535"
[[ "$FAIL2BAN_BACKEND" =~ ^[A-Za-z0-9_.-]+$ ]] ||
    die "FAIL2BAN_BACKEND contains unsupported characters"

log "Installing fail2ban and the systemd Python module"
apt-get update
apt-get install -y python3-module-systemd fail2ban

command -v fail2ban-client >/dev/null 2>&1 ||
    die "fail2ban-client was not installed"

if command -v sshd >/dev/null 2>&1; then
    if ! sshd -T 2>/dev/null |
        awk '$1 == "port" {print $2}' |
        grep -Fxq "$SSH_PORT"; then
        die "sshd is not configured for TCP port $SSH_PORT"
    fi
fi

log "Writing $JAIL_CONFIG"
install -d -m 0755 /etc/fail2ban/jail.d
cat > "$JAIL_CONFIG" <<EOF
[DEFAULT]
bantime = ${BAN_TIME}
findtime = ${FIND_TIME}

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
maxretry = ${MAX_RETRY}
backend = ${FAIL2BAN_BACKEND}
EOF
chmod 0644 "$JAIL_CONFIG"

log "Validating fail2ban configuration"
fail2ban-client -t

log "Starting fail2ban"
systemctl enable --now fail2ban
systemctl restart fail2ban

for attempt in {1..20}; do
    if fail2ban-client ping 2>/dev/null |
        grep -q 'pong'; then
        break
    fi
    if (( attempt == 20 )); then
        journalctl -u fail2ban -n 100 --no-pager >&2 || true
        die "fail2ban did not become ready"
    fi
    sleep 1
done

fail2ban-client status sshd >/dev/null 2>&1 ||
    die "the sshd jail is not active"

log "Active sshd jail"
fail2ban-client status sshd
printf 'Port: %s\n' "$SSH_PORT"
printf 'Max retry: %s\n' "$(fail2ban-client get sshd maxretry)"
printf 'Find time: %s seconds\n' "$(fail2ban-client get sshd findtime)"
printf 'Ban time: %s seconds\n' "$(fail2ban-client get sshd bantime)"
