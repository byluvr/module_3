#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
PKI_DIR=/root/au-team-ca

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: $ENV_FILE not found." >&2
    exit 1
fi

WEB_DOMAIN="${WEB_DOMAIN:-web.au-team.irpo}"
DOCKER_DOMAIN="${DOCKER_DOMAIN:-docker.au-team.irpo}"
CERT_DAYS="${CERT_DAYS:-30}"
CA_DAYS="${CA_DAYS:-30}"
RSA_KEY_BITS="${RSA_KEY_BITS:-4096}"
CERT_COUNTRY="${CERT_COUNTRY:-RU}"
CERT_STATE="${CERT_STATE:-HMAO}"
CERT_CITY="${CERT_CITY:-RADUZHNY}"
CERT_ORGANIZATION="${CERT_ORGANIZATION:-AU-Team}"
CERT_ORG_UNIT="${CERT_ORG_UNIT:-IT}"
CA_COMMON_NAME="${CA_COMMON_NAME:-AU-Team CA}"
SSH_USER="${SSH_USER:-sshuser}"
SSH_PASSWORD="${SSH_PASSWORD:-P@ssw0rd}"
ISP_IP="${ISP_IP:?ISP_IP is required in $ENV_FILE}"
ISP_SSH_PORT="${ISP_SSH_PORT:?ISP_SSH_PORT is required in $ENV_FILE}"
HQ_CLI_IP="${HQ_CLI_IP:?HQ_CLI_IP is required in $ENV_FILE}"
HQ_CLI_SSH_PORT="${HQ_CLI_SSH_PORT:?HQ_CLI_SSH_PORT is required in $ENV_FILE}"

log() {
    printf '[HQ-SRV CA] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

validate_domain() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] ||
        die "$name is not a valid domain name"
}

validate_subject_value() {
    local name="$1"
    local value="$2"

    [[ -n "$value" ]] || die "$name is empty"
    case "$value" in
        *'/'* | *$'\n'* | *$'\r'*)
            die "$name contains an unsupported character"
            ;;
    esac
}

copy_with_password() {
    local source_file="$1"
    local port="$2"
    local host="$3"
    local destination="$4"

    sshpass -p "$SSH_PASSWORD" scp \
        -P "$port" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$source_file" "$SSH_USER@$host:$destination"
}

[[ $EUID -eq 0 ]] || die "run this script as root"
validate_domain WEB_DOMAIN "$WEB_DOMAIN"
validate_domain DOCKER_DOMAIN "$DOCKER_DOMAIN"
[[ "$WEB_DOMAIN" != "$DOCKER_DOMAIN" ]] ||
    die "WEB_DOMAIN and DOCKER_DOMAIN must be different"
[[ "$CERT_DAYS" =~ ^[1-9][0-9]*$ ]] || die "CERT_DAYS must be positive"
[[ "$CA_DAYS" =~ ^[1-9][0-9]*$ ]] || die "CA_DAYS must be positive"
[[ "$RSA_KEY_BITS" =~ ^(2048|3072|4096)$ ]] ||
    die "RSA_KEY_BITS must be 2048, 3072 or 4096"
for port_name in ISP_SSH_PORT HQ_CLI_SSH_PORT; do
    port_value="${!port_name}"
    [[ "$port_value" =~ ^[0-9]+$ ]] &&
        (( port_value >= 1 && port_value <= 65535 )) ||
        die "$port_name must be from 1 to 65535"
done
for subject_name in \
    CERT_COUNTRY CERT_STATE CERT_CITY CERT_ORGANIZATION \
    CERT_ORG_UNIT CA_COMMON_NAME; do
    validate_subject_value "$subject_name" "${!subject_name}"
done

log "Installing OpenSSL and SSH tools"
apt-get update
apt-get install -y openssl openssh-clients sshpass

install -d -m 0700 "$PKI_DIR"

cat > "$PKI_DIR/ca.cnf" <<EOF
[req]
prompt = no
distinguished_name = ca_dn
x509_extensions = v3_ca

