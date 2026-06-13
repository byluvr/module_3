#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
COMPOSE_FILE="$SCRIPT_DIR/compose.yaml"
PROMETHEUS_TEMPLATE="$SCRIPT_DIR/prometheus.yml.template"
GENERATED_DIR="$SCRIPT_DIR/generated"
PROMETHEUS_CONFIG="$GENERATED_DIR/prometheus.yml"

[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: $ENV_FILE not found" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

MON_DOMAIN="${MON_DOMAIN:-mon.au-team.irpo}"
HQ_SRV_IP="${HQ_SRV_IP:?HQ_SRV_IP is required in $ENV_FILE}"
BR_SRV_IP="${BR_SRV_IP:?BR_SRV_IP is required in $ENV_FILE}"
GRAFANA_PORT="${GRAFANA_PORT:?GRAFANA_PORT is required in $ENV_FILE}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:?PROMETHEUS_PORT is required in $ENV_FILE}"
NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:?NODE_EXPORTER_PORT is required in $ENV_FILE}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-P@ssw0rd}"

log() {
    printf '[HQ-SRV monitoring] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

validate_ipv4() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
        die "$name is not an IPv4 address"
}

validate_port() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[0-9]+$ ]] &&
        (( value >= 1 && value <= 65535 )) ||
        die "$name must be from 1 to 65535"
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ -f "$COMPOSE_FILE" ]] || die "$COMPOSE_FILE not found"
[[ -f "$PROMETHEUS_TEMPLATE" ]] || die "$PROMETHEUS_TEMPLATE not found"
[[ "$MON_DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
    die "MON_DOMAIN is invalid"
validate_ipv4 HQ_SRV_IP "$HQ_SRV_IP"
validate_ipv4 BR_SRV_IP "$BR_SRV_IP"
validate_port GRAFANA_PORT "$GRAFANA_PORT"
validate_port PROMETHEUS_PORT "$PROMETHEUS_PORT"
validate_port NODE_EXPORTER_PORT "$NODE_EXPORTER_PORT"
[[ -n "$GRAFANA_ADMIN_USER" && -n "$GRAFANA_ADMIN_PASSWORD" ]] ||
    die "Grafana credentials must not be empty"

log "Installing Docker and Compose"
apt-get update
apt-get install -y \
    docker-engine \
    docker-compose-v2 \
    curl

systemctl enable --now docker.service
systemctl is-active --quiet docker.service ||
    die "docker.service is not running"

log "Generating Prometheus configuration"
install -d -m 0755 "$GENERATED_DIR"
sed \
    -e "s/__HQ_SRV_IP__/${HQ_SRV_IP}/g" \
    -e "s/__BR_SRV_IP__/${BR_SRV_IP}/g" \
    -e "s/__NODE_EXPORTER_PORT__/${NODE_EXPORTER_PORT}/g" \
    "$PROMETHEUS_TEMPLATE" > "$PROMETHEUS_CONFIG"

log "Validating Docker Compose"
docker compose \
    --env-file "$ENV_FILE" \
    --file "$COMPOSE_FILE" \
    config >/dev/null

log "Pulling monitoring images"
docker compose \
    --env-file "$ENV_FILE" \
    --file "$COMPOSE_FILE" \
    pull

log "Starting Prometheus, Grafana and HQ Node Exporter"
docker compose \
    --env-file "$ENV_FILE" \
    --file "$COMPOSE_FILE" \
    up -d

for attempt in {1..60}; do
    if curl --silent --fail \
        "http://127.0.0.1:${GRAFANA_PORT}/api/health" \
        >/dev/null; then
        break
    fi
    if (( attempt == 60 )); then
        docker compose \
            --env-file "$ENV_FILE" \
            --file "$COMPOSE_FILE" \
            logs >&2
        die "Grafana did not become ready"
    fi
    sleep 2
done

# Environment credentials apply only when Grafana initializes a new volume.
# Resetting the password also makes reruns idempotent for an existing volume.
if ! docker exec grafana \
    grafana cli admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD" \
    >/dev/null 2>&1; then
    docker exec grafana \
        grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD" \
        >/dev/null
fi

curl --silent --fail \
    "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready" \
    >/dev/null ||
    die "Prometheus is not ready"
curl --silent --fail \
    "http://127.0.0.1:${NODE_EXPORTER_PORT}/metrics" \
    >/dev/null ||
    die "HQ Node Exporter is not ready"

log "Container status"
docker compose \
    --env-file "$ENV_FILE" \
    --file "$COMPOSE_FILE" \
    ps

log "Monitoring is available at http://${MON_DOMAIN}:${GRAFANA_PORT}/"
printf 'Login: %s\n' "$GRAFANA_ADMIN_USER"
