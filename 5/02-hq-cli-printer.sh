#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: $ENV_FILE not found" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

CUPS_SERVER_HOST="${CUPS_SERVER_HOST:-hq-srv.au-team.irpo}"
CUPS_SERVER_IP="${CUPS_SERVER_IP:?CUPS_SERVER_IP is required in $ENV_FILE}"
CUPS_SERVER_PORT="${CUPS_SERVER_PORT:?CUPS_SERVER_PORT is required in $ENV_FILE}"
SERVER_QUEUE="${SERVER_QUEUE:-Cups-PDF}"
CLIENT_QUEUE="${CLIENT_QUEUE:-HQ-PDF}"
TEST_DOCUMENT="${TEST_DOCUMENT:-/tmp/hq-pdf-test.txt}"

log() {
    printf '[HQ-CLI printer] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"

log "Installing CUPS client tools"
apt-get update
if ! apt-get install -y cups-client; then
    log "cups-client is unavailable; installing the full cups package"
    apt-get install -y cups
fi

command -v lpadmin >/dev/null 2>&1 ||
    die "lpadmin was not installed"
command -v lp >/dev/null 2>&1 ||
    die "lp was not installed"

if ! getent hosts "$CUPS_SERVER_HOST" >/dev/null; then
    log "$CUPS_SERVER_HOST cannot be resolved; updating /etc/hosts"

    [[ "$CUPS_SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
        die "CUPS_SERVER_IP is not an IPv4 address"

    hosts_temp="$(mktemp)"
    trap 'rm -f "${hosts_temp:-}"' EXIT
    awk -v hostname="$CUPS_SERVER_HOST" '
        /^[[:space:]]*#/ || NF == 0 {
            print
            next
        }
        {
            output = $1
            for (i = 2; i <= NF; i++) {
                if ($i != hostname) {
                    output = output " " $i
                }
            }
            if (output != $1) {
                print output
            }
        }
    ' /etc/hosts > "$hosts_temp"
    printf '%s\t%s\n' "$CUPS_SERVER_IP" "$CUPS_SERVER_HOST" >> "$hosts_temp"
    install -m 0644 "$hosts_temp" /etc/hosts
    rm -f "$hosts_temp"
    trap - EXIT

    getent hosts "$CUPS_SERVER_HOST" >/dev/null ||
        die "$CUPS_SERVER_HOST still cannot be resolved after updating /etc/hosts"
fi

printer_uri="ipp://${CUPS_SERVER_HOST}:${CUPS_SERVER_PORT}/printers/${SERVER_QUEUE}"

log "Creating local queue $CLIENT_QUEUE"
if lpstat -p "$CLIENT_QUEUE" >/dev/null 2>&1; then
    lpadmin -x "$CLIENT_QUEUE"
fi

lpadmin \
    -p "$CLIENT_QUEUE" \
    -E \
    -v "$printer_uri" \
    -m everywhere
lpadmin -d "$CLIENT_QUEUE"

log "Sending a test document"
cat > "$TEST_DOCUMENT" <<EOF
AU-Team virtual PDF printer test
Client: $(hostname -f 2>/dev/null || hostname)
Date: $(date '+%Y-%m-%d %H:%M:%S %z')
Printer: $CLIENT_QUEUE
EOF

lp -d "$CLIENT_QUEUE" "$TEST_DOCUMENT"
rm -f -- "$TEST_DOCUMENT"

log "Current printer configuration"
lpstat -t