[ca_dn]
C = $CERT_COUNTRY
ST = $CERT_STATE
L = $CERT_CITY
O = $CERT_ORGANIZATION
OU = $CERT_ORG_UNIT
CN = $CA_COMMON_NAME

[v3_ca]
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

cat > "$PKI_DIR/server.cnf" <<EOF
[req]
prompt = no
distinguished_name = server_dn
req_extensions = server_req

[server_dn]
C = $CERT_COUNTRY
ST = $CERT_STATE
L = $CERT_CITY
O = $CERT_ORGANIZATION
OU = $CERT_ORG_UNIT
CN = $WEB_DOMAIN

[server_req]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:$WEB_DOMAIN,DNS:$DOCKER_DOMAIN
subjectKeyIdentifier = hash
EOF

log "Generating the RSA-$RSA_KEY_BITS CA"
openssl genrsa -out "$PKI_DIR/ca.key" "$RSA_KEY_BITS"
openssl req \
    -new -x509 \
    -sha256 \
    -days "$CA_DAYS" \
    -key "$PKI_DIR/ca.key" \
    -out "$PKI_DIR/ca.crt" \
    -config "$PKI_DIR/ca.cnf"

log "Issuing the web certificate for $CERT_DAYS days"
openssl genrsa -out "$PKI_DIR/web.key" "$RSA_KEY_BITS"
openssl req \
    -new \
    -sha256 \
    -key "$PKI_DIR/web.key" \
    -out "$PKI_DIR/web.csr" \
    -config "$PKI_DIR/server.cnf"
openssl x509 \
    -req \
    -sha256 \
    -days "$CERT_DAYS" \
    -in "$PKI_DIR/web.csr" \
    -CA "$PKI_DIR/ca.crt" \
    -CAkey "$PKI_DIR/ca.key" \
    -CAcreateserial \
    -out "$PKI_DIR/web.crt" \
    -extfile "$PKI_DIR/server.cnf" \
    -extensions server_req

chmod 0600 "$PKI_DIR/ca.key" "$PKI_DIR/web.key"
chmod 0644 "$PKI_DIR/ca.crt" "$PKI_DIR/web.crt"

openssl verify -CAfile "$PKI_DIR/ca.crt" "$PKI_DIR/web.crt"
openssl x509 -in "$PKI_DIR/web.crt" -noout -text |
    grep -q 'Public Key Algorithm: rsaEncryption' ||
    die "the server certificate does not use RSA"
openssl x509 -in "$PKI_DIR/web.crt" -noout -text |
    grep -qi 'Signature Algorithm: sha256WithRSAEncryption' ||
    die "the server certificate does not use SHA-256 with RSA"
san_output="$(openssl x509 -in "$PKI_DIR/web.crt" -noout -ext subjectAltName)"
grep -Fq "DNS:$WEB_DOMAIN" <<< "$san_output" ||
    die "$WEB_DOMAIN is absent from the certificate"
grep -Fq "DNS:$DOCKER_DOMAIN" <<< "$san_output" ||
    die "$DOCKER_DOMAIN is absent from the certificate"

log "Copying the server certificate and key to ISP"
copy_with_password "$PKI_DIR/web.crt" "$ISP_SSH_PORT" "$ISP_IP" "/home/$SSH_USER/web.crt"
copy_with_password "$PKI_DIR/web.key" "$ISP_SSH_PORT" "$ISP_IP" "/home/$SSH_USER/web.key"
copy_with_password "$PKI_DIR/ca.crt" "$ISP_SSH_PORT" "$ISP_IP" "/home/$SSH_USER/au-team-ca.crt"

log "Copying the CA certificate to HQ-CLI"
copy_with_password "$PKI_DIR/ca.crt" "$HQ_CLI_SSH_PORT" "$HQ_CLI_IP" /tmp/au-team-ca.crt

log "Certificate issuance completed"
openssl x509 -in "$PKI_DIR/web.crt" \
    -noout -subject -issuer -dates -text |
    grep -E 'subject=|issuer=|notBefore=|notAfter=|Signature Algorithm|DNS:'
