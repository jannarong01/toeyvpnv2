#!/bin/bash
# ==============================================================================
#  MAIN INSTALLER & UPDATER (SETUP.SH) - TOEYVPN V2 ALL-IN-ONE SUITE
# ==============================================================================
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

if [ "${EUID}" -ne 0 ]; then
    echo -e "${RED}[ERROR] กรุณารันสคริปต์นี้ด้วยสิทธิ์ root เท่านั้น!${NC}"
    exit 1
fi
cd /root || exit 1

export DEBIAN_FRONTEND=noninteractive
REPO_URL="https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main"

MYIP=$(curl -sS --max-time 5 ipv4.icanhazip.com || curl -sS --max-time 5 ifconfig.me || curl -sS --max-time 5 api.ipify.org)
if [[ -z "$MYIP" ]]; then
    echo -e "${RED}[ERROR] ไม่สามารถดึงค่า IPv4 ของเซิร์ฟเวอร์ได้!${NC}"
    exit 1
fi

clear

# ตรวจสอบว่าเคยติดตั้งหรือยัง
if [[ -f /etc/xray/config.json ]]; then
    INSTALL_MODE="UPDATE"
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "        ${GREEN}DETECTED TOEYVPN V2 (UPDATE MODE)${NC}"
    echo -e "   ${YELLOW}ระบบตรวจพบว่าเครื่องนี้ติดตั้งอยู่แล้ว กำลังอัปเดตโค้ด...${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")
    sleep 2
else
    INSTALL_MODE="FRESH"
    echo -e "${YELLOW}==========================================================${NC}"
    echo -e "        ${CYAN}WELCOME TO TOEYVPN V2 FRESH INSTALLER${NC}"
    echo -e "  ${GREEN}SSH/WS • UDP CUSTOM • XRAY • ZIVPN • HYSTERIA 2 • API${NC}"
    echo -e "${YELLOW}==========================================================${NC}"
    echo -e ""

    mkdir -p /etc/xray /etc/zivpn /etc/hysteria /root/udp
    read -rp "กรอกชื่อโดเมนของคุณ (หากไม่มี ให้กด Enter เพื่อใช้ IP ${MYIP}): " user_domain
    user_domain=$(echo "$user_domain" | tr -d '[:space:]')

    if [[ -n "$user_domain" ]]; then
        DOMAIN="$user_domain"
    else
        DOMAIN="$MYIP"
    fi

    echo "$DOMAIN" > /etc/xray/domain
    echo "$DOMAIN" > /root/domain
    echo -e "${GREEN}ตั้งค่า Host/Domain เป็น: ${DOMAIN}${NC}\n"
    sleep 2

    echo -e "${CYAN}[1/4] กำลังเตรียมระบบพื้นฐานและซิงค์เวลามาตรฐาน (Asia/Bangkok)...${NC}"
    apt-get update -y
    apt-get install -y wget curl jq dos2unix openssl net-tools chrony socat cron rsyslog zip unzip ca-certificates psmisc
    ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
    systemctl enable chrony >/dev/null 2>&1
    systemctl restart chrony >/dev/null 2>&1
    chronyc makestep >/dev/null 2>&1

    echo -e "${CYAN}[2/4] กำลังเปิดใช้งานระบบเร่งความเร็วเครือข่าย (TCP BBR & UDP Buffer)...${NC}"
    mkdir -p /etc/sysctl.d
    cat <<EOF > /etc/sysctl.d/99-toeyvpnv2.conf
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.core.rmem_default=262144
net.core.wmem_default=262144
EOF
sysctl --system >/dev/null 2>&1
fi

echo -e "${CYAN}[INFO] กำลังอัปเดตและติดตั้ง Xray Core (Vmess/Vless) พร้อมระบบ Smart SSL...${NC}"
if wget -q -O /root/ins-xray.sh "${REPO_URL}/xray/ins-xray.sh" && [ -s /root/ins-xray.sh ]; then
    dos2unix /root/ins-xray.sh >/dev/null 2>&1
    chmod +x /root/ins-xray.sh
    /root/ins-xray.sh
    rm -f /root/ins-xray.sh
else
    echo -e "${RED}[ERROR] ไม่พบไฟล์ xray/ins-xray.sh บน GitHub!${NC}"
    exit 1
fi

echo -e "${CYAN}[INFO] กำลังอัปเดตระบบ SSH, UDP Custom, ZIVPN, Hysteria 2 และเมนูจัดการ...${NC}"
if wget -q -O /root/ssh-vpn.sh "${REPO_URL}/ssh/ssh-vpn.sh" && [ -s /root/ssh-vpn.sh ]; then
    dos2unix /root/ssh-vpn.sh >/dev/null 2>&1
    chmod +x /root/ssh-vpn.sh
    /root/ssh-vpn.sh
    rm -f /root/ssh-vpn.sh
else
    echo -e "${RED}[ERROR] ไม่พบไฟล์ ssh/ssh-vpn.sh บน GitHub!${NC}"
    exit 1
fi

rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
SERVICES=(rsyslog ssh sshd dropbear nginx xray zivpn hysteria udp-custom ws-epro udpgw@7100 udpgw@7300 fail2ban cron)
for svc in "${SERVICES[@]}"; do
    systemctl restart "$svc" >/dev/null 2>&1
done

clear
echo -e "${YELLOW}==========================================================${NC}"
echo -e "      ${GREEN}อัปเดตและติดตั้งระบบ TOEYVPN V2 สำเร็จ 100%!${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e " โหมดที่ใช้งาน      : ${GREEN}${INSTALL_MODE}${NC}"
echo -e " IP Address        : ${GREEN}${MYIP}${NC}"
echo -e " Domain            : ${GREEN}${DOMAIN}${NC}"
echo -e " Web Panel         : ${GREEN}http://${MYIP}:8081${NC}"
echo -e "${YELLOW}==========================================================${NC}"
rm -f /root/setup.sh
