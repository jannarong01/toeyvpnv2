#!/usr/bin/env bash
# ==============================================================================
# toeyvpnv2 - UDP Services & Firewall Routing Module
# Path: modules/50-udp.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../versions.conf
source "${SCRIPT_DIR}/../versions.conf"

require_root
log_info "=== เริ่มต้นติดตั้งบริการ UDP (50-udp.sh) ==="

ARCH="$(conf_get "ARCH")"
ENABLE_UDP_CUSTOM="$(conf_get "ENABLE_UDP_CUSTOM" "true")"

mkdir -p /etc/zivpn
mkdir -p /etc/hysteria
mkdir -p /root/udp

# 1. ติดตั้ง ZIVPN UDP
log_info "กำลังดาวน์โหลดไบนารี ZIVPN UDP (${ARCH})..."
ZIVPN_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_${ZIVPN_VER}/udp-zivpn-linux-${ARCH}"
ZIVPN_HASH=""
[[ "$ARCH" == "amd64" ]] && ZIVPN_HASH="${SHA256_ZIVPN_AMD64}"
[[ "$ARCH" == "arm64" ]] && ZIVPN_HASH="${SHA256_ZIVPN_ARM64}"

download "$ZIVPN_URL" "/usr/local/bin/zivpn-udp" "$ZIVPN_HASH"
chmod +x /usr/local/bin/zivpn-udp

# สร้างใบรับรองของ ZIVPN
if [[ ! -f /etc/zivpn/zivpn.crt ]]; then
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=toeyvpn/CN=zivpn" \
        -keyout /etc/zivpn/zivpn.key -out /etc/zivpn/zivpn.crt >/dev/null 2>&1
fi

cat <<'EOF' > /etc/zivpn/config.json
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": []
  }
}
EOF

cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=toeyvpnv2 ZIVPN UDP Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn-udp -c /etc/zivpn/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 2. ติดตั้ง Hysteria 2
log_info "กำลังดาวน์โหลดไบนารี Hysteria 2 (${ARCH})..."
HYS_URL="https://github.com/apernet/hysteria/releases/download/app%2Fv${HYSTERIA_VER}/hysteria-linux-${ARCH}"
HYS_HASH=""
[[ "$ARCH" == "amd64" ]] && HYS_HASH="${SHA256_HYSTERIA_AMD64}"
[[ "$ARCH" == "arm64" ]] && HYS_HASH="${SHA256_HYSTERIA_ARM64}"

download "$HYS_URL" "/usr/local/bin/hysteria" "$HYS_HASH"
chmod +x /usr/local/bin/hysteria

# สคริปต์ยืนยันตัวตนชั่วคราวสำหรับ Hysteria (จะถูกแทนที่อย่างสมบูรณ์ในเฟส 3)
cat <<'EOF' > /usr/bin/hys-auth
#!/bin/bash
exit 1
EOF
chmod +x /usr/bin/hys-auth

cat <<'EOF' > /etc/hysteria/config.yaml
listen: :8443
tls:
  cert: /etc/xray/xray.crt
  key: /etc/xray/xray.key
auth:
  type: command
  command: /usr/bin/hys-auth
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
EOF

