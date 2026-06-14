#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
HQ_CONFIG="$SCRIPT_DIR/HQ-RTR.conf"
BR_CONFIG="$SCRIPT_DIR/BR-RTR.conf"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "ERROR: $ENV_FILE not found." >&2
    exit 1
fi

HQ_WAN_IP="${HQ_WAN_IP:?HQ_WAN_IP is required in $ENV_FILE}"
BR_WAN_IP="${BR_WAN_IP:?BR_WAN_IP is required in $ENV_FILE}"
HQ_WAN_INTERFACE="${HQ_WAN_INTERFACE:?HQ_WAN_INTERFACE is required in $ENV_FILE}"
BR_WAN_INTERFACE="${BR_WAN_INTERFACE:?BR_WAN_INTERFACE is required in $ENV_FILE}"
HQ_TUNNEL_INTERFACE="${HQ_TUNNEL_INTERFACE:?HQ_TUNNEL_INTERFACE is required in $ENV_FILE}"
BR_TUNNEL_INTERFACE="${BR_TUNNEL_INTERFACE:?BR_TUNNEL_INTERFACE is required in $ENV_FILE}"
IPSEC_PROFILE="${IPSEC_PROFILE:-VPN}"
CRYPTO_MAP="${CRYPTO_MAP:-VPN-MAP}"
FILTER_MAP="${FILTER_MAP:-VPN-FILTER}"
IPSEC_PSK="${IPSEC_PSK:-P@ssw0rd}"

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

validate_name() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[a-zA-Z0-9_.-]+$ ]] ||
        die "$name contains unsupported characters"
}

for variable_name in HQ_WAN_IP BR_WAN_IP; do
    validate_ipv4 "$variable_name" "${!variable_name}"
done

for variable_name in \
    HQ_WAN_INTERFACE BR_WAN_INTERFACE \
    HQ_TUNNEL_INTERFACE BR_TUNNEL_INTERFACE \
    IPSEC_PROFILE CRYPTO_MAP FILTER_MAP; do
    validate_name "$variable_name" "${!variable_name}"
done

[[ "$IPSEC_PSK" != *[[:space:]]* && -n "$IPSEC_PSK" ]] ||
    die "IPSEC_PSK must not be empty or contain spaces"

write_config() {
    local output_file="$1"
    local local_wan="$2"
    local remote_wan="$3"
    local wan_interface="$4"
    local tunnel_interface="$5"

    cat > "$output_file" <<EOF
enable
configure
crypto-ipsec ike enable
crypto-ipsec profile $IPSEC_PROFILE ike-v2
 mode tunnel
 ike-phase1
  proposal aes256-sha256-modp2048
  auth pre-shared-key $IPSEC_PSK
 exit
 ike-phase2
  protocol esp
  proposal aes256-sha256
  local-ts $local_wan
  remote-ts $remote_wan
 exit
exit
crypto-map $CRYPTO_MAP 10
 match peer $remote_wan
 set crypto-ipsec profile $IPSEC_PROFILE
exit
filter-map ipv4 $FILTER_MAP 5
 match gre host $local_wan host $remote_wan
 set crypto-map $CRYPTO_MAP peer $remote_wan
exit
no filter-map ipv4 $FILTER_MAP 10
filter-map ipv4 $FILTER_MAP 10
 match udp host $remote_wan eq 4500 host $local_wan eq 4500
 set crypto-map $CRYPTO_MAP peer $remote_wan
exit
filter-map ipv4 $FILTER_MAP 15
 match any any any
 set accept
exit
interface $wan_interface
 set filter-map in $FILTER_MAP 5
 set filter-map in $FILTER_MAP 10
 set filter-map in $FILTER_MAP 15
exit
interface $tunnel_interface
 no set filter-map in $FILTER_MAP 5
 no set filter-map in $FILTER_MAP 10
 no set filter-map in $FILTER_MAP 15
exit
EOF

    cat >> "$output_file" <<'EOF'
end
write memory
EOF
}

write_config \
    "$HQ_CONFIG" \
    "$HQ_WAN_IP" "$BR_WAN_IP" \
    "$HQ_WAN_INTERFACE" "$HQ_TUNNEL_INTERFACE"

write_config \
    "$BR_CONFIG" \
    "$BR_WAN_IP" "$HQ_WAN_IP" \
    "$BR_WAN_INTERFACE" "$BR_TUNNEL_INTERFACE"

printf 'Created:\n  %s\n  %s\n' "$HQ_CONFIG" "$BR_CONFIG"
