#!/usr/bin/env bash
# ==============================================================================
# toeyvpnv2 - Common Library
# Path: lib/common.sh
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# สีและฟังก์ชันแสดงผล
# ------------------------------------------------------------------------------
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m'

LOG_DIR="/var/log/toeyvpn"
INSTALL_LOG="${LOG_DIR}/install.log"
CONF_FILE="/etc/toeyvpn/toeyvpn.conf"

mkdir -p "$LOG_DIR"
mkdir -p "/etc/toeyvpn"

# ------------------------------------------------------------------------------
# ระบบบันทึก Log และแจ้งเตือน
# ------------------------------------------------------------------------------
_log() {
    local level="$1"
    local color="$2"
    shift 2
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${color}[${timestamp}] [${level}] ${msg}${NC}"
    echo "[${timestamp}] [${level}] ${msg}" >> "$INSTALL_LOG"
}

log_info() {
    _log "INFO" "$GREEN" "$*"
}

log_warn() {
    _log "WARN" "$YELLOW" "$*"
}

log_error() {
    _log "ERROR" "$RED" "$*"
}

die() {
    log_error "FATAL: $*"
    echo -e "${RED}การทำงานล้มเหลว กรุณาตรวจสอบบันทึกที่: ${INSTALL_LOG}${NC}" >&2
    exit 1
}

# ------------------------------------------------------------------------------
# ตรวจจับข้อผิดพลาด (Trap ERR)
# ------------------------------------------------------------------------------
trap_error() {
    local exit_code="$1"
    local line_no="$2"
    local bash_command="$3"
    log_error "คำสั่ง '${bash_command}' ล้มเหลวที่บรรทัด ${line_no} (Exit code: ${exit_code})"
}
trap 'trap_error $? $LINENO "$BASH_COMMAND"' ERR

# ------------------------------------------------------------------------------
# ตรวจสอบสิทธิ์และสภาพแวดล้อมระบบ
# ------------------------------------------------------------------------------
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo -e "${RED}ข้อผิดพลาด: สคริปต์นี้ต้องทำงานด้วยสิทธิ์ root เท่านั้น!${NC}" >&2
        exit 1
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        die "ไม่พบไฟล์ /etc/os-release ไม่สามารถระบุระบบปฏิบัติการได้"
    fi

    # ดึงค่า OS และ Version
    # shellcheck source=/dev/null
    source /etc/os-release

    local id="${ID:-}"
    local version="${VERSION_ID:-}"

    case "$id" in
        ubuntu)
            case "$version" in
                20.04|22.04|24.04)
                    log_info "ระบบปฏิบัติการที่รองรับ: Ubuntu ${version}"
                    ;;
                *)
                    die "Ubuntu เวอร์ชัน ${version} ไม่รองรับ (รองรับเฉพาะ 20.04, 22.04, 24.04 LTS)"
                    ;;
            esac
            ;;
        debian)
            case "$version" in
                11|12)
                    log_info "ระบบปฏิบัติการที่รองรับ: Debian ${version}"
                    ;;
                10)
                    die "Debian 10 สิ้นสุดระยะซัพพอร์ตแล้ว กรุณาอัปเกรดเป็น Debian 11 หรือ 12"
                    ;;
                *)
                    die "Debian เวอร์ชัน ${version} ไม่รองรับ (รองรับเฉพาะ 11 และ 12)"
                    ;;
            esac
            ;;
        *)
            die "ระบบปฏิบัติการ ${id} ไม่ได้รับการรองรับ (รองรับ Ubuntu และ Debian เท่านั้น)"
            ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            die "สถาปัตยกรรม CPU '${arch}' ไม่ได้รับการรองรับ (รองรับเฉพาะ amd64 และ arm64)"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# เครือข่ายและการดาวน์โหลดไฟล์
# ------------------------------------------------------------------------------
get_public_ip() {
    local ip=""
    local providers=(
        "https://ipv4.icanhazip.com"
        "https://ifconfig.me/ip"
        "https://ipinfo.io/ip"
        "https://api.ipify.org"
    )

    for url in "${providers[@]}"; do
        ip="$(curl -4 -fsSL --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done

    die "ไม่สามารถตรวจสอบ IPv4 สาธารณะของเซิร์ฟเวอร์ได้ กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต"
}