cat <<EOF > /etc/systemd/system/hysteria-server.service
[Unit]
Description=toeyvpnv2 Hysteria 2 Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 3. ติดตั้ง UDP Custom (กรณีเลือกเปิดใช้งาน)
if [[ "$ENABLE_UDP_CUSTOM" == "true" ]]; then
    log_info "กำลังตั้งค่า UDP Custom..."
    UDPCUSTOM_URL="$UDPCUSTOM_URL_AMD64"
    [[ "$ARCH" == "arm64" ]] && UDPCUSTOM_URL="$UDPCUSTOM_URL_ARM64"
    
    download "$UDPCUSTOM_URL" "/usr/local/bin/udp-custom" ""
    chmod +x /usr/local/bin/udp-custom

    cat <<'EOF' > /root/udp/config.json
{
  "listen": ":7200",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF

    cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=toeyvpnv2 UDP Custom Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/udp
ExecStart=/usr/local/bin/udp-custom server -c /root/udp/config.json
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    service_restart_safe udp-custom || true
fi

# 4. ติดตั้ง BadVPN UDPGW (พอร์ต 7100 และ 7300)
log_info "กำลังติดตั้ง BadVPN UDPGW..."
if [[ ! -f /usr/local/bin/badvpn-udpgw ]]; then
    # คอมไพล์ BadVPN แบบเร็วหากระบบมี build tools หรือดาวน์โหลด binary สำเร็จรูป
    if curl -fsSL -o /usr/local/bin/badvpn-udpgw "https://raw.githubusercontent.com/jannarong01/toeyvpn/main/badvpn-udpgw" 2>/dev/null; then
        chmod +x /usr/local/bin/badvpn-udpgw
    fi
fi

if [[ -f /usr/local/bin/badvpn-udpgw ]]; then
    for port in 7100 7300; do
        cat <<EOF > "/etc/systemd/system/udpgw@${port}.service"
[Unit]
Description=BadVPN UDPGW on port ${port}
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:${port} --max-clients 500
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable --now "udpgw@${port}" 2>/dev/null || true
    done
fi

# 5. ตั้งค่ากฎ Firewall Iptables แบบแยก Chain (ไม่กระทบ Docker หรือบริการอื่น)
log_info "กำลังกำหนดกฎ Iptables Firewall..."
NET_IFACE="$(ip -4 route show default 2>/dev/null | awk '{print $5}' | head -n 1)"

# สร้าง Chain TOEYVPN_PRE ใน nat table
iptables -t nat -N TOEYVPN_PRE 2>/dev/null || iptables -t nat -F TOEYVPN_PRE

# ลบกฎเก่าที่เคย Jump มายัง Chain นี้ แล้วผูกใหม่
iptables -t nat -D PREROUTING -i "$NET_IFACE" -j TOEYVPN_PRE 2>/dev/null || true
iptables -t nat -A PREROUTING -i "$NET_IFACE" -j TOEYVPN_PRE

# กฎภายใน Chain TOEYVPN_PRE
iptables -t nat -A TOEYVPN_PRE -p udp --dport 5667 -j ACCEPT
iptables -t nat -A TOEYVPN_PRE -p udp --dport 8443 -j ACCEPT
iptables -t nat -A TOEYVPN_PRE -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A TOEYVPN_PRE -p udp --dport 20000:50000 -j DNAT --to-destination :8443

if [[ "$ENABLE_UDP_CUSTOM" == "true" ]]; then
    # ยกเว้นพอร์ตสำคัญไม่ให้ถูก Forward ไปยัง 7200
    EXCLUDED_PORTS=(53 80 443 8081 5667 8443 7100 7200 7300)
    for p in "${EXCLUDED_PORTS[@]}"; do
        iptables -t nat -A TOEYVPN_PRE -p udp --dport "$p" -j ACCEPT
    done
    iptables -t nat -A TOEYVPN_PRE -p udp --dport 1:65535 -j DNAT --to-destination :7200
fi

# MASQUERADE
if ! iptables -t nat -C POSTROUTING -o "$NET_IFACE" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o "$NET_IFACE" -j MASQUERADE
fi

# บล็อก P2P / BitTorrent Keywords
log_info "กำลังกำหนดกฎบล็อก BitTorrent / P2P..."
P2P_RULES=(
    "get_peers" "announce_peer" "find_node" "BitTorrent"
    "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey="
    "torrent" "info_hash"
)
for kw in "${P2P_RULES[@]}"; do
    iptables -D FORWARD -m string --algo bm --string "$kw" -j DROP 2>/dev/null || true
    iptables -A FORWARD -m string --algo bm --string "$kw" -j DROP
done

# บันทึกกฎลงระบบอย่างถาวร
netfilter-persistent save >/dev/null 2>&1 || true

# เริ่มการทำงานของเซอร์วิส
service_restart_safe zivpn || true
service_restart_safe hysteria-server || true

log_info "=== ติดตั้งบริการ UDP เสร็จสิ้น ==="
