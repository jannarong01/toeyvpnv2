#!/usr/bin/env bash
# ==============================================================================
# toeyvpnv2 - Base System Configuration
# Path: modules/00-base.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root
log_info "=== เริ่มต้นติดตั้งระบบพื้นฐาน (00-base.sh) ==="

# 1. ตั้งค่า Timezone เป็น Asia/Bangkok
log_info "กำลังตั้งค่าเขตเวลาเป็น Asia/Bangkok..."
timedatectl set-timezone Asia/Bangkok 2>/dev/null || ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

# 2. ปรับปรุงรายการแพ็กเกจระบบ
log_info "กำลังอัปเดต apt repository..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# 3. ติดตั้งแพ็กเกจจำเป็น
PACKAGES=(
    curl wget jq dos2unix openssl net-tools chrony socat cron rsyslog
    zip unzip tar iptables iptables-persistent netfilter-persistent fail2ban
    xz-utils lsof build-essential python3 python3-pip
)

log_info "กำลังติดตั้งแพ็กเกจที่จำเป็น..."
apt-get install -y --no-install-recommends "${PACKAGES[@]}"

# 4. ตั้งค่า BBR และ Network Optimization ผ่าน sysctl.d (Idempotent)
log_info "กำลังตั้งค่า Network Optimization และ TCP BBR..."
cat <<EOF > /etc/sysctl.d/99-toeyvpn.conf
# toeyvpnv2 Network Tuning
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mtu_probing = 1
fs.file-max = 65535
EOF

sysctl --system >/dev/null 2>&1

# 5. เปิดและเริ่มการทำงานของบริการพื้นฐาน
systemctl enable --now chrony cron rsyslog >/dev/null 2>&1 || true

# 6. เพิ่มเมนูลงใน /root/.bashrc (ตรวจสอบป้องกันบรรทัดซ้ำ)
if ! grep -q "toeyvpn-menu" /root/.bashrc 2>/dev/null; then
    echo "alias menu='toeyvpn-menu'" >> /root/.bashrc
    echo "# toeyvpn-menu trigger" >> /root/.bashrc
fi

log_info "=== ติดตั้งระบบพื้นฐานเสร็จสิ้น ==="
