#!/bin/bash
# ==============================================================================
#  DOMAIN & SSL UPDATER - TOEYVPN V2
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p /etc/xray
MYIP=$(curl -sS --max-time 5 ipv4.icanhazip.com || curl -sS --max-time 5 ifconfig.me)

echo -e "${YELLOW}-----------------------------------------${NC}"
echo -e "  ตั้งค่าโดเมนสำหรับเซิร์ฟเวอร์ (กด Enter เพื่อใช้ IP แทนได้)"
echo -e "${YELLOW}-----------------------------------------${NC}"
read -rp "กรุณากรอกโดเมนของคุณ (เช่น vpn.example.com): " USER_DOMAIN
USER_DOMAIN=$(echo "$USER_DOMAIN" | tr -d '[:space:]')

if [[ -z "$USER_DOMAIN" ]]; then
    DOMAIN="$MYIP"
    echo -e "${GREEN}ไม่ได้ระบุโดเมน ระบบจะใช้ IP: ${DOMAIN} แทน${NC}"
else
    DOMAIN="$USER_DOMAIN"
    echo -e "${GREEN}บันทึกโดเมน: ${DOMAIN} เรียบร้อยแล้ว${NC}"
fi

echo "$DOMAIN" > /etc/xray/domain
echo "$DOMAIN" > /root/domain

if [[ "$DOMAIN" != "$MYIP" && -f /root/.acme.sh/acme.sh ]]; then
    echo -e "${CYAN}กำลังขอใบรับรอง SSL ใหม่สำหรับโดเมน ${DOMAIN}...${NC}"
    systemctl stop nginx >/dev/null 2>&1
    fuser -k 80/tcp >/dev/null 2>&1
    /root/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone -k ec-256 --force
    /root/.acme.sh/acme.sh --installcert -d "${DOMAIN}" \
        --fullchainpath /etc/xray/xray.crt \
        --keypath /etc/xray/xray.key --ecc
    systemctl restart nginx xray zivpn hysteria >/dev/null 2>&1
    echo -e "${GREEN}อัปเดต SSL Certificate และรีสตาร์ทบริการเรียบร้อยแล้ว!${NC}"
fi
sleep 1
