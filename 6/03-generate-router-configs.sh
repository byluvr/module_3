#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
HQ_CONFIG="$SCRIPT_DIR/HQ-RTR.conf"
BR_CONFIG="$SCRIPT_DIR/BR-RTR.conf"

[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: $ENV_FILE not found" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

LOG_SERVER_IP="${LOG_SERVER_IP:?LOG_SERVER_IP is required in $ENV_FILE}"
LOG_SERVER_PORT="${LOG_SERVER_PORT:?LOG_SERVER_PORT is required in $ENV_FILE}"
LOG_PROTOCOL="${LOG_PROTOCOL:-tcp}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ "$LOG_SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
    die "LOG_SERVER_IP is not an IPv4 address"
[[ "$LOG_SERVER_PORT" =~ ^[0-9]+$ ]] &&
    (( LOG_SERVER_PORT >= 1 && LOG_SERVER_PORT <= 65535 )) ||
    die "LOG_SERVER_PORT must be from 1 to 65535"
[[ "$LOG_PROTOCOL" == tcp || "$LOG_PROTOCOL" == udp ]] ||
    die "LOG_PROTOCOL must be tcp or udp"

write_config() {
    local output_file="$1"

    cat > "$output_file" <<EOF
enable
configure
rsyslog host $LOG_SERVER_IP mode $LOG_PROTOCOL port $LOG_SERVER_PORT
end
write memory
EOF
}

write_config "$HQ_CONFIG"
write_config "$BR_CONFIG"

printf 'Created:\n  %s\n  %s\n' "$HQ_CONFIG" "$BR_CONFIG"
