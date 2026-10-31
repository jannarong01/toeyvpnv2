#!/usr/bin/env bash
# ==============================================================================
# toeyvpnv2 - WebSocket Service Installer
# Path: modules/40-ws.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root
log_info "=== เริ่มต้นติดตั้งบริการ WebSocket Proxy (40-ws.sh) ==="

WS_SRC="${SCRIPT_DIR}/../websocket/websocket.py"
WS_DEST="/usr/local/bin/ws-epro"

if [[ -f "$WS_SRC" ]]; then
    cp "$WS_SRC" "$WS_DEST"
else
    die "ไม่พบไฟล์ต้นฉบับ ${WS_SRC}"
fi

dos2unix "$WS_DEST" >/dev/null 2>&1 || true
chmod +x "$WS_DEST"

# สร้าง Systemd Service
cat <<EOF > /etc/systemd/system/ws-epro.service
[Unit]
Description=toeyvpnv2 SSH Over WebSocket Python3 Proxy
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 ${WS_DEST} 10015
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

service_restart_safe ws-epro
log_info "=== ติดตั้งบริการ WebSocket Proxy เสร็จสิ้น ==="
