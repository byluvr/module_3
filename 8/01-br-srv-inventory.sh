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

ANSIBLE_DIR="${ANSIBLE_DIR:-/etc/ansible}"
INVENTORY_FILE="${INVENTORY_FILE:-/etc/ansible/hosts}"
PLAYBOOK_NAME="${PLAYBOOK_NAME:-inventory.yml}"
REPORT_DIR_NAME="${REPORT_DIR_NAME:-PC-INFO}"
INVENTORY_TARGETS="${INVENTORY_TARGETS:-HQ-SRV:HQ-CLI}"

PLAYBOOK_FILE="$ANSIBLE_DIR/$PLAYBOOK_NAME"
REPORT_DIR="$ANSIBLE_DIR/$REPORT_DIR_NAME"

log() {
    printf '[BR-SRV inventory] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root"
[[ "$ANSIBLE_DIR" == /* ]] ||
    die "ANSIBLE_DIR must be an absolute path"
[[ "$INVENTORY_FILE" == /* ]] ||
    die "INVENTORY_FILE must be an absolute path"
[[ "$PLAYBOOK_NAME" =~ ^[A-Za-z0-9_.-]+\.ya?ml$ ]] ||
    die "PLAYBOOK_NAME must have a .yml or .yaml extension"
[[ "$REPORT_DIR_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] ||
    die "REPORT_DIR_NAME contains unsupported characters"
[[ "$INVENTORY_TARGETS" =~ ^[A-Za-z0-9_.:-]+$ ]] ||
    die "INVENTORY_TARGETS contains unsupported characters"

if ! command -v ansible-playbook >/dev/null 2>&1; then
    log "Installing Ansible"
    apt-get update
    apt-get install -y ansible
fi

[[ -f "$INVENTORY_FILE" ]] ||
    die "$INVENTORY_FILE not found; complete module 2 task 5 first"

log "Checking HQ-SRV and HQ-CLI in the existing inventory"
for host in HQ-SRV HQ-CLI; do
    ansible-inventory \
        --inventory "$INVENTORY_FILE" \
        --host "$host" |
        grep -q '"ansible_host"' ||
        die "$host was not found in $INVENTORY_FILE"
done

log "Creating $REPORT_DIR"
install -d -m 0755 "$REPORT_DIR"

log "Writing $PLAYBOOK_FILE"
cat > "$PLAYBOOK_FILE" <<EOF
---
- name: Inventory HQ workstations
  hosts: "$INVENTORY_TARGETS"
  gather_facts: true

  tasks:
    - name: Check that the primary IPv4 address was discovered
      ansible.builtin.assert:
        that:
          - ansible_default_ipv4 is defined
          - ansible_default_ipv4.address is defined
        fail_msg: "The primary IPv4 address was not discovered for {{ inventory_hostname }}"

    - name: Remove the previous report for this computer
      ansible.builtin.file:
        path: "$REPORT_DIR/{{ ansible_hostname }}.yml"
        state: absent
      delegate_to: localhost
      become: false

    - name: Write the inventory report on BR-SRV
      ansible.builtin.copy:
        dest: "$REPORT_DIR/{{ ansible_hostname }}.yml"
        mode: "0644"
        content: |
          ---
          hostname: "{{ ansible_hostname }}"
          ip_address: "{{ ansible_default_ipv4.address }}"
      delegate_to: localhost
      become: false
EOF
chmod 0644 "$PLAYBOOK_FILE"

log "Checking Ansible connectivity"
ansible \
    --inventory "$INVENTORY_FILE" \
    "$INVENTORY_TARGETS" \
    --module-name ping

run_marker="$(mktemp)"
trap 'rm -f "${run_marker:-}"' EXIT

log "Validating and running the playbook"
ansible-playbook \
    --inventory "$INVENTORY_FILE" \
    "$PLAYBOOK_FILE" \
    --syntax-check
ansible-playbook \
    --inventory "$INVENTORY_FILE" \
    "$PLAYBOOK_FILE"

mapfile -t reports < <(
    find "$REPORT_DIR" \
        -maxdepth 1 \
        -type f \
        -name '*.yml' \
        -newer "$run_marker" \
        -printf '%f\n' |
        sort
)

((${#reports[@]} >= 2)) ||
    die "fewer than two YAML reports were created in $REPORT_DIR"

log "Created reports"
for report in "${reports[@]}"; do
    printf '%s\n' "$REPORT_DIR/$report"
    grep -Eq '^hostname: ".+"$' "$REPORT_DIR/$report" ||
        die "$report does not contain hostname"
    grep -Eq '^ip_address: "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"$' \
        "$REPORT_DIR/$report" ||
        die "$report does not contain an IPv4 address"
done

rm -f "$run_marker"
trap - EXIT

log "Inventory completed"
