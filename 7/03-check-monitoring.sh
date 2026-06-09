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

MON_DOMAIN="${MON_DOMAIN:-mon.au-team.irpo}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-P@ssw0rd}"

log() {
    printf '[Monitoring check] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 ||
    die "curl is not installed"

log "Checking DNS"
getent hosts "$MON_DOMAIN" || die "$MON_DOMAIN cannot be resolved"

log "Checking Grafana"
curl --silent --fail \
    --user "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
    "http://${MON_DOMAIN}:${GRAFANA_PORT}/api/user"
printf '\n'

log "Checking Prometheus targets"
targets_json="$(
    curl --silent --fail \
        "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/targets"
)"

if command -v python3 >/dev/null 2>&1; then
    TARGETS_JSON="$targets_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["TARGETS_JSON"])
targets = payload["data"]["activeTargets"]
for target in targets:
    labels = target.get("labels", {})
    print(
        f"{labels.get('device', labels.get('instance', 'unknown'))}: "
        f"{target.get('health')} ({target.get('scrapeUrl')})"
    )

if len(targets) != 2 or any(target.get("health") != "up" for target in targets):
    raise SystemExit(1)
PY
else
    printf '%s\n' "$targets_json"
    grep -q '"health":"up"' <<< "$targets_json" ||
        die "Prometheus targets are not healthy"
fi

log "Grafana URL: http://${MON_DOMAIN}:${GRAFANA_PORT}/"
