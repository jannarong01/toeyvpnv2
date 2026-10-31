#!/usr/bin/env bash
# ==============================================================================
# toeyvpnv2 - Xray & Nginx Reverse Proxy Module
# Path: modules/20-xray.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root
log_info "=== เริ่มต้นติดตั้ง Xray และ Nginx (20-xray.sh) ==="

# 1. ติดตั้ง Nginx
apt-get install -y nginx

# 2. ติดตั้ง Xray-core ทางการ
log_info "กำลังติดตั้ง Xray-core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

mkdir -p /var/log/xray
mkdir -p /etc/xray

# 3. สร้างคอนฟิก /etc/xray/config.json
log_info "กำลังสร้างไฟล์คอนฟิก Xray (VMess: 10001, VLESS: 10002)..."
cat <<'EOF' > /etc/xray/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "api",
      "port": 10085,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    },
    {
      "tag": "vmess-ws",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "tag": "vless-ws",
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

# 4. สร้างการตั้งค่า Nginx (/etc/nginx/conf.d/xray.conf)
log_info "กำลังกำหนดค่า Nginx Reverse Proxy (พอร์ต 80, 443)..."
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default

cat <<'EOF' > /etc/nginx/conf.d/xray.conf
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _;

    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # สำหรับ acme.sh ต่ออายุใบรับรอง
    location /.well-known/acme-challenge/ {
        root /var/www/acme;
        try_files $uri =404;
    }

    # VMess WebSocket
    location /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # VLESS WebSocket
    location /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # SSH WebSocket Proxy (ต่อสายเข้า ws-epro พอร์ต 10015)
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10015;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

# 5. ตั้งค่า Logrotate สำหรับ Xray
cat <<'EOF' > /etc/logrotate.d/xray
/var/log/xray/*.log {
    daily
    missingok
    rotate 3
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload xray >/dev/null 2>&1 || true
    endscript
}
EOF

# 6. ตรวจสอบ Syntax และเริ่มทำงาน
nginx -t
service_restart_safe xray
service_restart_safe nginx

log_info "=== ติดตั้ง Xray และ Nginx เสร็จสิ้น ==="
