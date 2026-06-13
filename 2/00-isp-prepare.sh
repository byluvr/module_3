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

SSH_USER="${SSH_USER:-sshuser}"
SSH_PASSWORD="${SSH_PASSWORD:-P@ssw0rd}"
ISP_SSH_PORT="${ISP_SSH_PORT:?ISP_SSH_PORT is required in $ENV_FILE}"
SSHD_CONFIG=/etc/openssh/sshd_config

log() {
    printf '[ISP prepare] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
    die "SSH_USER contains unsupported characters"
[[ -n "$SSH_PASSWORD" && "$SSH_PASSWORD" != *$'\n'* ]] ||
    die "SSH_PASSWORD must not be empty or contain a newline"
[[ "$ISP_SSH_PORT" =~ ^[0-9]+$ ]] &&
    (( ISP_SSH_PORT >= 1 && ISP_SSH_PORT <= 65535 )) ||
    die "ISP_SSH_PORT must be from 1 to 65535"

log "Installing nginx, OpenSSH and TLS tools"
apt-get update
apt-get install -y \
    nginx \
    openssh-server \
    openssl \
    curl \
    apache2-htpasswd

command -v openssl >/dev/null 2>&1 ||
    die "openssl was not installed"

if ! id "$SSH_USER" >/dev/null 2>&1; then
    log "Creating $SSH_USER"
    useradd -m -s /bin/bash "$SSH_USER"
fi
printf '%s:%s\n' "$SSH_USER" "$SSH_PASSWORD" | chpasswd

log "Starting SSH"
ssh-keygen -A
[[ -f "$SSHD_CONFIG" ]] || die "$SSHD_CONFIG was not found"
temp_sshd_config="$(mktemp)"
trap 'rm -f -- "${temp_sshd_config:-}"' EXIT
awk '
    $0 == "# BEGIN MODULE_3_TASK_2" {
        in_managed_block = 1
        next
    }
    $0 == "# END MODULE_3_TASK_2" {
        in_managed_block = 0
        next
    }
    in_managed_block {
        next
    }
    /^[[:space:]]*Port[[:space:]]+/ {
        print "# Disabled by module_3 task 2: " $0
        next
    }
    { print }
' "$SSHD_CONFIG" > "$temp_sshd_config"
cat >> "$temp_sshd_config" <<EOF

# BEGIN MODULE_3_TASK_2
Port $ISP_SSH_PORT
# END MODULE_3_TASK_2
EOF
sshd -t -f "$temp_sshd_config"
install -m 0600 "$temp_sshd_config" "$SSHD_CONFIG"
rm -f -- "$temp_sshd_config"
trap - EXIT
systemctl enable --now sshd
systemctl restart sshd
systemctl is-active --quiet sshd || die "sshd is not running"

log "ISP preparation completed"
printf 'SSH port: %s\n' "$ISP_SSH_PORT"
