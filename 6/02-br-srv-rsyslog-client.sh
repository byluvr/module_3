#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
RSYSLOG_CONFIG=/etc/rsyslog.d/30-au-team-forward-warning.conf

[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: $ENV_FILE not found" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

LOG_SERVER_IP="${LOG_SERVER_IP:?LOG_SERVER_IP is required in $ENV_FILE}"
LOG_SERVER_PORT="${LOG_SERVER_PORT:?LOG_SERVER_PORT is required in $ENV_FILE}"
LOG_PROTOCOL="${LOG_PROTOCOL:-tcp}"

log() {
    printf '[BR-SRV rsyslog] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ "$LOG_SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
    die "LOG_SERVER_IP is not an IPv4 address"
[[ "$LOG_SERVER_PORT" =~ ^[0-9]+$ ]] &&
    (( LOG_SERVER_PORT >= 1 && LOG_SERVER_PORT <= 65535 )) ||
    die "LOG_SERVER_PORT must be from 1 to 65535"
[[ "$LOG_PROTOCOL" == tcp || "$LOG_PROTOCOL" == udp ]] ||
    die "LOG_PROTOCOL must be tcp or udp"

log "Installing rsyslog"
apt-get update
if ! apt-get install -y rsyslog rsyslog-journal; then
    log "rsyslog-journal is unavailable; installing rsyslog only"
    apt-get install -y rsyslog
fi

log "Writing warning-or-higher forwarding rule"
cat > "$RSYSLOG_CONFIG" <<EOF
*.warning action(
    type="omfwd"
    target="${LOG_SERVER_IP}"
    port="${LOG_SERVER_PORT}"
    protocol="${LOG_PROTOCOL}"
    action.resumeRetryCount="-1"
    queue.type="linkedList"
)
EOF

rsyslogd -N1
systemctl enable --now rsyslog
systemctl restart rsyslog

log "Sending a warning test message"
logger -p user.warning -t AU-TEAM-RSYSLOG \
    "warning test from $(hostname) at $(date '+%Y-%m-%d %H:%M:%S %z')"

log "Forwarding *.warning to ${LOG_SERVER_IP}:${LOG_SERVER_PORT}/${LOG_PROTOCOL}"
