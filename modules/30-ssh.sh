#!/usr/bin/env bash
# ==============================================================================
# toeyvpnv2 - SSH & Dropbear Hardening Module
# Path: modules/30-ssh.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_root
log_info "=== เริ่มต้นตั้งค่า OpenSSH และ Dropbear (30-ssh.sh) ==="

PERMIT_ROOT="$(conf_get "PERMIT_ROOT" "false")"
ROOT_AUTH="prohibit-password"
if [[ "$PERMIT_ROOT" == "true" ]]; then
    ROOT_AUTH="yes"
fi

# 1. ติดตั้ง Dropbear
apt-get install -y dropbear

# 2. ปรับแต่ง OpenSSH
# ค้นหา Ciphers/Algorithms ที่ SSH daemon รุ่นนี้รองรับจริง
SUPPORTED_KEYS="$(sshd -Q key 2>/dev/null | grep -E 'ssh-rsa|ssh-dss' | paste -sd, - || true)"
SUPPORTED_KEX="$(sshd -Q kex 2>/dev/null | grep -E 'diffie-hellman-group1-sha1|diffie-hellman-group14-sha1' | paste -sd, - || true)"

SSH_COMPAT_CONF=""
[[ -n "$SUPPORTED_KEYS" ]] && SSH_COMPAT_CONF+="PubkeyAcceptedKeyTypes +${SUPPORTED_KEYS}\nHostKeyAlgorithms +${SUPPORTED_KEYS}\n"
[[ -n "$SUPPORTED_KEX" ]] && SSH_COMPAT_CONF+="KexAlgorithms +${SUPPORTED_KEX}\n"

mkdir -p /etc/ssh/sshd_config.d
SSH_TEST_FILE="/etc/ssh/sshd_config.d/99-toeyvpn.conf"

cat <<EOF > "$SSH_TEST_FILE"
PasswordAuthentication yes
PermitRootLogin ${ROOT_AUTH}
$(echo -e "$SSH_COMPAT_CONF")
EOF

# ตรวจสอบความถูกต้องของคอนฟิกก่อนรีสตาร์ต
if sshd -t; then
    log_info "ตรวจสอบคอนฟิก OpenSSH ผ่านเรียบร้อย"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
else
    log_error "คอนฟิก OpenSSH มีข้อผิดพลาด กำลังย้อนกลับเพื่อความปลอดภัย..."
    rm -f "$SSH_TEST_FILE"
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
fi

# 3. ปรับแต่ง Dropbear พอร์ต 109 และ 143
log_info "กำลังกำหนดค่า Dropbear (พอร์ต 109, 143)..."
cat <<'EOF' > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl daemon-reload
systemctl enable dropbear
systemctl restart dropbear || true

# 4. ตั้งค่า Fail2ban
log_info "กำลังกำหนดค่า Fail2ban ป้องกันการ Brute-force..."
cat <<'EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
mode = normal

[dropbear]
enabled = true
port = 109,143
logpath = /var/log/auth.log
backend = auto
EOF

systemctl restart fail2ban || true

log_info "=== ตั้งค่า OpenSSH และ Dropbear เสร็จสิ้น ==="
