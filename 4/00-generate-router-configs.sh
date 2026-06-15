#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
HQ_CONFIG="$SCRIPT_DIR/HQ-RTR.conf"
BR_CONFIG="$SCRIPT_DIR/BR-RTR.conf"

if [[ ! -f "$ENV_FILE" ]]; then
    printf 'ERROR: %s not found\n' "$ENV_FILE" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

HQ_INTERNAL_NETWORKS="${HQ_INTERNAL_NETWORKS:?HQ_INTERNAL_NETWORKS is required in $ENV_FILE}"
BR_INTERNAL_NETWORKS="${BR_INTERNAL_NETWORKS:?BR_INTERNAL_NETWORKS is required in $ENV_FILE}"
HQ_WAN_INTERFACE="${HQ_WAN_INTERFACE:?HQ_WAN_INTERFACE is required in $ENV_FILE}"
BR_WAN_INTERFACE="${BR_WAN_INTERFACE:?BR_WAN_INTERFACE is required in $ENV_FILE}"
FIREWALL_MAP="${FIREWALL_MAP:?FIREWALL_MAP is required in $ENV_FILE}"
VPN_FILTER_MAP="${VPN_FILTER_MAP:?VPN_FILTER_MAP is required in $ENV_FILE}"
ALLOWED_INBOUND_TCP_PORTS="${ALLOWED_INBOUND_TCP_PORTS:?ALLOWED_INBOUND_TCP_PORTS is required in $ENV_FILE}"
TCP_REPLY_SOURCE_PORTS="${TCP_REPLY_SOURCE_PORTS:?TCP_REPLY_SOURCE_PORTS is required in $ENV_FILE}"
ALLOW_ICMP="${ALLOW_ICMP:?ALLOW_ICMP is required in $ENV_FILE}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

validate_name() {
    local label="$1"
    local value="$2"

    [[ "$value" =~ ^[a-zA-Z0-9_.-]+$ ]] ||
        die "$label contains unsupported characters"
}

validate_cidr() {
    local value="$1"
    local address="${value%/*}"
    local prefix="${value#*/}"

    [[ "$value" == */* ]] ||
        die "$value is not an IPv4 network"
    [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] ||
        die "$value is not an IPv4 network"
    [[ "$prefix" =~ ^[0-9]+$ ]] &&
        (( prefix >= 0 && prefix <= 32 )) ||
        die "$value has an invalid prefix"
}

validate_ports() {
    local label="$1"
    shift

    local port
    for port in "$@"; do
        [[ "$port" =~ ^[0-9]+$ ]] &&
            (( port >= 1 && port <= 65535 )) ||
            die "$label contains an invalid port: $port"
    done
}

for variable_name in \
    HQ_WAN_INTERFACE BR_WAN_INTERFACE FIREWALL_MAP VPN_FILTER_MAP; do
    validate_name "$variable_name" "${!variable_name}"
done

for network in $HQ_INTERNAL_NETWORKS $BR_INTERNAL_NETWORKS; do
    validate_cidr "$network"
done

read -r -a inbound_tcp_ports <<< "$ALLOWED_INBOUND_TCP_PORTS"
read -r -a reply_tcp_ports <<< "$TCP_REPLY_SOURCE_PORTS"
validate_ports ALLOWED_INBOUND_TCP_PORTS "${inbound_tcp_ports[@]}"
validate_ports TCP_REPLY_SOURCE_PORTS "${reply_tcp_ports[@]}"

[[ "$ALLOW_ICMP" == yes || "$ALLOW_ICMP" == no ]] ||
    die "ALLOW_ICMP must be yes or no"

write_config() {
    local output_file="$1"
    local wan_interface="$2"
    local internal_networks_string="$3"
    local -a internal_networks
    local port
    local network

    read -r -a internal_networks <<< "$internal_networks_string"

    cat > "$output_file" <<EOF
enable
configure
no filter-map ipv4 $FIREWALL_MAP 5
no filter-map ipv4 $FIREWALL_MAP 15
no filter-map ipv4 $FIREWALL_MAP 10
filter-map ipv4 $FIREWALL_MAP 10
 match tcp any any ack
EOF

    for port in "${reply_tcp_ports[@]}"; do
        for network in "${internal_networks[@]}"; do
            printf ' match tcp any eq %s %s\n' "$port" "$network" >> "$output_file"
        done
    done

    cat >> "$output_file" <<EOF
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 20
filter-map ipv4 $FIREWALL_MAP 20
EOF

    for port in "${inbound_tcp_ports[@]}"; do
        printf ' match tcp any any eq %s\n' "$port" >> "$output_file"
    done

    cat >> "$output_file" <<EOF
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 30
filter-map ipv4 $FIREWALL_MAP 30
EOF

    for network in "${internal_networks[@]}"; do
        printf ' match udp any eq 53 %s\n' "$network" >> "$output_file"
    done

    cat >> "$output_file" <<EOF
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 40
filter-map ipv4 $FIREWALL_MAP 40
EOF

    for network in "${internal_networks[@]}"; do
        printf ' match udp any eq 123 %s\n' "$network" >> "$output_file"
    done

    cat >> "$output_file" <<EOF
 set accept
exit
no filter-map ipv4 $FIREWALL_MAP 50
filter-map ipv4 $FIREWALL_MAP 50
 match udp any any eq 500
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
    else
        printf 'no filter-map ipv4 %s 60\n' "$FIREWALL_MAP" >> "$output_file"
    fi

    cat >> "$output_file" <<EOF
interface $wan_interface
 set filter-map in $VPN_FILTER_MAP 5
 set filter-map in $VPN_FILTER_MAP 10
 no set filter-map in $VPN_FILTER_MAP 15
 set filter-map in $FIREWALL_MAP 10
 set filter-map in $FIREWALL_MAP 20
 set filter-map in $FIREWALL_MAP 30
 set filter-map in $FIREWALL_MAP 40
 set filter-map in $FIREWALL_MAP 50
EOF

    if [[ "$ALLOW_ICMP" == yes ]]; then
        printf ' set filter-map in %s 60\n' "$FIREWALL_MAP" >> "$output_file"
    else
        printf ' no set filter-map in %s 60\n' "$FIREWALL_MAP" >> "$output_file"
    fi

    cat >> "$output_file" <<EOF
exit
end
write memory
EOF
}

write_config "$HQ_CONFIG" "$HQ_WAN_INTERFACE" "$HQ_INTERNAL_NETWORKS"
write_config "$BR_CONFIG" "$BR_WAN_INTERFACE" "$BR_INTERNAL_NETWORKS"

printf 'Created:\n  %s\n  %s\n' "$HQ_CONFIG" "$BR_CONFIG"
