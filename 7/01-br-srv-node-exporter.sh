#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
CONTAINER_NAME=node-exporter-br

[[ -f "$ENV_FILE" ]] || {
    echo "ERROR: $ENV_FILE not found" >&2
    exit 1
}

# shellcheck disable=SC1090
source "$ENV_FILE"

NODE_EXPORTER_PORT="${NODE_EXPORTER_PORT:?NODE_EXPORTER_PORT is required in $ENV_FILE}"
NODE_EXPORTER_IMAGE="${NODE_EXPORTER_IMAGE:-quay.io/prometheus/node-exporter:latest}"

log() {
    printf '[BR-SRV monitoring] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ "$NODE_EXPORTER_PORT" =~ ^[0-9]+$ ]] &&
    (( NODE_EXPORTER_PORT >= 1 && NODE_EXPORTER_PORT <= 65535 )) ||
    die "NODE_EXPORTER_PORT must be from 1 to 65535"

log "Installing Docker and curl"
apt-get update
apt-get install -y docker-engine curl

systemctl enable --now docker.service
systemctl is-active --quiet docker.service ||
    die "docker.service is not running"

log "Pulling $NODE_EXPORTER_IMAGE"
docker pull "$NODE_EXPORTER_IMAGE"

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    log "Replacing the existing $CONTAINER_NAME container"
    docker rm -f "$CONTAINER_NAME"
fi

log "Starting Node Exporter"
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --network host \
    --pid host \
    --volume /:/host:ro,rslave \
    "$NODE_EXPORTER_IMAGE" \
    --path.rootfs=/host \
    --web.listen-address=":${NODE_EXPORTER_PORT}" \
    '--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+|run)($|/)'

for attempt in {1..30}; do
    if curl --silent --fail \
        "http://127.0.0.1:${NODE_EXPORTER_PORT}/metrics" \
        >/dev/null; then
        log "Node Exporter is available on port $NODE_EXPORTER_PORT"
        docker ps --filter "name=^/${CONTAINER_NAME}$"
        exit 0
    fi
    sleep 1
done

docker logs "$CONTAINER_NAME" >&2 || true
die "Node Exporter did not become ready"
