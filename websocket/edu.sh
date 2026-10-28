#!/bin/bash
# ==============================================================================
#  SSH WEBSOCKET INSTALLER (PORT 10015) - TOEYVPN V2
# ==============================================================================
REPO="https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main"

apt-get install -y python3 dos2unix >/dev/null 2>&1

# 1. ดาวน์โหลดไฟล์ websocket.py ไปไว้ที่ /usr/local/bin/ws-epro
wget -q -O /usr/local/bin/ws-epro "${REPO}/websocket/websocket.py"
dos2unix /usr/local/bin/ws-epro >/dev/null 2>&1
chmod +x /usr/local/bin/ws-epro

# 2. สร้าง Systemd Service สำหรับรันพอร์ต 10015
cat <<EOF > /etc/systemd/system/ws-epro.service
[Unit]
Description=SSH Over WebSocket Python3 Proxy (ToeyVPN V2)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-epro 10015
Restart=always
RestartSec=1
LimitNOFILE=1048576
LimitNPROC=infinity

[Install]
WantedBy=multi-user.target
EOF

# 3. เปิดใช้งาน Service
systemctl daemon-reload
systemctl enable ws-epro >/dev/null 2>&1
systemctl restart ws-epro
echo "WebSocket Service (Port 10015) Installed Successfully!"
