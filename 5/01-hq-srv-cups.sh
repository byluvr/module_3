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

CUPS_SERVER_PORT="${CUPS_SERVER_PORT:-631}"
SERVER_QUEUE="${SERVER_QUEUE:-Cups-PDF}"

log() {
    printf '[HQ-SRV CUPS] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ "$CUPS_SERVER_PORT" =~ ^[0-9]+$ ]] &&
    (( CUPS_SERVER_PORT >= 1 && CUPS_SERVER_PORT <= 65535 )) ||
    die "CUPS_SERVER_PORT must be from 1 to 65535"
[[ "$CUPS_SERVER_PORT" == 631 ]] ||
    die "cupsctl --remote-any configures the standard IPP port 631"
[[ "$SERVER_QUEUE" =~ ^[A-Za-z0-9_.-]+$ ]] ||
    die "SERVER_QUEUE contains unsupported characters"

log "Installing CUPS and the PDF backend"
apt-get update
apt-get install -y cups cups-pdf

log "Starting CUPS"
systemctl enable --now cups

log "Allowing remote printing and printer sharing"
cupsctl --share-printers --remote-any

if ! lpstat -p "$SERVER_QUEUE" >/dev/null 2>&1; then
    log "The cups-pdf package did not create $SERVER_QUEUE; creating it"

    pdf_device="$(
        lpinfo -v 2>/dev/null |
            awk 'tolower($0) ~ /cups.*pdf/ {print $2; exit}'
    )"
    pdf_model="$(
        lpinfo -m 2>/dev/null |
            awk 'tolower($0) ~ /cups.*pdf/ {print $1; exit}'
    )"

    [[ -n "$pdf_device" ]] || pdf_device="cups-pdf:/"
    [[ -n "$pdf_model" ]] ||
        die "cups-pdf PPD was not found; inspect 'lpinfo -m | grep -i pdf'"

    lpadmin \
        -p "$SERVER_QUEUE" \
        -E \
        -v "$pdf_device" \
        -m "$pdf_model"
fi

log "Publishing $SERVER_QUEUE"
lpadmin -p "$SERVER_QUEUE" -E -o printer-is-shared=true
systemctl restart cups

queue_status="$(lpstat -p "$SERVER_QUEUE" 2>&1)" ||
    die "printer queue $SERVER_QUEUE is unavailable: $queue_status"
printf '%s\n' "$queue_status"

lpstat -a "$SERVER_QUEUE" |
    grep -F "$SERVER_QUEUE accepting requests" >/dev/null ||
    die "printer queue $SERVER_QUEUE is not accepting jobs"

lpstat -t

if command -v ss >/dev/null 2>&1; then
    ss -lnt | grep -E ":${CUPS_SERVER_PORT}[[:space:]]" >/dev/null ||
        die "CUPS is not listening on TCP port $CUPS_SERVER_PORT"
fi

log "Printer URI: ipp://$(hostname -f 2>/dev/null || hostname):${CUPS_SERVER_PORT}/printers/${SERVER_QUEUE}"
