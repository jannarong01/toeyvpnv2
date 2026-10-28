# ตรวจสอบสถานะว่าเคยติดตั้งระบบไว้หรือยัง
if [[ -f /etc/xray/config.json && -d /home/vps/public_html ]]; then
    INSTALL_MODE="UPDATE"
    echo -e "${CYAN}==========================================================${NC}"
    echo -e "        ${GREEN}DETECTED TOEYVPN V2 (UPDATE MODE)${NC}"
    echo -e "   ${YELLOW}ระบบตรวจพบว่าเครื่องนี้ติดตั้งอยู่แล้ว กำลังอัปเดตโค้ด...${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    
    # ดึงโดเมนเดิมมาใช้อัตโนมัติทันที
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")
    sleep 2
else
    INSTALL_MODE="FRESH"
    echo -e "${YELLOW}==========================================================${NC}"
    echo -e "        ${CYAN}WELCOME TO TOEYVPN V2 FRESH INSTALLER${NC}"
    echo -e "  ${GREEN}SSH/WS • UDP CUSTOM • XRAY • ZIVPN • HYSTERIA 2 • API${NC}"
    echo -e "${YELLOW}==========================================================${NC}"
    
    read -rp "กรอกชื่อโดเมนของคุณ (หากไม่มี ให้กด Enter เพื่อใช้ IP ${MYIP}): " user_domain
    user_domain=$(echo "$user_domain" | tr -d '[:space:]')
    
    if [[ -n "$user_domain" ]]; then
        DOMAIN="$user_domain"
    else
        DOMAIN="$MYIP"
    fi
    
    mkdir -p /etc/xray /etc/zivpn /etc/hysteria /root/udp
    echo "$DOMAIN" > /etc/xray/domain
    echo "$DOMAIN" > /root/domain
    echo -e "${GREEN}ตั้งค่า Host/Domain เป็น: ${DOMAIN}${NC}\n"
    sleep 2
fi
