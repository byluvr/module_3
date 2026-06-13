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
WEB_UPSTREAM="${WEB_UPSTREAM:?WEB_UPSTREAM is required in $ENV_FILE}"
DOCKER_UPSTREAM="${DOCKER_UPSTREAM:?DOCKER_UPSTREAM is required in $ENV_FILE}"
SSH_USER="${SSH_USER:-sshuser}"
AUTH_USER="${AUTH_USER:-WEB}"
AUTH_PASSWORD="${AUTH_PASSWORD:-P@ssw0rd}"
AUTH_REALM="${AUTH_REALM:-Restricted Access}"

SSL_DIR=/etc/nginx/ssl
NGINX_AVAILABLE_DIR=/etc/nginx/sites-available.d
NGINX_ENABLED_DIR=/etc/nginx/sites-enabled.d
NGINX_CONFIG="$NGINX_AVAILABLE_DIR/default.conf"
NGINX_LINK="$NGINX_ENABLED_DIR/default.conf"
HTPASSWD_FILE=/etc/nginx/.htpasswd

log() {
    printf '[ISP HTTPS] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ "$SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
    die "SSH_USER contains unsupported characters"

log "Installing nginx and TLS tools"
apt-get update
apt-get install -y nginx openssl curl apache2-htpasswd

SOURCE_DIR="/home/$SSH_USER"
for certificate_file in web.crt web.key au-team-ca.crt; do
    [[ -s "$SOURCE_DIR/$certificate_file" ]] ||
        die "$SOURCE_DIR/$certificate_file not found; run 01-hq-srv-issue-certificates.sh"
done

log "Installing the certificate and private key"
install -d -m 0750 "$SSL_DIR"
install -m 0644 "$SOURCE_DIR/web.crt" "$SSL_DIR/web.crt"
install -m 0600 "$SOURCE_DIR/web.key" "$SSL_DIR/web.key"
install -m 0644 "$SOURCE_DIR/au-team-ca.crt" "$SSL_DIR/au-team-ca.crt"
rm -f -- \
    "$SOURCE_DIR/web.crt" \
    "$SOURCE_DIR/web.key" \
    "$SOURCE_DIR/au-team-ca.crt"

openssl verify -CAfile "$SSL_DIR/au-team-ca.crt" "$SSL_DIR/web.crt"
openssl x509 -in "$SSL_DIR/web.crt" -noout -text |
    grep -q 'Public Key Algorithm: rsaEncryption' ||
    die "the installed certificate does not use RSA"

log "Ensuring the Basic Auth account exists"
htpasswd -bc "$HTPASSWD_FILE" "$AUTH_USER" "$AUTH_PASSWORD"
if getent group nginx >/dev/null 2>&1; then
    chown root:nginx "$HTPASSWD_FILE"
    chmod 0640 "$HTPASSWD_FILE"
else
    chown root:root "$HTPASSWD_FILE"
    chmod 0644 "$HTPASSWD_FILE"
fi

log "Writing the HTTPS reverse proxy configuration"
install -d -m 0755 "$NGINX_AVAILABLE_DIR" "$NGINX_ENABLED_DIR"
temp_config="$(mktemp)"
trap 'rm -f -- "${temp_config:-}"' EXIT
cat > "$temp_config" <<EOF
# Managed by module_3/2/02-isp-nginx-https.sh
server {
    listen 80;
    server_name $WEB_DOMAIN $DOCKER_DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $WEB_DOMAIN;

    ssl_certificate $SSL_DIR/web.crt;
    ssl_certificate_key $SSL_DIR/web.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header Content-Security-Policy "upgrade-insecure-requests" always;

    auth_basic "$AUTH_REALM";
    auth_basic_user_file $HTPASSWD_FILE;

    location / {
        proxy_pass http://$WEB_UPSTREAM;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
    }
}

server {
    listen 443 ssl;
    server_name $DOCKER_DOMAIN;

    ssl_certificate $SSL_DIR/web.crt;
    ssl_certificate_key $SSL_DIR/web.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header Content-Security-Policy "upgrade-insecure-requests" always;

    location / {
        proxy_pass http://$DOCKER_UPSTREAM;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
    }
}
EOF

if [[ ! -f "$NGINX_CONFIG" ]] || ! cmp -s "$temp_config" "$NGINX_CONFIG"; then
    install -m 0644 "$temp_config" "$NGINX_CONFIG"
fi
rm -f -- "$temp_config"
trap - EXIT

if [[ -e "$NGINX_LINK" && ! -L "$NGINX_LINK" ]]; then
    rm -f -- "$NGINX_LINK"
fi
ln -sfn ../sites-available.d/default.conf "$NGINX_LINK"

log "Validating and restarting nginx"
nginx -t
systemctl enable --now nginx
systemctl restart nginx
systemctl is-active --quiet nginx || die "nginx is not running"

web_code="$(
    curl --silent --output /dev/null --write-out '%{http_code}' \
        --cacert "$SSL_DIR/au-team-ca.crt" \
        --resolve "$WEB_DOMAIN:443:127.0.0.1" \
        "https://$WEB_DOMAIN/"
)"
[[ "$web_code" == 401 ]] ||
    die "$WEB_DOMAIN returned $web_code without credentials; expected 401"

docker_code="$(
    curl --silent --output /dev/null --write-out '%{http_code}' \
        --cacert "$SSL_DIR/au-team-ca.crt" \
        --resolve "$DOCKER_DOMAIN:443:127.0.0.1" \
        "https://$DOCKER_DOMAIN/"
)"
[[ "$docker_code" != 000 && "$docker_code" != 401 ]] ||
    die "$DOCKER_DOMAIN returned $docker_code"

log "HTTPS configuration completed"
printf '%s: HTTP %s without credentials\n' "$WEB_DOMAIN" "$web_code"
printf '%s: HTTP %s\n' "$DOCKER_DOMAIN" "$docker_code"
