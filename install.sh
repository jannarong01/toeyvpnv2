#!/usr/bin/env bash
# ==============================================================================
# toeyvpnv2 - Main Installer
# Path: install.sh
# ==============================================================================
set -euo pipefail

# นำเข้า Common Library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    # shellcheck source=lib/common.sh
    source "${SCRIPT_DIR}/lib/common.sh"
else
    echo "ไม่พบไฟล์ ${SCRIPT_DIR}/lib/common.sh" >&2
    exit 1
fi

# ตรวจสอบสิทธิ์ Root
require_root

# ตรวจสอบระบบปฏิบัติการและสถาปัตยกรรม
detect_os
ARCH="$(detect_arch)"
export ARCH

# ------------------------------------------------------------------------------
# ค่าพารามิเตอร์เริ่มต้น
# ------------------------------------------------------------------------------
ARG_DOMAIN=""
ARG_PANEL_PASS=""
ARG_ENABLE_UDP_CUSTOM="true"
ARG_PERMIT_ROOT="false"
ARG_NON_INTERACTIVE="false"

# อ่านค่า Flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            ARG_DOMAIN="$2"
            shift 2
            ;;
        --panel-pass)
            ARG_PANEL_PASS="$2"
            shift 2
            ;;
        --no-udp-custom)
            ARG_ENABLE_UDP_CUSTOM="false"
            shift
            ;;
        --permit-root)
            ARG_PERMIT_ROOT="true"
            shift
            ;;
        -y|--yes)
            ARG_NON_INTERACTIVE="true"
            shift
            ;;
        *)
            echo "พารามิเตอร์ไม่ถูกต้อง: $1" >&2
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# ตรวจสอบสถานะการติดตั้ง v1 เดิม
# ------------------------------------------------------------------------------
if [[ -f /etc/xray/config.json ]] && [[ ! -f /etc/toeyvpn/VERSION ]]; then
    echo -e "${YELLOW}====================================================================${NC}"
    echo -e "${YELLOW}ตรวจพบการติดตั้ง toeyvpn v1 อยู่ในเซิร์ฟเวอร์นี้!${NC}"
    echo -e "เพื่อป้องกันข้อมูลลูกค้าและบัญชีเดิมสูญหาย"
    echo -e "กรุณาใช้สคริปต์ ${CYAN}update.sh${NC} หรือเครื่องมือไมเกรตข้อมูล ${CYAN}migrate/v1-to-v2.sh${NC}"
    echo -e "${YELLOW}====================================================================${NC}"
    if [[ "$ARG_NON_INTERACTIVE" != "true" ]]; then
        read -rp "ต้องการยกเลิกการติดตั้งใหม่เพื่อไปใช้สคริปต์อัปเดตหรือไม่? [Y/n]: " cancel_install
        cancel_install="${cancel_install:-Y}"
        if [[ "$cancel_install" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
fi

# ------------------------------------------------------------------------------
# รับค่าคอนฟิกจากผู้ใช้งาน
# ------------------------------------------------------------------------------
clear
echo -e "${CYAN}====================================================================${NC}"
echo -e "${CYAN}             ยินดีต้อนรับสู่โปรแกรมติดตั้ง toeyvpnv2                ${NC}"
echo -e "${CYAN}====================================================================${NC}"

MYIP="$(get_public_ip)"
log_info "IP สาธารณะของเซิร์ฟเวอร์: ${MYIP}"

# 1. โดเมน
DOMAIN="$ARG_DOMAIN"
if [[ -z "$DOMAIN" ]] && [[ "$ARG_NON_INTERACTIVE" != "true" ]]; then
    echo ""
    read -rp "กรอกชื่อโดเมนของคุณ (หากไม่มี ให้กด Enter เพื่อใช้ IP ${MYIP}): " input_domain
    DOMAIN="${input_domain:-$MYIP}"
elif [[ -z "$DOMAIN" ]]; then
    DOMAIN="$MYIP"
fi

# 2. รหัสผ่านแอดมิน Web Panel
PANEL_PASS="$ARG_PANEL_PASS"
if [[ -z "$PANEL_PASS" ]] && [[ "$ARG_NON_INTERACTIVE" != "true" ]]; then
    echo ""
    read -rp "กำหนดรหัสผ่าน Web Panel (กด Enter เพื่อสุ่มรหัสผ่านปลอดภัย 16 ตัวอักษร): " input_pass
    if [[ -z "$input_pass" ]]; then
        PANEL_PASS="$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)"
    else
        PANEL_PASS="$input_pass"
    fi
elif [[ -z "$PANEL_PASS" ]]; then
    PANEL_PASS="$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)"
fi

# 3. เปิดใช้งาน UDP Custom หรือไม่
ENABLE_UDP_CUSTOM="$ARG_ENABLE_UDP_CUSTOM"
if [[ "$ARG_NON_INTERACTIVE" != "true" && -z "$ARG_DOMAIN" ]]; then
    echo ""
    read -rp "ต้องการเปิดใช้งาน UDP Custom (พอร์ต 1-65535 DNAT ไปยัง 7200) หรือไม่? [Y/n]: " input_udp
    input_udp="${input_udp:-Y}"
    if [[ ! "$input_udp" =~ ^[Yy]$ ]]; then
        ENABLE_UDP_CUSTOM="false"
    fi
fi

# 4. อนุญาตให้ Root ล็อกอินผ่านรหัสผ่าน SSH หรือไม่
PERMIT_ROOT="$ARG_PERMIT_ROOT"
if [[ "$ARG_NON_INTERACTIVE" != "true" && -z "$ARG_DOMAIN" ]]; then
    echo ""
    echo -e "${YELLOW}คำแนะนำด้านความปลอดภัย: ไม่ควรอนุญาตให้ Root ล็อกอินด้วย Password ทาง SSH${NC}"
    read -rp "ต้องการอนุญาตให้ Root ล็อกอินผ่านรหัสผ่าน SSH หรือไม่? [y/N]: " input_root
    input_root="${input_root:-N}"
    if [[ "$input_root" =~ ^[Yy]$ ]]; then
        PERMIT_ROOT="true"
    fi
fi

# ------------------------------------------------------------------------------
# บันทึกคอนฟิกลงระบบ
# ------------------------------------------------------------------------------
mkdir -p /etc/toeyvpn
mkdir -p /var/log/toeyvpn
mkdir -p /root/toeyvpn-backup

conf_set "DOMAIN" "$DOMAIN"
conf_set "MYIP" "$MYIP"
conf_set "ARCH" "$ARCH"
conf_set "ENABLE_UDP_CUSTOM" "$ENABLE_UDP_CUSTOM"
conf_set "PERMIT_ROOT" "$PERMIT_ROOT"
conf_set "INSTALLED_VERSION" "2.0.0"

# บันทึกรหัสผ่านพาเนลลงในไฟล์เฉพาะที่มีการจำกัดสิทธิ์ (chmod 640)
cat <<EOF > /etc/toeyvpn/panel.conf
PANEL_USER="admin"
PANEL_PASS_PLAIN="${PANEL_PASS}"
PANEL_SECRET="$(openssl rand -hex 32)"
EOF
chmod 640 /etc/toeyvpn/panel.conf

# คัดลอก VERSION
cp "${SCRIPT_DIR}/VERSION" /etc/toeyvpn/VERSION 2>/dev/null || echo "2.0.0" > /etc/toeyvpn/VERSION

log_info "บันทึกคอนฟิกพื้นฐานเรียบร้อยแล้ว"

# ------------------------------------------------------------------------------
# ลำดับการเรียกโมดูลการติดตั้ง (Modules Execution Order)
# ------------------------------------------------------------------------------
MODULES=(
    "00-base.sh"
    "10-cert.sh"
    "20-xray.sh"
    "30-ssh.sh"
    "40-ws.sh"
    "50-udp.sh"
    "60-panel.sh"
    "70-cron.sh"
)

log_info "เตรียมเริ่มกระบวนการติดตั้งโมดูลย่อยตามลำดับ..."

for mod in "${MODULES[@]}"; do
    mod_path="${SCRIPT_DIR}/modules/${mod}"
    if [[ -f "$mod_path" ]]; then
        log_info "กำลังทำงาน: ${mod}..."
        bash "$mod_path"
    else
        log_warn "โมดูล ${mod} ยังไม่มีอยู่ในไดเรกทอรี (จะถูกติดตั้งในเฟสถัดไป)"
    fi
done

# ------------------------------------------------------------------------------
# สรุปผลการตั้งค่าเริ่มต้น
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}      โครงสร้างหลัก toeyvpnv2 (เฟส 1) ติดตั้งเสร็จสมบูรณ์!          ${NC}"
echo -e "${GREEN}====================================================================${NC}"
echo -e "**Server IP:**          ${MYIP}"
echo -e "**Domain:**             ${DOMAIN}"
echo -e "**Architecture:**       ${ARCH}"
echo -e "**UDP Custom Forward:** ${ENABLE_UDP_CUSTOM}"
echo -e "**Admin Password:**     ${YELLOW}${PANEL_PASS}${NC} (กรุณาบันทึกไว้ จะไม่แสดงซ้ำอีก)"
echo -e "**Install Log:**        ${INSTALL_LOG}"
echo -e "${GREEN}====================================================================${NC}"
