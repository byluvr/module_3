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

WEB_DOMAIN="${WEB_DOMAIN:-web.au-team.irpo}"
DOCKER_DOMAIN="${DOCKER_DOMAIN:-docker.au-team.irpo}"
AUTH_USER="${AUTH_USER:-WEB}"
AUTH_PASSWORD="${AUTH_PASSWORD:-P@ssw0rd}"
CA_COMMON_NAME="${CA_COMMON_NAME:-AU-Team CA}"
SOURCE_CA=/tmp/au-team-ca.crt
TRUST_CA=/etc/pki/ca-trust/source/anchors/au-team-ca.crt
GOST_REPOSITORY_FILE=/etc/apt/sources.list.d/gostcrypto.list

log() {
    printf '[HQ-CLI trust] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

enable_gost() {
    if control openssl-gost enabled >/dev/null 2>&1; then
        return 0
    fi
    control openssl-gost all >/dev/null 2>&1 ||
        die "could not enable OpenSSL GOST support"
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ -s "$SOURCE_CA" ]] ||
    die "$SOURCE_CA not found; run 01-hq-srv-issue-certificates.sh"

log "Installing GOST support and CA tools"
apt-get update
apt-get install -y openssl openssl-gost-engine ca-certificates curl
enable_gost

log "Enabling the official ALT p10 gostcrypto repository"
install -d -m 0755 /etc/apt/sources.list.d
cat > "$GOST_REPOSITORY_FILE" <<'EOF'
rpm [p10] http://ftp.altlinux.org p10/branch/x86_64 gostcrypto
EOF
chmod 0644 "$GOST_REPOSITORY_FILE"
apt-get update

chromium_gost_version="$(
    apt-cache show chromium-gost 2>/dev/null |
        awk '
            $1 == "Package:" {
                is_gost = ($2 == "chromium-gost")
            }
            is_gost && $1 == "Version:" {
                print $2
                exit
            }
        '
)"
[[ -n "$chromium_gost_version" ]] ||
    die "the real chromium-gost package was not found in the gostcrypto repository"

if rpm -q chromium >/dev/null 2>&1; then
    log "Replacing the standard Chromium package with Chromium GOST"
    apt-get remove -y chromium
fi

log "Installing Chromium GOST $chromium_gost_version"
apt-get install -y "chromium-gost=$chromium_gost_version"
rpm -q chromium-gost >/dev/null 2>&1 ||
    die "chromium-gost was not installed; check apt-conf-branch-gostcrypto and repository access"
if rpm -q chromium >/dev/null 2>&1; then
    die "the standard chromium package was installed instead of chromium-gost"
fi

log "Installing the AU-Team CA certificate"
install -d -m 0755 /etc/pki/ca-trust/source/anchors
install -m 0644 "$SOURCE_CA" "$TRUST_CA"
update-ca-trust

openssl verify -CAfile "$TRUST_CA" "$TRUST_CA"
if ! trust list | grep -Fqi "$CA_COMMON_NAME"; then
    log "WARNING: $CA_COMMON_NAME was not shown by trust list; HTTPS checks will verify trust."
fi

log "Checking HTTPS without bypassing certificate validation"
web_code="$(
    curl --silent --output /dev/null --write-out '%{http_code}' \
        "https://$WEB_DOMAIN/"
)"
[[ "$web_code" == 401 ]] ||
    die "$WEB_DOMAIN returned $web_code without credentials; expected 401"

web_authenticated_code="$(
    curl --silent --output /dev/null --write-out '%{http_code}' \
        --user "$AUTH_USER:$AUTH_PASSWORD" \
        "https://$WEB_DOMAIN/"
)"
[[ "$web_authenticated_code" != 000 &&
    "$web_authenticated_code" != 401 &&
    "$web_authenticated_code" != 403 ]] ||
    die "$WEB_DOMAIN returned $web_authenticated_code with valid credentials"

docker_code="$(
    curl --silent --output /dev/null --write-out '%{http_code}' \
        "https://$DOCKER_DOMAIN/"
)"
[[ "$docker_code" != 000 && "$docker_code" != 401 ]] ||
    die "$DOCKER_DOMAIN returned $docker_code"

log "CA trust configuration completed"
printf '%s: HTTP %s authenticated\n' "$WEB_DOMAIN" "$web_authenticated_code"
printf '%s: HTTP %s\n' "$DOCKER_DOMAIN" "$docker_code"
printf 'Chromium GOST package: %s\n' "$(rpm -q chromium-gost)"
printf 'Close all Chromium windows and start Chromium again.\n'
