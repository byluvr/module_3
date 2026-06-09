#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00-clean-common.sh"

prepare_cleanup BR-SRV

log "Preserving imported domain users and /etc/ansible/PC-INFO reports"
unmount_import_iso

finish_cleanup
