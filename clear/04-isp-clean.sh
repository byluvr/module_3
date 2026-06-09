#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/00-clean-common.sh"

ISP_SSH_USER="${ISP_SSH_USER:-sshuser}"
[[ "$ISP_SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
    die "ISP_SSH_USER contains unsupported characters"

prepare_cleanup ISP

remove_backup_dir /root/module_3_task_2_backups
remove_isp_transfer_file "/home/$ISP_SSH_USER/web.crt"
remove_isp_transfer_file "/home/$ISP_SSH_USER/web.key"
remove_isp_transfer_file "/home/$ISP_SSH_USER/au-team-ca.crt"

finish_cleanup
