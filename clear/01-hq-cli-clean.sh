#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00-clean-common.sh"

prepare_cleanup HQ-CLI
remove_temp_file /tmp/au-team-ca.crt
remove_temp_file /tmp/hq-pdf-test.txt
finish_cleanup
