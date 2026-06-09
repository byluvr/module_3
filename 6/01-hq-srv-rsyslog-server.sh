#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
RSYSLOG_CONFIG=/etc/rsyslog.d/20-au-team-remote-server.conf
LOGROTATE_CONFIG=/etc/logrotate.d/au-team-remote
CRON_CONFIG=/etc/cron.d/au-team-remote-logrotate
MANAGED_CLIENT_CONFIG=/etc/rsyslog.d/30-au-team-forward-warning.conf

[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: $ENV_FILE not found" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

LOG_SERVER_IP="${LOG_SERVER_IP:-192.168.1.10}"
LOG_SERVER_PORT="${LOG_SERVER_PORT:-514}"
LOG_ROOT="${LOG_ROOT:-/opt}"
LOG_FILE_NAME="${LOG_FILE_NAME:-messages.log}"
ROTATE_SIZE="${ROTATE_SIZE:-10M}"
ROTATE_COUNT="${ROTATE_COUNT:-4}"
ROTATE_WEEKDAY="${ROTATE_WEEKDAY:-0}"
ROTATE_HOUR="${ROTATE_HOUR:-0}"
ROTATE_MINUTE="${ROTATE_MINUTE:-0}"

log() {
    printf '[HQ-SRV rsyslog] %s\n' "$*"
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
[[ "$LOG_ROOT" == /* && "$LOG_ROOT" != "/" ]] ||
    die "LOG_ROOT must be an absolute directory other than /"
[[ "$LOG_FILE_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] ||
    die "LOG_FILE_NAME contains unsupported characters"
[[ "$ROTATE_SIZE" =~ ^[0-9]+[kKmMgG]?$ ]] ||
    die "ROTATE_SIZE must look like 10M"
[[ "$ROTATE_COUNT" =~ ^[0-9]+$ ]] ||
    die "ROTATE_COUNT must be numeric"
[[ "$ROTATE_WEEKDAY" =~ ^[0-7]$ ]] ||
    die "ROTATE_WEEKDAY must be from 0 to 7"
[[ "$ROTATE_HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]] ||
    die "ROTATE_HOUR must be from 0 to 23"
[[ "$ROTATE_MINUTE" =~ ^([0-9]|[1-5][0-9])$ ]] ||
    die "ROTATE_MINUTE must be from 0 to 59"

log "Installing rsyslog and logrotate"
apt-get update
apt-get install -y rsyslog logrotate

if ! command -v crontab >/dev/null 2>&1; then
    log "crontab is missing; trying ALT Linux cron packages"
    apt-get install -y crontabs ||
        apt-get install -y vixie-cron ||
        die "cron is not installed and no supported cron package was found"
fi

log "Creating the remote log root"
install -d -m 0750 "$LOG_ROOT"

# If the server script is run after a client script was copied by mistake,
# remove only this project's managed forwarding file.
rm -f "$MANAGED_CLIENT_CONFIG"

log "Writing the remote-only rsyslog ruleset"
cat > "$RSYSLOG_CONFIG" <<EOF
module(load="imudp")
module(load="imtcp")

template(name="AuTeamRemotePath" type="list") {
    constant(value="${LOG_ROOT}/")
    property(name="hostname" securePath="replace")
    constant(value="/${LOG_FILE_NAME}")
}

ruleset(name="AuTeamRemote") {
    if (\$syslogseverity <= 4) then {
        action(
            type="omfile"
            dynaFile="AuTeamRemotePath"
            createDirs="on"
            dirCreateMode="0750"
            fileCreateMode="0640"
        )
    }
    stop
}

input(type="imudp" port="${LOG_SERVER_PORT}" ruleset="AuTeamRemote")
input(type="imtcp" port="${LOG_SERVER_PORT}" ruleset="AuTeamRemote")
EOF

log "Writing the weekly logrotate policy"
cat > "$LOGROTATE_CONFIG" <<EOF
${LOG_ROOT}/*/*.log {
    weekly
    minsize ${ROTATE_SIZE}
    rotate ${ROTATE_COUNT}
    compress
    missingok
    notifempty
    dateext
    create 0640 root root
    sharedscripts
    postrotate
        /usr/bin/systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}
EOF

cat > "$CRON_CONFIG" <<EOF
${ROTATE_MINUTE} ${ROTATE_HOUR} * * ${ROTATE_WEEKDAY} root /usr/sbin/logrotate ${LOGROTATE_CONFIG}
EOF
chmod 0644 "$CRON_CONFIG"

log "Validating configuration"
rsyslogd -N1
logrotate -d "$LOGROTATE_CONFIG" >/dev/null

log "Starting services"
systemctl enable --now rsyslog
if systemctl list-unit-files --type=service |
    grep -q '^crond\.service'; then
    systemctl enable --now crond
elif systemctl list-unit-files --type=service |
    grep -q '^cron\.service'; then
    systemctl enable --now cron
else
    die "cron service was not found"
fi
systemctl restart rsyslog

if command -v ss >/dev/null 2>&1; then
    ss -lntu |
        grep -E "[:.]${LOG_SERVER_PORT}[[:space:]]" >/dev/null ||
        die "rsyslog is not listening on port $LOG_SERVER_PORT"
fi

log "Checking that HQ-SRV is not a client of itself"
self_test_marker="AU_TEAM_LOCAL_ONLY_$(date +%s)_$$"
logger -p user.warning -t AU-TEAM-RSYSLOG "$self_test_marker"
sleep 2
if grep -R -F -q -- "$self_test_marker" "$LOG_ROOT" 2>/dev/null; then
    die "a local HQ-SRV message appeared in $LOG_ROOT; remove self-forwarding rules"
fi

log "The server stores only remote warning-or-higher messages in $LOG_ROOT/<hostname>/$LOG_FILE_NAME"
find "$LOG_ROOT" -mindepth 1 -maxdepth 2 -type f -print 2>/dev/null || true
