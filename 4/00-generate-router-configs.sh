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
HQ_INTERNAL_NETWORKS="${HQ_INTERNAL_NETWORKS:?HQ_INTERNAL_NETWORKS is required in $ENV_FILE}"
BR_INTERNAL_NETWORKS="${BR_INTERNAL_NETWORKS:?BR_INTERNAL_NETWORKS is required in $ENV_FILE}"
HQ_WAN_INTERFACE="${HQ_WAN_INTERFACE:?HQ_WAN_INTERFACE is required in $ENV_FILE}"
BR_WAN_INTERFACE="${BR_WAN_INTERFACE:?BR_WAN_INTERFACE is required in $ENV_FILE}"
HQ_TUNNEL_INTERFACE="${HQ_TUNNEL_INTERFACE:?HQ_TUNNEL_INTERFACE is required in $ENV_FILE}"
BR_TUNNEL_INTERFACE="${BR_TUNNEL_INTERFACE:?BR_TUNNEL_INTERFACE is required in $ENV_FILE}"
FIREWALL_MAP="${FIREWALL_MAP:-INTERNET_IN}"
OLD_IPSEC_FILTER="${OLD_IPSEC_FILTER:-VPN-FILTER}"
CRYPTO_MAP="${CRYPTO_MAP:-VPN-MAP}"
ALLOWED_TCP_PORTS="${ALLOWED_TCP_PORTS:?ALLOWED_TCP_PORTS is required in $ENV_FILE}"
ALLOW_ICMP="${ALLOW_ICMP:-yes}"

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

validate_cidr() {
    local value="$1"
    local address="${value%/*}"
    local prefix="${value#*/}"

    [[ "$value" == */* ]] || die "$value is not an IPv4 network"
    validate_ipv4 "network address" "$address"
    [[ "$prefix" =~ ^[0-9]+$ ]] &&
        (( prefix >= 0 && prefix <= 32 )) ||
        die "$value has an invalid prefix"
}

validate_name() {
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[a-zA-Z0-9_.-]+$ ]] ||
        die "$name contains unsupported characters"
}

validate_ipv4 HQ_WAN_IP "$HQ_WAN_IP"
validate_ipv4 BR_WAN_IP "$BR_WAN_IP"

for value in $HQ_INTERNAL_NETWORKS $BR_INTERNAL_NETWORKS; do
    validate_cidr "$value"
done

for variable_name in \
    HQ_WAN_INTERFACE BR_WAN_INTERFACE \
    HQ_TUNNEL_INTERFACE BR_TUNNEL_INTERFACE FIREWALL_MAP \
    OLD_IPSEC_FILTER CRYPTO_MAP; do
    validate_name "$variable_name" "${!variable_name}"
done

for port in $ALLOWED_TCP_PORTS; do
    [[ "$port" =~ ^[0-9]+$ ]] &&
        (( port >= 1 && port <= 65535 )) ||
        die "invalid TCP port: $port"
done

[[ "$ALLOW_ICMP" == yes || "$ALLOW_ICMP" == no ]] ||
    die "ALLOW_ICMP must be yes or no"

write_match_lines() {
    local protocol="$1"
    local port_direction="$2"
    local port="$3"
    shift 3

    local network
    for network in "$@"; do
        if [[ "$port_direction" == source ]]; then
            printf ' match %s any eq %s %s\n' "$protocol" "$port" "$network"
        else
            printf ' match %s any %s eq %s\n' "$protocol" "$network" "$port"
        fi
    done
}

write_config() {
    local output_file="$1"
    local local_wan="$2"
    local remote_wan="$3"
    local wan_interface="$4"
    local tunnel_interface="$5"
    local internal_networks_string="$6"
    local -a internal_networks
    local port

    read -r -a internal_networks <<< "$internal_networks_string"

    cat > "$output_file" <<EOF
enable
configure
no filter-map ipv4 $FIREWALL_MAP 5
filter-map ipv4 $FIREWALL_MAP 5
 match gre host $local_wan host $remote_wan
 set crypto-map $CRYPTO_MAP peer $remote_wan
exit
no filter-map ipv4 $FIREWALL_MAP 10
filter-map ipv4 $FIREWALL_MAP 10
 match udp host $remote_wan eq 4500 host $local_wan eq 4500
 set crypto-map $CRYPTO_MAP peer $remote_wan
exit
no filter-map ipv4 $FIREWALL_MAP 15
filter-map ipv4 $FIREWALL_MAP 15
 match udp host $remote_wan eq 500 host $local_wan eq 500
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 20
filter-map ipv4 $FIREWALL_MAP 20
 match tcp any any ack
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 30
filter-map ipv4 $FIREWALL_MAP 30
EOF

    for port in $ALLOWED_TCP_PORTS; do
        printf ' match tcp any any eq %s\n' "$port" >> "$output_file"
    done

    cat >> "$output_file" <<EOF
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 40
filter-map ipv4 $FIREWALL_MAP 40
 match udp any any eq 53
EOF

    write_match_lines udp source 53 "${internal_networks[@]}" >> "$output_file"

    cat >> "$output_file" <<EOF
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 50
filter-map ipv4 $FIREWALL_MAP 50
 match udp any any eq 123
EOF

    write_match_lines udp source 123 "${internal_networks[@]}" >> "$output_file"

    cat >> "$output_file" <<EOF
 set accept
exit
EOF

    if [[ "$ALLOW_ICMP" == yes ]]; then
        cat >> "$output_file" <<EOF
no filter-map ipv4 $FIREWALL_MAP 60
filter-map ipv4 $FIREWALL_MAP 60
 match icmp any any
 set accept
exit
EOF
    fi

    cat >> "$output_file" <<EOF
interface $wan_interface
 set filter-map in $FIREWALL_MAP 20
 set filter-map in $FIREWALL_MAP 30
 set filter-map in $FIREWALL_MAP 40
 set filter-map in $FIREWALL_MAP 50
EOF

    if [[ "$ALLOW_ICMP" == yes ]]; then
        printf ' set filter-map in %s 60\n' "$FIREWALL_MAP" >> "$output_file"
    fi

    cat >> "$output_file" <<EOF
 set filter-map in $FIREWALL_MAP 5
 set filter-map in $FIREWALL_MAP 10
 set filter-map in $FIREWALL_MAP 15
 no set filter-map in $OLD_IPSEC_FILTER 5
 no set filter-map in $OLD_IPSEC_FILTER 10
 no set filter-map in $OLD_IPSEC_FILTER 15
exit
interface $tunnel_interface
 no set filter-map in $OLD_IPSEC_FILTER 5
 no set filter-map in $OLD_IPSEC_FILTER 10
 no set filter-map in $OLD_IPSEC_FILTER 15
exit
end
write memory
EOF
}

write_config \
    "$HQ_CONFIG" \
    "$HQ_WAN_IP" "$BR_WAN_IP" \
    "$HQ_WAN_INTERFACE" "$HQ_TUNNEL_INTERFACE" \
    "$HQ_INTERNAL_NETWORKS"

write_config \
    "$BR_CONFIG" \
    "$BR_WAN_IP" "$HQ_WAN_IP" \
    "$BR_WAN_INTERFACE" "$BR_TUNNEL_INTERFACE" \
    "$BR_INTERNAL_NETWORKS"

printf 'Created:\n  %s\n  %s\n' "$HQ_CONFIG" "$BR_CONFIG"
