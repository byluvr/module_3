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

HQ_WAN_IP="${HQ_WAN_IP:-172.16.4.4}"
BR_WAN_IP="${BR_WAN_IP:-172.16.5.5}"
HQ_WAN_INTERFACE="${HQ_WAN_INTERFACE:-int0}"
BR_WAN_INTERFACE="${BR_WAN_INTERFACE:-int0}"
HQ_TUNNEL_INTERFACE="${HQ_TUNNEL_INTERFACE:-tunnel.0}"
BR_TUNNEL_INTERFACE="${BR_TUNNEL_INTERFACE:-tunnel.0}"
HQ_TUNNEL_IP="${HQ_TUNNEL_IP:-172.16.0.1}"
BR_TUNNEL_IP="${BR_TUNNEL_IP:-172.16.0.2}"
TUNNEL_PREFIX="${TUNNEL_PREFIX:-30}"
TUNNEL_MTU="${TUNNEL_MTU:-1400}"
IPSEC_PROFILE="${IPSEC_PROFILE:-VPN}"
CRYPTO_MAP="${CRYPTO_MAP:-VPN-MAP}"
FILTER_MAP="${FILTER_MAP:-VPN-FILTER}"
IPSEC_PSK="${IPSEC_PSK:-P@ssw0rd}"
CONFIGURE_OSPF="${CONFIGURE_OSPF:-yes}"
OSPF_PROCESS="${OSPF_PROCESS:-1}"
OSPF_NETWORK="${OSPF_NETWORK:-172.16.0.0}"
OSPF_AREA="${OSPF_AREA:-0.0.0.0}"

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

for variable_name in \
    HQ_WAN_IP BR_WAN_IP HQ_TUNNEL_IP BR_TUNNEL_IP \
    OSPF_NETWORK OSPF_WILDCARD; do
    validate_ipv4 "$variable_name" "${!variable_name}"
done

for variable_name in \
    HQ_WAN_INTERFACE BR_WAN_INTERFACE \
    HQ_TUNNEL_INTERFACE BR_TUNNEL_INTERFACE \
    IPSEC_PROFILE CRYPTO_MAP FILTER_MAP; do
    validate_name "$variable_name" "${!variable_name}"
done

[[ "$TUNNEL_PREFIX" =~ ^[0-9]+$ ]] &&
    (( TUNNEL_PREFIX >= 1 && TUNNEL_PREFIX <= 32 )) ||
    die "TUNNEL_PREFIX must be from 1 to 32"
[[ "$TUNNEL_MTU" =~ ^[0-9]+$ ]] &&
    (( TUNNEL_MTU >= 1280 && TUNNEL_MTU <= 1500 )) ||
    die "TUNNEL_MTU must be from 1280 to 1500"
[[ "$IPSEC_PSK" != *[[:space:]]* && -n "$IPSEC_PSK" ]] ||
    die "IPSEC_PSK must not be empty or contain spaces"
[[ "$CONFIGURE_OSPF" == yes || "$CONFIGURE_OSPF" == no ]] ||
    die "CONFIGURE_OSPF must be yes or no"
[[ "$OSPF_PROCESS" =~ ^[0-9]+$ ]] || die "OSPF_PROCESS must be numeric"
[[ "$OSPF_AREA" =~ ^[0-9]+$ ]] || die "OSPF_AREA must be numeric"

write_config() {
    local output_file="$1"
    local local_wan="$2"
    local remote_wan="$3"
    local wan_interface="$4"
    local tunnel_interface="$5"
    local tunnel_ip="$6"

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
filter-map ipv4 $FILTER_MAP 10
 match udp host $remote_wan eq 4500 host $local_wan eq 4500
 set crypto-map $CRYPTO_MAP peer $remote_wan
exit
filter-map ipv4 $FILTER_MAP 15
 match any any any
 set accept
exit
interface $wan_interface
 set filter-map in $FILTER_MAP 10
exit
interface $tunnel_interface
 ip address $tunnel_ip/$TUNNEL_PREFIX
 ip mtu $TUNNEL_MTU
 ip tunnel $local_wan $remote_wan mode gre
 set filter-map in $FILTER_MAP 10
exit
EOF

    if [[ "$CONFIGURE_OSPF" == yes ]]; then
        cat >> "$output_file" <<EOF
router ospf $OSPF_PROCESS
 network $OSPF_NETWORK/$TUNNEL_PREFIX area $OSPF_AREA
exit
EOF
    fi

    cat >> "$output_file" <<'EOF'
end
write memory
EOF
}

write_config \
    "$HQ_CONFIG" \
    "$HQ_WAN_IP" "$BR_WAN_IP" \
    "$HQ_WAN_INTERFACE" "$HQ_TUNNEL_INTERFACE" "$HQ_TUNNEL_IP"

write_config \
    "$BR_CONFIG" \
    "$BR_WAN_IP" "$HQ_WAN_IP" \
    "$BR_WAN_INTERFACE" "$BR_TUNNEL_INTERFACE" "$BR_TUNNEL_IP"

printf 'Created:\n  %s\n  %s\n' "$HQ_CONFIG" "$BR_CONFIG"