check_domain_points_here() {
    local domain="$1"
    local server_ip="$2"

    log_info "กำลังตรวจสอบ DNS ชี้มายังเซิร์ฟเวอร์หรือไม่: ${domain} -> ${server_ip}"
    local resolved_ip
    resolved_ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | head -n 1 || true)"

    if [[ -z "$resolved_ip" ]]; then
        resolved_ip="$(curl -4 -fsSL --max-time 5 "https://dns.google/resolve?name=${domain}&type=A" 2>/dev/null | jq -r '.Answer[0].data // empty' || true)"
    fi

    if [[ "$resolved_ip" == "$server_ip" ]]; then
        log_info "ตรวจสอบสำเร็จ: โดเมน ${domain} ชี้มาที่ IP ${server_ip} ถูกต้อง"
        return 0
    else
        log_warn "โดเมน ${domain} ไม่ได้ชี้มาที่ ${server_ip} (พบ: '${resolved_ip}')"
        return 1
    fi
}

download() {
    local url="$1"
    local dest="$2"
    local expected_hash="${3:-}"
    local max_retries=3
    local count=0
    local success=0

    mkdir -p "$(dirname "$dest")"

    log_info "กำลังดาวน์โหลด: ${url} -> ${dest}"
    while [[ $count -lt $max_retries ]]; do
        count=$((count + 1))
        if curl -fsSL --connect-timeout 10 --retry 2 -o "$dest" "$url"; then
            if [[ -s "$dest" ]]; then
                success=1
                break
            fi
        fi
        log_warn "ดาวน์โหลดล้มเหลว กำลังลองใหม่ (${count}/${max_retries})..."
        sleep 2
    done

    if [[ $success -ne 1 ]] || [[ ! -s "$dest" ]]; then
        die "ไม่สามารถดาวน์โหลดไฟล์ได้: ${url}"
    fi

    # ตรวจสอบ SHA256 หากระบุ
    if [[ -n "$expected_hash" ]]; then
        local actual_hash
        actual_hash="$(sha256sum "$dest" | awk '{print $1}')"
        if [[ "$actual_hash" != "$expected_hash" ]]; then
            rm -f "$dest"
            die "Checksum ตรวจสอบไม่ผ่านสำหรับ ${dest} (ได้: ${actual_hash}, ต้องการ: ${expected_hash})"
        fi
        log_info "ตรวจสอบ Checksum SHA-256 ผ่านเรียบร้อย"
    fi
}

# ------------------------------------------------------------------------------
# การจัดการ Service อย่างปลอดภัย
# ------------------------------------------------------------------------------
service_restart_safe() {
    local s_name="$1"
    log_info "กำลังรีสตาร์ตบริการ: ${s_name}"
    systemctl daemon-reload
    if systemctl restart "$s_name"; then
        if systemctl is-active --quiet "$s_name"; then
            log_info "บริการ ${s_name} ทำงานปกติ (active)"
            return 0
        fi
    fi
    log_error "บริการ ${s_name} ไม่สามารถเริ่มทำงานได้ กรุณาตรวจสอบ 'systemctl status ${s_name}'"
    return 1
}

# ------------------------------------------------------------------------------
# จัดการไฟล์คอนฟิกส่วนกลาง (/etc/toeyvpn/toeyvpn.conf)
# ------------------------------------------------------------------------------
conf_set() {
    local key="$1"
    local value="$2"
    touch "$CONF_FILE"
    if grep -q "^${key}=" "$CONF_FILE"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$CONF_FILE"
    else
        echo "${key}=\"${value}\"" >> "$CONF_FILE"
    fi
}

conf_get() {
    local key="$1"
    local default_value="${2:-}"
    if [[ -f "$CONF_FILE" ]]; then
        local val
        val="$(grep "^${key}=" "$CONF_FILE" | cut -d'=' -f2- | tr -d '"' || true)"
        if [[ -n "$val" ]]; then
            echo "$val"
            return 0
        fi
    fi
    echo "$default_value"
}
