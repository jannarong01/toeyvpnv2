#!/bin/bash
# TOEYVPN_SAFE_UPDATE_V1
# Insert immediately after the existing shebang.
# Keep the original script below this safety gate.

set -Eeuo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [[ $EUID -ne 0 ]]; then
    echo "[SSH ERROR] Run as root." >&2
    exit 1
fi

if [[ "${TOEYVPN_MANAGED_UPDATE:-}" != "TOEYVPN_SAFE_UPDATE_V1" ]]; then
    echo "[BLOCKED] Direct execution of the legacy installer is disabled." >&2
    echo "Use setup.sh --check or setup.sh --apply." >&2
    exit 1
fi

case "${1:---check}" in
    --check|--apply)
        ;;
    *)
        echo "[SSH ERROR] Unsupported mode." >&2
        exit 1
        ;;
esac

if [[ ! -s /home/vps/public_html/api_ssh.php ||
      ! -s /home/vps/public_html/index.php ||
      ! -x /usr/bin/panel-cmd ||
      ! -x /usr/bin/api-vpn ]]; then
    echo "[REPAIR REQUIRED] Existing panel components are incomplete." >&2
    echo "The legacy installer will not be run automatically." >&2
    exit 1
fi

if ! command -v nginx >/dev/null; then
    echo "[SSH ERROR] Nginx is missing." >&2
    exit 1
fi

if ! command -v php >/dev/null; then
    echo "[SSH ERROR] PHP CLI is missing; PHP syntax cannot be checked." >&2
    exit 1
fi

if [[ ! -x /usr/sbin/sshd ]]; then
    echo "[SSH ERROR] OpenSSH server is missing." >&2
    exit 1
fi

echo "[CHECK] Nginx configuration"
nginx -t

echo "[CHECK] OpenSSH configuration"
/usr/sbin/sshd -t

echo "[CHECK] Existing PHP syntax"
php -l /home/vps/public_html/api_ssh.php
php -l /home/vps/public_html/index.php

echo "[CHECK] Existing command syntax"
bash -n /usr/bin/api-vpn
bash -n /usr/bin/panel-cmd

if ! systemctl is-active --quiet nginx.service; then
    echo "[SSH ERROR] Nginx is not active. Diagnose it before applying maintenance." >&2
    exit 1
fi

if ! systemctl is-active --quiet ssh.service &&
   ! systemctl is-active --quiet sshd.service; then
    echo "[SSH ERROR] No active OpenSSH service was detected." >&2
    exit 1
fi

echo
echo "[SERVICE INVENTORY] Status only; no services will be restarted here."

for svc in \
    ssh dropbear nginx xray \
    udp-custom udpgw@7100 udpgw@7300 \
    zivpn hysteria ws-epro fail2ban cron
do
    load_state=$(systemctl show "$svc.service" -p LoadState --value 2>/dev/null) ||
        load_state="unknown"

    if [[ "$load_state" != "loaded" ]]; then
        printf '  %-18s NOT_LOADED\n' "$svc"
    elif systemctl is-active --quiet "$svc.service"; then
        printf '  %-18s ACTIVE\n' "$svc"
    else
        printf '  %-18s INACTIVE_OR_FAILED\n' "$svc"
    fi
done

echo
echo "[SECURITY NOTICE]"
echo "This maintenance release does not harden the existing web/API application."
echo "Review the existing sudo permissions, administrator authentication,"
echo "session directory permissions, account authorization, and log-cleanup jobs."
echo "Do not treat a successful syntax check as a security assessment."

if [[ -f /etc/sudoers.d/vpn-api ]]; then
    if grep -Eq '/(usr/)?bin/(sed|jq|systemctl)' /etc/sudoers.d/vpn-api; then
        echo "[WARNING] Broad command permissions were detected in vpn-api sudoers."
    fi
fi

if [[ -d /tmp/vpn_panel_sessions ]]; then
    session_mode=$(stat -c '%a' /tmp/vpn_panel_sessions)

    if (( (8#$session_mode & 0002) != 0 )); then
        echo "[WARNING] The panel session directory is writable by other users."
    fi
fi

if [[ -f /etc/xray/xray.key ]]; then
    key_mode=$(stat -c '%a' /etc/xray/xray.key)

    if (( (8#$key_mode & 0004) != 0 )); then
        echo "[WARNING] The TLS private key is readable by other local users."
    fi
fi

if [[ -f /usr/bin/clear-log ]]; then
    if grep -Eq 'truncate|drop_caches' /usr/bin/clear-log; then
        echo "[WARNING] Legacy destructive log/cache cleanup is still installed."
    fi
fi

echo
echo "[SKIP] Existing SSH/UDP/Hysteria/API application files were preserved."
echo "[SKIP] No users, passwords, certificates, firewall rules, or cron jobs were changed."
echo "[SKIP] The legacy installation body below this gate was not executed."

exit 0

# Original ssh-vpn.sh content continues below.
# ==============================================================================
#  ALL-IN-ONE VPN SUITE (TOEYVPN V2):
#  SSH/WS, DROPBEAR, UDP CUSTOM, BADVPN, ZIVPN, HYSTERIA 2, WEB PANEL & CLI MENU
#  Support: Ubuntu 20.04 / 22.04 / 24.04 LTS & Debian 10 / 11 / 12
# ==============================================================================
export DEBIAN_FRONTEND=noninteractive
REPO_URL="https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main"

# 1. ลบ Apache2 และ UFW ป้องกันการแย่งพอร์ต 80/443/8081
systemctl stop apache2 ufw firewalld >/dev/null 2>&1
systemctl disable apache2 ufw firewalld >/dev/null 2>&1
apt-get purge -y ufw firewalld exim4 apache2 apache2-utils apache2-bin apache2-data >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

# 2. ตั้งค่า Timezone เป็นเวลาไทย และเปิด IPv4 Forwarding
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
mkdir -p /etc/sysctl.d
cat <<EOF > /etc/sysctl.d/99-toeyvpnv2.conf
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
sysctl --system >/dev/null 2>&1

# 3. ติดตั้งแพ็กเกจหลัก + PHP-FPM + Fail2Ban + Iptables-Persistent + Zip/Unzip + Rsyslog
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update -y
apt-get install -y nginx dropbear vnstat curl wget jq python3 net-tools openssl socat cron fail2ban iptables iptables-persistent psmisc dos2unix php-fpm php-cli php-curl zip unzip rsyslog tar util-linux ca-certificates

# ติดตั้ง Speedtest by Ookla (Official CLI)
if [ ! -s /usr/local/bin/speedtest ]; then
    echo "กำลังติดตั้ง Speedtest by Ookla..."
    ARCH=$(uname -m)
    S_ARCH="x86_64"
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && S_ARCH="aarch64"
    wget -q -O /tmp/speedtest.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${S_ARCH}.tgz"
    tar -xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest 2>/dev/null
    chmod +x /usr/local/bin/speedtest
    rm -f /tmp/speedtest.tgz
fi

# เปิดใช้งาน rsyslog และเตรียมไฟล์ Log สำหรับ Ubuntu 24.04 และ Debian 12
touch /var/log/auth.log /var/log/syslog
chmod 640 /var/log/auth.log /var/log/syslog
systemctl enable rsyslog >/dev/null 2>&1
systemctl restart rsyslog

# 3.1 ปลดล็อก OpenSSH 9.2+ บน Debian 12 / Ubuntu 24.04 ให้รองรับแอปมือถือ + รับคนออนไลน์พร้อมกันเยอะๆ
mkdir -p /etc/ssh/sshd_config.d
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
cat <<EOF > /etc/ssh/sshd_config.d/99-vpn-compat.conf
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAcceptedKeyTypes +ssh-rsa,ssh-dss
HostKeyAlgorithms +ssh-rsa,ssh-dss
KexAlgorithms +diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1
MaxStartups 100:30:200
UseDNS no
EOF
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1

# 3.2 ตั้งค่า Dropbear (พอร์ต 109 และ 143) และปลดล็อก /bin/false ใน /etc/shells
grep -qxF '/bin/false' /etc/shells || echo '/bin/false' >> /etc/shells
grep -qxF '/usr/sbin/nologin' /etc/shells || echo '/usr/sbin/nologin' >> /etc/shells

cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF
touch /etc/issue.net
systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear >/dev/null 2>&1

# 3.3 ติดตั้ง SSH WebSocket (ws-epro พอร์ต 10015) จาก Repo toeyvpnv2
echo "กำลังติดตั้ง SSH WebSocket (Port 10015)..."
if wget -q -O /root/edu.sh "${REPO_URL}/websocket/edu.sh" && [ -s /root/edu.sh ]; then
    dos2unix /root/edu.sh >/dev/null 2>&1
    chmod +x /root/edu.sh
    /root/edu.sh
    rm -f /root/edu.sh
fi

# 3.4 ติดตั้ง BadVPN UDPGW (พอร์ต 7100 และ 7300)
echo "กำลังติดตั้ง BadVPN UDPGW (7100, 7300)..."
if [ ! -s /usr/bin/badvpn-udpgw ]; then
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        wget -q --no-check-certificate -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64" || \
        wget -q --no-check-certificate -O /usr/bin/badvpn-udpgw "https://github.com/ambrop72/badvpn/releases/download/1.999.130/badvpn-udpgw"
    else
        wget -q --no-check-certificate -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw"
    fi
    chmod +x /usr/bin/badvpn-udpgw
fi

cat <<EOF > /etc/systemd/system/udpgw@.service
[Unit]
Description=BadVPN UDPGW Service on Port %i
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:%i --max-clients 1000 --max-connections-for-client 100
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udpgw@7100 udpgw@7300 >/dev/null 2>&1
systemctl restart udpgw@7100 udpgw@7300 >/dev/null 2>&1

# ลบหน้าเริ่มต้นของ Nginx
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

# 4. ตั้งค่าระบบป้องกันการสุ่มรหัสผ่าน (Fail2Ban)
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log
backend = auto

[dropbear]
enabled = true
port = 109,143
logpath = /var/log/auth.log
backend = auto
EOF
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban >/dev/null 2>&1

# 5. ตั้งค่า Iptables บล็อก BitTorrent / P2P
for keyword in "get_peers" "announce_peer" "find_node" "BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "torrent" "announce" "info_hash"; do
    if ! iptables -C FORWARD -m string --string "$keyword" --algo bm -j DROP 2>/dev/null; then
        iptables -A FORWARD -m string --string "$keyword" --algo bm -j DROP
    fi
    if ! iptables -C OUTPUT -m string --string "$keyword" --algo bm -j DROP 2>/dev/null; then
        iptables -A OUTPUT -m string --string "$keyword" --algo bm -j DROP
    fi
done

# 6. เตรียมโฟลเดอร์หลักและใบรับรอง SSL เบื้องต้น
mkdir -p /etc/xray /etc/zivpn /etc/hysteria /home/vps/public_html /root/vnext_api /root/udp
touch /etc/xray/xray-exp.txt /etc/xray/xray-lock.txt /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

MYIP=$(curl -sS --max-time 5 ipv4.icanhazip.com || curl -sS --max-time 5 ifconfig.me)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
[ -z "$DOMAIN" ] && DOMAIN="$MYIP"

if [ ! -s /etc/xray/xray.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key \
        -out /etc/xray/xray.crt \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=ToeyVPNv2/CN=${DOMAIN}" >/dev/null 2>&1
    chmod 644 /etc/xray/xray.crt /etc/xray/xray.key
fi

# 7. ติดตั้ง Hysteria 2 (UDP Port 8443 และ Port Hopping 20000-50000)
if [ ! -s /usr/local/bin/hysteria ]; then
    echo "กำลังติดตั้ง Hysteria 2 Server..."
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64"
    else
        wget -q -O /usr/local/bin/hysteria "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-arm64"
    fi
    chmod +x /usr/local/bin/hysteria
fi

cat << 'EOF' > /usr/bin/hys-auth
#!/bin/bash
ADDR="$1"
AUTH="$2"
TX="$3"

MATCH_USER=$(awk -F: -v p="$AUTH" '$2 == p {print $1; exit}' /etc/hysteria/hys-users.txt)

if [ -z "$MATCH_USER" ]; then
    case "$AUTH" in
        *:*)
            u="${AUTH%%:*}"
            p="${AUTH#*:}"
            MATCH_USER=$(awk -F: -v usr="$u" -v pas="$p" '$1 == usr && $2 == pas {print $1; exit}' /etc/hysteria/hys-users.txt)
            ;;
    esac
fi

if [ -n "$MATCH_USER" ]; then
    echo "$MATCH_USER"
    exit 0
else
    exit 1
fi
EOF
chmod +x /usr/bin/hys-auth

cat << 'EOF' > /usr/bin/rebuild-hysteria
#!/bin/bash
mkdir -p /etc/hysteria
touch /etc/hysteria/hys-users.txt

cat <<YAML > /etc/hysteria/config.yaml
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
YAML

systemctl restart hysteria >/dev/null 2>&1
EOF
chmod +x /usr/bin/rebuild-hysteria

cat <<EOF > /etc/systemd/system/hysteria.service
[Unit]
Description=Hysteria 2 Server Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/hysteria
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

/usr/bin/rebuild-hysteria
systemctl daemon-reload
systemctl enable hysteria >/dev/null 2>&1
systemctl restart hysteria

# 8. ติดตั้ง ZIVPN UDP Tunnel (พอร์ต 5667 และ 6000-19999)
if [ ! -s /usr/local/bin/zivpn-udp ]; then
    echo "กำลังติดตั้ง ZIVPN UDP Server..."
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        wget -q -O /usr/local/bin/zivpn-udp "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
    else
        wget -q -O /usr/local/bin/zivpn-udp "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64"
    fi
    chmod +x /usr/local/bin/zivpn-udp
fi

if [ ! -s /etc/zivpn/zivpn.crt ]; then
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=ZIVPN/CN=zivpn" \
        -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

if [ ! -s /etc/zivpn/config.json ]; then
cat <<EOF > /etc/zivpn/config.json
{
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": [
      "zivpn-default"
    ]
  }
}
EOF
fi

cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN UDP Tunnel Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn-udp server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn >/dev/null 2>&1
systemctl restart zivpn

# 9. ติดตั้ง UDP Custom (พอร์ตภายใน 7200)
echo "กำลังติดตั้ง UDP Custom..."
mkdir -p /root/udp
UDP_SIZE=$(stat -c%s "/usr/local/bin/udp-custom" 2>/dev/null)
[ -z "$UDP_SIZE" ] && UDP_SIZE=0
if [ "$UDP_SIZE" -lt 1000000 ]; then
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        URLS=(
            "https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-amd64"
            "https://github.com/rudi9999/Herramientas/raw/main/UDP/udp-custom-linux-amd64"
            "https://raw.githubusercontent.com/zahidbd2/udp-custom/main/bin/udp-custom-linux-amd64"
        )
    else
        URLS=(
            "https://github.com/noobconner21/UDP-Custom-Script/raw/main/udp-custom-linux-arm"
            "https://github.com/rudi9999/Herramientas/raw/main/UDP/udp-custom-linux-arm"
        )
    fi
    for url in "${URLS[@]}"; do
        wget -q --no-check-certificate -O /usr/local/bin/udp-custom "$url"
        NEW_SIZE=$(stat -c%s "/usr/local/bin/udp-custom" 2>/dev/null)
        [ -z "$NEW_SIZE" ] && NEW_SIZE=0
        if [ "$NEW_SIZE" -gt 1000000 ]; then
            break
        fi
    done
fi
chmod +x /usr/local/bin/udp-custom
cp -f /usr/local/bin/udp-custom /root/udp/udp-custom
chmod +x /root/udp/udp-custom

cat <<EOF > /root/udp/config.json
{
  "listen": ":7200",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
EOF
chmod 644 /root/udp/config.json

cat <<EOF > /etc/systemd/system/udp-custom.service
[Unit]
Description=UDP Custom VPN Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/udp
ExecStart=/usr/local/bin/udp-custom server
Restart=always
RestartSec=3
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp-custom >/dev/null 2>&1
systemctl restart udp-custom

# 10. ตั้งค่า Iptables Port Forwarding แยกช่วงพอร์ตชัดเจน (ZIVPN + Hysteria 2 + UDP Custom)
NET_IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -F PREROUTING

iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 5667 -j ACCEPT
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 8443 -j ACCEPT
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :8443
iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 1:65535 -j DNAT --to-destination :7200

if ! iptables -t nat -C POSTROUTING -o "$NET_IFACE" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o "$NET_IFACE" -j MASQUERADE
fi

for uport in 7200 5667 8443; do
    if ! iptables -C INPUT -p udp --dport "$uport" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport "$uport" -j ACCEPT
    fi
done

# 11. ติดตั้งระบบ Web API & Web Dashboard (Port 8081)
cat << 'EOF' > /usr/bin/api-vpn
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exec 200>/var/lock/api-vpn.lock
if ! flock -w 10 200; then
    rm -f /var/lock/api-vpn.lock 2>/dev/null
    exec 200>/var/lock/api-vpn.lock
    flock -n 200
fi

ACTION=$1
USER=$2
PASS=$3
EXP=$4

mkdir -p /etc/zivpn /etc/hysteria
touch /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

if ! pgrep -x "useradd" >/dev/null && ! pgrep -x "usermod" >/dev/null && ! pgrep -x "chpasswd" >/dev/null; then
    rm -f /etc/passwd.lock /etc/shadow.lock /etc/group.lock /etc/gshadow.lock /etc/.pwd.lock 2>/dev/null
fi

if ! echo "$EXP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    EXP=$(date -d "+1 days" +"%Y-%m-%d")
fi

if [ "$ACTION" = "add" ]; then
    for i in 1 2 3; do
        if ! id "$USER" >/dev/null 2>&1; then
            if ! pgrep -x "useradd" >/dev/null; then
                rm -f /etc/passwd.lock /etc/shadow.lock /etc/group.lock /etc/gshadow.lock /etc/.pwd.lock 2>/dev/null
            fi
            /usr/sbin/useradd -e "$EXP" -s /bin/false -M "$USER" 2>/dev/null || \
            /usr/sbin/useradd -e "$EXP" -s /bin/false -M -N "$USER" 2>/dev/null
            sleep 0.3
        else
            break
        fi
    done

    if ! id "$USER" >/dev/null 2>&1; then
        flock -u 200
        exit 1
    fi

    echo "$USER:$PASS" | /usr/sbin/chpasswd 2>/dev/null
    /usr/bin/chage -E "$EXP" "$USER" 2>/dev/null
    /usr/sbin/usermod -e "$EXP" "$USER" 2>/dev/null

    if [ -n "$PASS" ] && [ -f /etc/zivpn/config.json ]; then
        jq --arg p "$PASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > "/tmp/zivpn_tmp_$$.json"
        if [ -s "/tmp/zivpn_tmp_$$.json" ]; then
            mv "/tmp/zivpn_tmp_$$.json" /etc/zivpn/config.json
        else
            rm -f "/tmp/zivpn_tmp_$$.json"
        fi
        sed -i "/^${PASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${PASS}:${EXP}" >> /etc/zivpn/zivpn-exp.txt
        sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
        echo "${USER}:${PASS}" >> /etc/zivpn/zivpn-users.txt
        (systemctl restart zivpn >/dev/null 2>&1) 200>&- &
    fi

    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        sed -i "/^${USER}:/d" /etc/hysteria/hys-users.txt
        echo "${USER}:${PASS}:${EXP}" >> /etc/hysteria/hys-users.txt
        (/usr/bin/rebuild-hysteria >/dev/null 2>&1) 200>&- &
    fi

elif [ "$ACTION" = "renew" ]; then
    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt | cut -d: -f2 | tail -n 1)
    HPASS=$(grep "^${USER}:" /etc/hysteria/hys-users.txt | cut -d: -f2 | tail -n 1)
    [ -z "$ZPASS" ] && [ -n "$PASS" ] && ZPASS="$PASS"
    [ -z "$ZPASS" ] && [ -n "$HPASS" ] && ZPASS="$HPASS"
    [ -z "$HPASS" ] && [ -n "$ZPASS" ] && HPASS="$ZPASS"

    if ! id "$USER" >/dev/null 2>&1; then
        for i in 1 2 3; do
            if ! id "$USER" >/dev/null 2>&1; then
                /usr/sbin/useradd -e "$EXP" -s /bin/false -M "$USER" 2>/dev/null || \
                /usr/sbin/useradd -e "$EXP" -s /bin/false -M -N "$USER" 2>/dev/null
                sleep 0.3
            else
                break
            fi
        done
        if [ -n "$ZPASS" ]; then
            echo "$USER:$ZPASS" | /usr/sbin/chpasswd 2>/dev/null
        fi
    elif [ -n "$PASS" ]; then
        echo "$USER:$PASS" | /usr/sbin/chpasswd 2>/dev/null
    fi

    if ! id "$USER" >/dev/null 2>&1; then
        flock -u 200
        exit 1
    fi

    /usr/bin/chage -E "$EXP" "$USER" 2>/dev/null
    /usr/sbin/usermod -e "$EXP" "$USER" 2>/dev/null
    /usr/bin/passwd -u "$USER" >/dev/null 2>&1

    if [ -n "$ZPASS" ]; then
        sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
        echo "${USER}:${ZPASS}" >> /etc/zivpn/zivpn-users.txt
        sed -i "/^${ZPASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${ZPASS}:${EXP}" >> /etc/zivpn/zivpn-exp.txt
        if [ -f /etc/zivpn/config.json ]; then
            jq --arg p "$ZPASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > "/tmp/zivpn_tmp_$$.json"
            if [ -s "/tmp/zivpn_tmp_$$.json" ]; then
                mv "/tmp/zivpn_tmp_$$.json" /etc/zivpn/config.json
            else
                rm -f "/tmp/zivpn_tmp_$$.json"
            fi
            (systemctl restart zivpn >/dev/null 2>&1) 200>&- &
        fi
    fi

    if [ -n "$HPASS" ]; then
        sed -i "/^${USER}:/d" /etc/hysteria/hys-users.txt
        echo "${USER}:${HPASS}:${EXP}" >> /etc/hysteria/hys-users.txt
        (/usr/bin/rebuild-hysteria >/dev/null 2>&1) 200>&- &
    fi

elif [ "$ACTION" = "delete" ]; then
    /usr/bin/killall -u "$USER" 2>/dev/null
    /usr/sbin/userdel -f "$USER" 2>/dev/null
    /usr/sbin/groupdel "$USER" 2>/dev/null

    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt | cut -d: -f2 | tail -n 1)
    sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
    if [ -n "$ZPASS" ] && [ -f /etc/zivpn/config.json ]; then
        if ! grep -q ":${ZPASS}$" /etc/zivpn/zivpn-users.txt; then
            jq --arg p "$ZPASS" '.auth.config -= [$p]' /etc/zivpn/config.json > "/tmp/zivpn_tmp_$$.json"
            if [ -s "/tmp/zivpn_tmp_$$.json" ]; then
                mv "/tmp/zivpn_tmp_$$.json" /etc/zivpn/config.json
            else
                rm -f "/tmp/zivpn_tmp_$$.json"
            fi
            sed -i "/^${ZPASS}:/d" /etc/zivpn/zivpn-exp.txt
            (systemctl restart zivpn >/dev/null 2>&1) 200>&- &
        fi
    fi

    if grep -q "^${USER}:" /etc/hysteria/hys-users.txt; then
        sed -i "/^${USER}:/d" /etc/hysteria/hys-users.txt
        (/usr/bin/rebuild-hysteria >/dev/null 2>&1) 200>&- &
    fi
fi

flock -u 200
exit 0
EOF
chmod +x /usr/bin/api-vpn

# Backend หน้า Web Dashboard (/usr/bin/panel-cmd)
cat << 'EOF' > /usr/bin/panel-cmd
#!/bin/bash
export LC_ALL=C
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ACTION="$1"

MYIP=$(curl -sS --max-time 2 ipv4.icanhazip.com 2>/dev/null)
if [ -z "$MYIP" ]; then
    MYIP=$(hostname -I | awk '{print $1}')
fi
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
if [ -z "$DOMAIN" ]; then
    DOMAIN="$MYIP"
fi

case "$ACTION" in
    stats)
        RAM_USED=$(free -m | awk 'NR==2{print $3}')
        RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
        CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | tr -d ' ')
        UPTIME_STR=$(uptime -p | sed 's/up //')

        SSH_ON=0
        for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
            c=$(pgrep -u "$u" sshd 2>/dev/null | wc -l)
            SSH_ON=$((SSH_ON + c))
        done

        Services=("ssh" "dropbear" "nginx" "xray" "udp-custom" "udpgw@7300" "zivpn" "hysteria" "ws-epro" "fail2ban")
        SVC_JSON="{"
        first=1
        for s in "${Services[@]}"; do
            if systemctl is-active --quiet "$s"; then
                st="ON"
            else
                st="OFF"
            fi
            [ $first -eq 0 ] && SVC_JSON="${SVC_JSON},"
            SVC_JSON="${SVC_JSON}\"${s}\":\"${st}\""
            first=0
        done
        SVC_JSON="${SVC_JSON}}"

        jq -n \
            --arg ip "$MYIP" \
            --arg dom "$DOMAIN" \
            --arg ram_u "$RAM_USED" \
            --arg ram_t "$RAM_TOTAL" \
            --arg cpu "$CPU_LOAD" \
            --arg up "$UPTIME_STR" \
            --arg ssh_on "$SSH_ON" \
            --argjson svc "$SVC_JSON" \
            '{ip:$ip, domain:$dom, ram_used:$ram_u, ram_total:$ram_t, cpu:$cpu, uptime:$up, ssh_online:$ssh_on, services:$svc}'
        ;;

    list_ssh)
        echo "["
        first=1
        USERS_LIST=$(tac /etc/passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}')
        for u in $USERS_LIST; do
            exp_raw=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            if [ "$exp_raw" = "never" ] || [ -z "$exp_raw" ]; then
                exp="Never"
            else
                exp=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
                [ -z "$exp" ] && exp="$exp_raw"
            fi
            pstat=$(passwd -S "$u" 2>/dev/null | awk '{print $2}')
            if [ "$pstat" = "L" ]; then
                stat="Locked"
            else
                stat="Active"
            fi
            on_cnt=$(pgrep -u "$u" sshd 2>/dev/null | wc -l)
            pass=$(grep "^${u}:" /etc/zivpn/zivpn-users.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
            [ -z "$pass" ] && pass="-"

            [ $first -eq 0 ] && echo ","
            jq -n --arg u "$u" --arg p "$pass" --arg e "$exp" --arg s "$stat" --arg o "$on_cnt" \
                '{user:$u, pass:$p, exp:$e, status:$s, online:$o}'
            first=0
        done
        echo "]"
        ;;

    list_xray)
        echo "["
        first=1
        if [ -s /etc/xray/xray-exp.txt ]; then
            while IFS=':' read -r u exp; do
                [ -z "$u" ] && continue
                if grep -q "^${u}:" /etc/xray/xray-lock.txt 2>/dev/null; then
                    uuid=$(grep "^${u}:" /etc/xray/xray-lock.txt | cut -d: -f2)
                    stat="Locked"
                else
                    uuid=$(jq -r --arg usr "$u" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json 2>/dev/null)
                    stat="Active"
                fi
                [ -z "$uuid" ] && continue

                v_tls_json=$(printf '{"v":"2","ps":"%s-TLS","add":"%s","port":"443","id":"%s","aid":"0","net":"ws","path":"/vmess","type":"none","host":"%s","tls":"tls"}' "$u" "$DOMAIN" "$uuid" "$DOMAIN" | base64 -w 0)
                v_ntls_json=$(printf '{"v":"2","ps":"%s-HTTP","add":"%s","port":"80","id":"%s","aid":"0","net":"ws","path":"/vmess","type":"none","host":"%s","tls":"none"}' "$u" "$DOMAIN" "$uuid" "$DOMAIN" | base64 -w 0)
                vmess_tls="vmess://${v_tls_json}"
                vmess_ntls="vmess://${v_ntls_json}"
                vless_tls="vless://${uuid}@${DOMAIN}:443?path=%2Fvless&security=tls&encryption=none&type=ws&host=${DOMAIN}&sni=${DOMAIN}#${u}-TLS"
                vless_ntls="vless://${uuid}@${DOMAIN}:80?path=%2Fvless&security=none&encryption=none&type=ws&host=${DOMAIN}#${u}-HTTP"

                [ $first -eq 0 ] && echo ","
                jq -n --arg u "$u" --arg e "$exp" --arg s "$stat" --arg id "$uuid" \
                      --arg vmt "$vmess_tls" --arg vmn "$vmess_ntls" --arg vlt "$vless_tls" --arg vln "$vless_ntls" \
                      '{user:$u, exp:$e, status:$s, uuid:$id, vmess_tls:$vmt, vmess_http:$vmn, vless_tls:$vlt, vless_http:$vln}'
                first=0
            done < /etc/xray/xray-exp.txt
        fi
        echo "]"
        ;;

    add_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        PASS=$(echo "$3" | tr -cd 'a-zA-Z0-9_@#.-')
        DAYS=$(echo "$4" | tr -cd '0-9')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"กรุณากรอกชื่อผู้ใช้"}'; exit 0; fi
        if [ -z "$PASS" ]; then echo '{"success":false,"msg":"กรุณากรอกรหัสผ่าน"}'; exit 0; fi
        if [ -z "$DAYS" ]; then DAYS=30; fi
        if id "$USER" >/dev/null 2>&1; then
            echo '{"success":false,"msg":"มีชื่อผู้ใช้นี้ในระบบแล้ว"}'
            exit 0
        fi
        EXP=$(date -d "$DAYS days" +"%Y-%m-%d")
        /usr/bin/api-vpn add "$USER" "$PASS" "$EXP" >/dev/null 2>&1
        if id "$USER" >/dev/null 2>&1; then
            echo "{\"success\":true,\"msg\":\"สร้างบัญชี $USER สำเร็จ (หมดอายุ $EXP)\",\"user\":\"$USER\",\"pass\":\"$PASS\",\"exp\":\"$EXP\"}"
        else
            echo "{\"success\":false,\"msg\":\"สร้างบัญชี $USER ไม่สำเร็จ! กรุณาลองใหม่อีกครั้ง\"}"
        fi
        ;;

    renew_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        DAYS=$(echo "$3" | tr -cd '0-9')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"ไม่พบชื่อผู้ใช้"}'; exit 0; fi
        if [ -z "$DAYS" ]; then DAYS=30; fi
        exp_old=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        today_sec=$(date +%s)
        exp_sec=$(date -d "$exp_old" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$exp_old" +%Y-%m-%d 2>/dev/null)
            [ -z "$base_date" ] && base_date=$(date +%Y-%m-%d)
        fi
        NEW_EXP=$(date -d "$base_date + $DAYS days" +%Y-%m-%d)
        /usr/bin/api-vpn renew "$USER" "" "$NEW_EXP" >/dev/null 2>&1
        echo "{\"success\":true,\"msg\":\"ต่ออายุ $USER สำเร็จ (หมดอายุ $NEW_EXP)\"}"
        ;;

    set_pass)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        PASS=$(echo "$3" | tr -cd 'a-zA-Z0-9_@#.-')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"ไม่พบชื่อผู้ใช้"}'; exit 0; fi
        if [ -z "$PASS" ]; then echo '{"success":false,"msg":"กรุณากรอกรหัสผ่าน"}'; exit 0; fi
        exp_raw=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        EXP=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
        [ -z "$EXP" ] && EXP=$(date -d "30 days" +%Y-%m-%d)
        /usr/bin/api-vpn add "$USER" "$PASS" "$EXP" >/dev/null 2>&1
        echo "{\"success\":true,\"msg\":\"บันทึกรหัสผ่านของ $USER เรียบร้อยแล้ว\"}"
        ;;

    del_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        /usr/bin/api-vpn delete "$USER" "" "" >/dev/null 2>&1
        echo "{\"success\":true,\"msg\":\"ลบบัญชี $USER เรียบร้อยแล้ว\"}"
        ;;

    toggle_ssh)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        pstat=$(passwd -S "$USER" 2>/dev/null | awk '{print $2}')
        if [ "$pstat" = "L" ]; then
            passwd -u "$USER" >/dev/null 2>&1
            echo "{\"success\":true,\"msg\":\"ปลดล็อกบัญชี $USER แล้ว\"}"
        else
            passwd -l "$USER" >/dev/null 2>&1
            killall -u "$USER" >/dev/null 2>&1
            echo "{\"success\":true,\"msg\":\"ระงับบัญชี $USER ชั่วคราวแล้ว\"}"
        fi
        ;;

    add_xray)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        DAYS=$(echo "$3" | tr -cd '0-9')
        if [ -z "$USER" ]; then echo '{"success":false,"msg":"กรุณากรอกชื่อบัญชี"}'; exit 0; fi
        if [ -z "$DAYS" ]; then DAYS=30; fi
        if grep -q "^${USER}:" /etc/xray/xray-exp.txt 2>/dev/null; then
            echo '{"success":false,"msg":"มีชื่อบัญชี Xray นี้แล้ว"}'
            exit 0
        fi
        EXP=$(date -d "$DAYS days" +"%Y-%m-%d")
        UUID=$(cat /proc/sys/kernel/random/uuid)
        (
            flock -x 200
            jq --arg u "$USER" --arg id "$UUID" \
               '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] |
                .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            echo "$USER:$EXP" >> /etc/xray/xray-exp.txt
        ) 200>/var/lock/vpn-panel.lock
        (sleep 1 && systemctl restart xray) >/dev/null 2>&1 &
        echo "{\"success\":true,\"msg\":\"สร้างบัญชี Xray $USER สำเร็จ\"}"
        ;;

    renew_xray)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        DAYS=$(echo "$3" | tr -cd '0-9')
        [ -z "$DAYS" ] && DAYS=30
        old_exp=$(grep "^${USER}:" /etc/xray/xray-exp.txt | cut -d: -f2)
        if [ -z "$old_exp" ]; then echo '{"success":false,"msg":"ไม่พบชื่อบัญชี"}'; exit 0; fi
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d 2>/dev/null)
            [ -z "$base_date" ] && base_date=$(date +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $DAYS days" +%Y-%m-%d)
        (
            flock -x 200
            sed -i "s/^${USER}:${old_exp}/${USER}:${new_exp}/g" /etc/xray/xray-exp.txt
        ) 200>/var/lock/vpn-panel.lock
        echo "{\"success\":true,\"msg\":\"ต่ออายุ Xray $USER ถึง $new_exp สำเร็จ\"}"
        ;;

    del_xray)
        USER=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        (
            flock -x 200
            jq --arg u "$USER" \
               '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            sed -i "/^${USER}:/d" /etc/xray/xray-exp.txt
            sed -i "/^${USER}:/d" /etc/xray/xray-lock.txt 2>/dev/null
        ) 200>/var/lock/vpn-panel.lock
        (sleep 1 && systemctl restart xray) >/dev/null 2>&1 &
        echo "{\"success\":true,\"msg\":\"ลบบัญชี Xray $USER เรียบร้อยแล้ว\"}"
        ;;

    restart_all)
        (
            sleep 1
            for svc in rsyslog ssh sshd dropbear xray zivpn hysteria udp-custom ws-epro udpgw@7100 udpgw@7300 fail2ban cron nginx; do
                systemctl restart "$svc" >/dev/null 2>&1
            done
        ) >/dev/null 2>&1 &
        echo '{"success":true,"msg":"กำลังรีสตาร์ทบริการทั้งหมด (รอประมาณ 3 วินาที)"}'
        ;;

    clear_ram)
        /usr/bin/clear-log >/dev/null 2>&1
        echo '{"success":true,"msg":"ล้างไฟล์ขยะ Log และเคลียร์ RAM Cache เรียบร้อยแล้ว"}'
        ;;

    run_speedtest)
        if pgrep -f "/usr/local/bin/speedtest" >/dev/null 2>&1; then
            echo '{"success":false,"msg":"กำลังทดสอบความเร็วอยู่ กรุณารอสักครู่..."}'
            exit 0
        fi
        echo "กำลังเชื่อมต่อเซิร์ฟเวอร์ Ookla Speedtest... กรุณารอ 15-25 วินาที" > /tmp/speedtest_panel.log
        (
            if [ ! -s /usr/local/bin/speedtest ]; then
                ARCH=$(uname -m)
                S_ARCH="x86_64"
                [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && S_ARCH="aarch64"
                wget -q -O /tmp/speedtest.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${S_ARCH}.tgz"
                tar -xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest 2>/dev/null
                chmod +x /usr/local/bin/speedtest
                rm -f /tmp/speedtest.tgz
            fi
            /usr/local/bin/speedtest --accept-license --accept-gdpr > /tmp/speedtest_panel.log 2>&1
        ) >/dev/null 2>&1 &
        echo '{"success":true,"msg":"เริ่มการทดสอบความเร็วแล้ว"}'
        ;;

    get_speedtest)
        if pgrep -f "/usr/local/bin/speedtest" >/dev/null 2>&1; then
            RUNNING=true
        else
            RUNNING=false
        fi
        CONTENT=$(cat /tmp/speedtest_panel.log 2>/dev/null)
        [ -z "$CONTENT" ] && CONTENT="กดปุ่ม 'เริ่มวัดความเร็ว' ด้านบนเพื่อทดสอบความเร็วอินเทอร์เน็ตของ VPS"
        jq -n --argjson r "$RUNNING" --arg c "$CONTENT" '{running:$r, output:$c}'
        ;;
esac
EOF
chmod +x /usr/bin/panel-cmd

cat <<EOF > /etc/sudoers.d/vpn-api
www-data ALL=(ALL) NOPASSWD: /usr/bin/api-vpn, /usr/bin/panel-cmd, /usr/bin/rebuild-hysteria, /usr/sbin/useradd, /usr/sbin/usermod, /usr/sbin/groupdel, /usr/sbin/chpasswd, /usr/bin/chage, /usr/sbin/userdel, /usr/bin/killall, /bin/systemctl, /usr/bin/jq, /bin/sed
EOF
chmod 440 /etc/sudoers.d/vpn-api

if [ -s /home/vps/public_html/api_ssh.php ]; then
    SAVED_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php | cut -d'"' -f2)
fi
[ -z "$SAVED_KEY" ] && SAVED_KEY="VNEXT_SSH_999"

cat <<EOF > /home/vps/public_html/api_ssh.php
<?php
header('Content-Type: application/json');
\$secret_key = "${SAVED_KEY}";

\$req_key = \$_POST['key'] ?? '';
if (\$req_key !== \$secret_key) {
    die(json_encode(['success' => false, 'msg' => 'Invalid Key']));
}

\$action = \$_POST['action'] ?? '';
\$user = preg_replace('/[^a-zA-Z0-9_]/', '', \$_POST['user'] ?? '');
\$pass = preg_replace('/[^a-zA-Z0-9_@#]/', '', \$_POST['pass'] ?? '');
\$days = intval(\$_POST['days'] ?? 0);

if (empty(\$user)) {
    die(json_encode(['success' => false, 'msg' => 'User empty']));
}

if (\$days < 1) {
    \$days = 1;
}

if (\$action === 'add') {
    \$exp = date('Y-m-d', strtotime("+\$days days"));
    exec("sudo /usr/bin/api-vpn add '\$user' '\$pass' '\$exp' 2>&1", \$out, \$ret);
    exec("id -u '\$user' 2>/dev/null", \$id_out, \$id_ret);
    if (\$id_ret === 0) {
        echo json_encode(['success' => true, 'exp' => \$exp]);
    } else {
        echo json_encode(['success' => false, 'msg' => 'Create user failed']);
    }
} elseif (\$action === 'renew') {
    \$exp = date('Y-m-d', strtotime("+\$days days"));
    exec("sudo /usr/bin/api-vpn renew '\$user' '\$pass' '\$exp' 2>&1", \$out, \$ret);
    exec("id -u '\$user' 2>/dev/null", \$id_out, \$id_ret);
    if (\$id_ret === 0) {
        echo json_encode(['success' => true, 'exp' => \$exp]);
    } else {
        echo json_encode(['success' => false, 'msg' => 'Renew user failed']);
    }
} elseif (\$action === 'delete') {
    exec("sudo /usr/bin/api-vpn delete '\$user' '' '' 2>&1", \$out, \$ret);
    echo json_encode(['success' => true]);
} else {
    echo json_encode(['success' => false, 'msg' => 'Unknown action']);
}
?>
EOF

cp -f /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php

# สร้างหน้า Web Dashboard (Modern Glassmorphism UI + ระบบจำสิทธิ์ Cookie HMAC ป้องกันเด้งหลุด)
cat << 'EOF' > /home/vps/public_html/index.php
<?php
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");

$sess_dir = "/tmp/vpn_panel_sessions";
if (!is_dir($sess_dir)) {
    @mkdir($sess_dir, 0777, true);
}
@chmod($sess_dir, 0777);
session_save_path($sess_dir);
session_name("TOEYVPN_NODE_SESS");
session_start();

$admin_pass = "VNEXT_SSH_999";
if (file_exists(__DIR__ . '/api_ssh.php')) {
    $api_content = file_get_contents(__DIR__ . '/api_ssh.php');
    if (preg_match('/\$secret_key\s*=\s*"([^"]+)"/', $api_content, $m)) {
        $admin_pass = $m[1];
    }
}

$auth_token = hash_hmac('sha256', $admin_pass, 'toeyvpn_node_auth_v1');

if (isset($_COOKIE['toeyvpn_node_token']) && $_COOKIE['toeyvpn_node_token'] === $auth_token) {
    $_SESSION['vpn_admin_logged'] = true;
}

if (isset($_GET['logout'])) {
    $_SESSION = [];
    session_destroy();
    setcookie('toeyvpn_node_token', '', time() - 3600, '/');
    header("Location: index.php?t=" . time());
    exit;
}

$login_error = "";
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login_pass'])) {
    if (trim($_POST['login_pass']) === $admin_pass) {
        $_SESSION['vpn_admin_logged'] = true;
        setcookie('toeyvpn_node_token', $auth_token, time() + (86400 * 30), '/', '', false, true);
        session_write_close();
        header("Location: index.php?t=" . time());
        exit;
    } else {
        $login_error = "รหัสผ่านไม่ถูกต้อง! (ใช้รหัสเดียวกับ Secret Key ในเมนู 28)";
    }
}

if (isset($_GET['ajax']) && !empty($_SESSION['vpn_admin_logged'])) {
    header('Content-Type: application/json; charset=utf-8');
    $act = $_GET['ajax'];

    if ($act === 'stats') {
        echo shell_exec("sudo /usr/bin/panel-cmd stats");
    } elseif ($act === 'list_ssh') {
        echo shell_exec("sudo /usr/bin/panel-cmd list_ssh");
    } elseif ($act === 'list_xray') {
        echo shell_exec("sudo /usr/bin/panel-cmd list_xray");
    } elseif ($act === 'add_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $p = escapeshellarg($_POST['pass'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd add_ssh $u $p $d");
    } elseif ($act === 'renew_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd renew_ssh $u $d");
    } elseif ($act === 'set_pass') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $p = escapeshellarg($_POST['pass'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd set_pass $u $p");
    } elseif ($act === 'del_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd del_ssh $u");
    } elseif ($act === 'toggle_ssh') {
        $u = escapeshellarg($_POST['user'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd toggle_ssh $u");
    } elseif ($act === 'add_xray') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd add_xray $u $d");
    } elseif ($act === 'renew_xray') {
        $u = escapeshellarg($_POST['user'] ?? '');
        $d = escapeshellarg($_POST['days'] ?? '30');
        echo shell_exec("sudo /usr/bin/panel-cmd renew_xray $u $d");
    } elseif ($act === 'del_xray') {
        $u = escapeshellarg($_POST['user'] ?? '');
        echo shell_exec("sudo /usr/bin/panel-cmd del_xray $u");
    } elseif ($act === 'restart_all') {
        echo shell_exec("sudo /usr/bin/panel-cmd restart_all");
    } elseif ($act === 'clear_ram') {
        echo shell_exec("sudo /usr/bin/panel-cmd clear_ram");
    } elseif ($act === 'run_speedtest') {
        echo shell_exec("sudo /usr/bin/panel-cmd run_speedtest");
    } elseif ($act === 'get_speedtest') {
        echo shell_exec("sudo /usr/bin/panel-cmd get_speedtest");
    }
    exit;
}
?>
<!DOCTYPE html>
<html lang="th" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>TOEYVPN V2 • Node Management Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;600;700;800&family=Prompt:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/remixicon@4.2.0/fonts/remixicon.css" rel="stylesheet">
    <style>
        * { font-family: 'Prompt', 'Plus Jakarta Sans', sans-serif; }
        body {
            background-color: #060913;
            background-image: 
                radial-gradient(at 0% 0%, rgba(6, 182, 212, 0.14) 0px, transparent 50%),
                radial-gradient(at 100% 0%, rgba(99, 102, 241, 0.12) 0px, transparent 50%),
                radial-gradient(at 50% 100%, rgba(16, 185, 129, 0.08) 0px, transparent 50%);
            background-attachment: fixed;
            color: #f1f5f9;
        }
        .glass-card {
            background: rgba(15, 23, 42, 0.72);
            backdrop-filter: blur(16px);
            -webkit-backdrop-filter: blur(16px);
            border: 1px solid rgba(255, 255, 255, 0.08);
            box-shadow: 0 10px 30px -10px rgba(0, 0, 0, 0.5);
        }
        .glow-dot-on { box-shadow: 0 0 10px #10b981, 0 0 20px #10b981; }
        .glow-dot-off { box-shadow: 0 0 10px #ef4444; }
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-track { background: #0f172a; }
        ::-webkit-scrollbar-thumb { background: #334155; border-radius: 3px; }
    </style>
</head>
<body class="min-h-screen pb-12 selection:bg-cyan-500 selection:text-slate-950">

<?php if (empty($_SESSION['vpn_admin_logged'])): ?>
    <div class="flex items-center justify-center min-h-screen px-4">
        <div class="glass-card p-8 rounded-3xl w-full max-w-md relative overflow-hidden">
            <div class="absolute -top-20 -right-20 w-40 h-40 bg-cyan-500/20 rounded-full blur-3xl pointer-events-none"></div>
            <div class="flex flex-col items-center text-center mb-7">
                <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-cyan-400 to-blue-600 flex items-center justify-center shadow-lg shadow-cyan-500/25 mb-4">
                    <i class="ri-shield-keyhole-fill text-3xl text-slate-950"></i>
                </div>
                <h1 class="text-2xl font-bold bg-gradient-to-r from-white via-cyan-200 to-cyan-400 bg-clip-text text-transparent">
                    TOEYVPN V2 NODE PANEL
                </h1>
                <p class="text-slate-400 text-xs mt-1">ระบบจัดการเซิร์ฟเวอร์ VPN ครบวงจร (Port 8081)</p>
            </div>

            <?php if ($login_error): ?>
                <div class="bg-red-500/15 border border-red-500/40 text-red-300 text-xs p-3.5 rounded-xl mb-5 flex items-center gap-2.5">
                    <i class="ri-error-warning-fill text-lg text-red-400"></i>
                    <span><?= htmlspecialchars($login_error) ?></span>
                </div>
            <?php endif; ?>

            <form method="POST" class="space-y-4">
                <div>
                    <label class="block text-xs font-medium text-slate-300 mb-2 ml-1">รหัสผ่านผู้ดูแลระบบ (Secret Key)</label>
                    <div class="relative">
                        <i class="ri-key-2-line absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 text-lg"></i>
                        <input type="password" name="login_pass" required placeholder="กรอก Secret Key ของโหนดนี้..."
                               class="w-full pl-11 pr-4 py-3.5 rounded-xl bg-slate-950/80 border border-slate-700/80 text-sm text-white placeholder-slate-500 focus:outline-none focus:border-cyan-400 focus:ring-1 focus:ring-cyan-400 transition">
                    </div>
                </div>
                <button type="submit" class="w-full bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-bold py-3.5 rounded-xl shadow-lg shadow-cyan-500/20 transition flex items-center justify-center gap-2 text-sm">
                    <i class="ri-login-circle-line text-lg"></i> เข้าสู่ระบบจัดการ
                </button>
            </form>
        </div>
    </div>

<?php else: ?>
    <header class="sticky top-0 z-30 glass-card border-b border-white/10 px-4 py-3">
        <div class="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-3 min-w-0">
                <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-cyan-400 to-blue-600 flex items-center justify-center shadow-md shadow-cyan-500/20 shrink-0">
                    <i class="ri-server-fill text-xl text-slate-950"></i>
                </div>
                <div class="min-w-0">
                    <div class="flex items-center gap-2">
                        <span class="font-bold text-base tracking-wide text-white">TOEYVPN V2</span>
                        <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-cyan-500/20 text-cyan-300 border border-cyan-500/30">NODE</span>
                    </div>
                    <div class="flex items-center gap-1.5 text-xs text-slate-400 truncate">
                        <span class="w-2 h-2 rounded-full bg-emerald-400 glow-dot-on shrink-0"></span>
                        <span id="nav-domain" class="truncate">กำลังโหลดข้อมูล...</span>
                    </div>
                </div>
            </div>

            <div class="flex items-center gap-1.5 sm:gap-2 ml-auto">
                <button onclick="clearRam()" class="flex items-center gap-1.5 text-xs font-medium bg-amber-500/15 hover:bg-amber-500/25 text-amber-300 border border-amber-500/30 px-3 py-2 rounded-xl transition">
                    <i class="ri-brush-3-line text-sm"></i>
                    <span class="hidden sm:inline">เคลียร์ RAM</span>
                </button>
                <button onclick="restartAll()" class="flex items-center gap-1.5 text-xs font-medium bg-indigo-500/15 hover:bg-indigo-500/25 text-indigo-300 border border-indigo-500/30 px-3 py-2 rounded-xl transition">
                    <i class="ri-restart-line text-sm"></i>
                    <span class="hidden sm:inline">รีสตาร์ทบริการ</span>
                </button>
                <a href="?logout=1" class="flex items-center gap-1 text-xs font-medium bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 border border-rose-500/30 px-3 py-2 rounded-xl transition" title="ออกจากระบบ">
                    <i class="ri-logout-box-r-line text-sm"></i>
                </a>
            </div>
        </div>
    </header>

    <main class="max-w-7xl mx-auto px-4 pt-5 space-y-5">
        <div id="toast" class="hidden fixed bottom-5 right-5 left-5 sm:left-auto glass-card border-emerald-500/50 bg-slate-900/95 text-white px-4 py-3.5 rounded-2xl shadow-2xl z-50 flex items-center gap-3 text-xs sm:text-sm font-medium transition-all">
            <i class="ri-checkbox-circle-fill text-xl text-emerald-400 shrink-0"></i>
            <span id="toast-msg">สำเร็จ</span>
        </div>

        <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">Host / Domain</span>
                    <div class="w-8 h-8 rounded-lg bg-cyan-500/15 border border-cyan-500/25 flex items-center justify-center text-cyan-400 shrink-0">
                        <i class="ri-global-line text-base"></i>
                    </div>
                </div>
                <div id="stat-domain" class="text-sm sm:text-base font-bold text-white mt-1.5 truncate" title="">-</div>
                <div id="stat-ip" class="text-[11px] text-cyan-400 font-mono truncate mt-0.5">IP: -</div>
                <div id="stat-up" class="text-[10px] text-slate-400 truncate mt-1"><i class="ri-time-line"></i> -</div>
            </div>

            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">RAM Usage</span>
                    <div class="w-8 h-8 rounded-lg bg-blue-500/15 border border-blue-500/25 flex items-center justify-center text-blue-400 shrink-0">
                        <i class="ri-ram-2-line text-base"></i>
                    </div>
                </div>
                <div id="stat-ram" class="text-sm sm:text-base font-bold text-white mt-1.5">- MB</div>
                <div id="stat-ram-pct" class="text-[11px] text-blue-400 mt-0.5">ใช้งานไป 0%</div>
                <div class="w-full bg-slate-800 h-1.5 rounded-full mt-2 overflow-hidden">
                    <div id="stat-ram-bar" class="bg-gradient-to-r from-cyan-400 to-blue-500 h-full transition-all duration-500" style="width: 0%"></div>
                </div>
            </div>

            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">CPU Load</span>
                    <div class="w-8 h-8 rounded-lg bg-amber-500/15 border border-amber-500/25 flex items-center justify-center text-amber-400 shrink-0">
                        <i class="ri-cpu-line text-base"></i>
                    </div>
                </div>
                <div id="stat-cpu" class="text-lg sm:text-xl font-bold text-amber-400 mt-1">0.00</div>
                <div class="text-[11px] text-slate-400 mt-1">Debian / Ubuntu VPS</div>
            </div>

            <div class="glass-card p-4 rounded-2xl relative overflow-hidden">
                <div class="flex items-start justify-between gap-2">
                    <span class="text-[11px] font-medium text-slate-400">กำลังออนไลน์</span>
                    <div class="w-8 h-8 rounded-lg bg-emerald-500/15 border border-emerald-500/25 flex items-center justify-center text-emerald-400 shrink-0">
                        <i class="ri-user-voice-line text-base"></i>
                    </div>
                </div>
                <div id="stat-online" class="text-lg sm:text-xl font-bold text-emerald-400 mt-1">0 เครื่อง</div>
                <div class="text-[11px] text-slate-400 mt-1">SSH / WS / UDP Custom</div>
            </div>
        </div>

        <div class="glass-card p-4 sm:p-5 rounded-2xl">
            <div class="flex items-center justify-between mb-3">
                <div class="flex items-center gap-2">
                    <i class="ri-pulse-line text-cyan-400 text-lg"></i>
                    <h2 class="text-xs sm:text-sm font-semibold text-slate-200">สถานะการทำงานของโปรโตคอล (Services Status)</h2>
                </div>
                <span class="text-[11px] text-slate-400">อัปเดตเรียลไทม์</span>
            </div>
            <div id="svc-grid" class="grid grid-cols-2 sm:grid-cols-5 gap-2 text-xs"></div>
        </div>

        <div class="glass-card p-1.5 rounded-2xl grid grid-cols-3 gap-1.5">
            <button onclick="switchTab('ssh')" id="tab-btn-ssh" class="flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-semibold text-xs sm:text-sm bg-gradient-to-r from-cyan-400 to-blue-500 text-slate-950 shadow-md transition">
                <i class="ri-shield-user-line text-base"></i>
                <span class="truncate">All-in-One</span>
            </button>
            <button onclick="switchTab('xray')" id="tab-btn-xray" class="flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-medium text-xs sm:text-sm text-slate-300 hover:bg-slate-800/60 transition">
                <i class="ri-radar-line text-base"></i>
                <span class="truncate">Xray Core</span>
            </button>
            <button onclick="switchTab('speed')" id="tab-btn-speed" class="flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-medium text-xs sm:text-sm text-slate-300 hover:bg-slate-800/60 transition">
                <i class="ri-speed-up-line text-base"></i>
                <span class="truncate">Speedtest</span>
            </button>
        </div>

        <div id="tab-ssh" class="space-y-5">
            <div class="glass-card p-5 rounded-2xl">
                <div class="flex items-center gap-2 mb-4">
                    <div class="w-7 h-7 rounded-lg bg-emerald-500/20 text-emerald-400 flex items-center justify-center">
                        <i class="ri-user-add-line"></i>
                    </div>
                    <div>
                        <h3 class="text-sm font-bold text-white">สร้างบัญชี All-in-One ใหม่</h3>
                        <p class="text-[11px] text-slate-400">ใช้ได้พร้อมกันทั้ง SSH-WS, UDP Custom (1-65535), ZIVPN และ Hysteria 2</p>
                    </div>
                </div>
                <form onsubmit="addSshUser(event)" class="grid grid-cols-1 sm:grid-cols-4 gap-3">
                    <div class="relative">
                        <i class="ri-user-3-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="text" id="ssh-user" required placeholder="ชื่อผู้ใช้ (Username)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <div class="relative flex">
                        <i class="ri-lock-password-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="text" id="ssh-pass" required placeholder="รหัสผ่าน (Password)" class="w-full pl-10 pr-9 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                        <button type="button" onclick="randPass()" title="สุ่มรหัสผ่าน" class="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-cyan-400">
                            <i class="ri-dice-line text-lg"></i>
                        </button>
                    </div>
                    <div class="relative">
                        <i class="ri-calendar-check-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="number" id="ssh-days" value="30" required placeholder="จำนวนวัน (เช่น 30)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <button type="submit" class="bg-gradient-to-r from-emerald-400 to-teal-500 hover:from-emerald-300 hover:to-teal-400 text-slate-950 font-bold py-2.5 px-4 rounded-xl text-xs sm:text-sm shadow-lg shadow-emerald-500/15 transition flex items-center justify-center gap-1.5">
                        <i class="ri-add-circle-fill text-base"></i> สร้างบัญชีทันที
                    </button>
                </form>
            </div>

            <div class="glass-card rounded-2xl overflow-hidden">
                <div class="p-4 border-b border-white/10 flex justify-between items-center">
                    <div class="flex items-center gap-2">
                        <i class="ri-group-line text-cyan-400"></i>
                        <h3 class="font-bold text-xs sm:text-sm text-white">รายชื่อบัญชี All-in-One ทั้งหมด</h3>
                        <span id="ssh-count" class="text-[11px] bg-slate-800 text-cyan-300 px-2 py-0.5 rounded-full">0</span>
                    </div>
                    <button onclick="loadSshUsers()" class="text-xs text-cyan-400 hover:text-cyan-300 flex items-center gap-1">
                        <i class="ri-refresh-line"></i> รีเฟรช
                    </button>
                </div>
                <div class="overflow-x-auto">
                    <table class="w-full text-left text-xs sm:text-sm">
                        <thead class="bg-slate-950/60 text-slate-400 text-[11px] uppercase">
                            <tr>
                                <th class="py-3 px-4">บัญชีผู้ใช้</th>
                                <th class="py-3 px-4">รหัสผ่าน (แตะเพื่อแก้)</th>
                                <th class="py-3 px-4">หมดอายุ</th>
                                <th class="py-3 px-4">ออนไลน์</th>
                                <th class="py-3 px-4">สถานะ</th>
                                <th class="py-3 px-4 text-right">จัดการ / คัดลอก</th>
                            </tr>
                        </thead>
                        <tbody id="ssh-tbody" class="divide-y divide-white/5"></tbody>
                    </table>
                </div>
            </div>
        </div>

        <div id="tab-xray" class="hidden space-y-5">
            <div class="glass-card p-5 rounded-2xl">
                <div class="flex items-center gap-2 mb-4">
                    <div class="w-7 h-7 rounded-lg bg-cyan-500/20 text-cyan-400 flex items-center justify-center">
                        <i class="ri-radar-fill"></i>
                    </div>
                    <div>
                        <h3 class="text-sm font-bold text-white">สร้างบัญชี Xray Core (Vmess & Vless)</h3>
                        <p class="text-[11px] text-slate-400">รองรับทั้งพอร์ต 443 (SSL/TLS) และพอร์ต 80 (HTTP WebSocket)</p>
                    </div>
                </div>
                <form onsubmit="addXrayUser(event)" class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div class="relative">
                        <i class="ri-user-star-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="text" id="xray-user" required placeholder="ชื่อบัญชี Xray (ห้ามซ้ำ)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <div class="relative">
                        <i class="ri-calendar-check-line absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400"></i>
                        <input type="number" id="xray-days" value="30" required placeholder="จำนวนวัน (เช่น 30)" class="w-full pl-10 pr-3 py-2.5 rounded-xl bg-slate-950/90 border border-slate-700/80 text-xs sm:text-sm focus:outline-none focus:border-cyan-400">
                    </div>
                    <button type="submit" class="bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-bold py-2.5 px-4 rounded-xl text-xs sm:text-sm shadow-lg shadow-cyan-500/15 transition flex items-center justify-center gap-1.5">
                        <i class="ri-add-circle-fill text-base"></i> สร้างบัญชี Xray
                    </button>
                </form>
            </div>

            <div class="glass-card rounded-2xl overflow-hidden">
                <div class="p-4 border-b border-white/10 flex justify-between items-center">
                    <div class="flex items-center gap-2">
                        <i class="ri-links-line text-cyan-400"></i>
                        <h3 class="font-bold text-xs sm:text-sm text-white">รายชื่อบัญชี Xray ทั้งหมด</h3>
                    </div>
                    <button onclick="loadXrayUsers()" class="text-xs text-cyan-400 hover:text-cyan-300 flex items-center gap-1">
                        <i class="ri-refresh-line"></i> รีเฟรช
                    </button>
                </div>
                <div class="overflow-x-auto">
                    <table class="w-full text-left text-xs sm:text-sm">
                        <thead class="bg-slate-950/60 text-slate-400 text-[11px] uppercase">
                            <tr>
                                <th class="py-3 px-4">ชื่อบัญชี</th>
                                <th class="py-3 px-4">วันหมดอายุ</th>
                                <th class="py-3 px-4">คัดลอกลิงก์ด่วน</th>
                                <th class="py-3 px-4 text-right">จัดการ</th>
                            </tr>
                        </thead>
                        <tbody id="xray-tbody" class="divide-y divide-white/5"></tbody>
                    </table>
                </div>
            </div>
        </div>

        <div id="tab-speed" class="hidden space-y-4">
            <div class="glass-card p-5 rounded-2xl">
                <div class="flex flex-wrap justify-between items-center gap-3 mb-4">
                    <div class="flex items-center gap-2.5">
                        <div class="w-9 h-9 rounded-xl bg-cyan-500/15 text-cyan-400 flex items-center justify-center">
                            <i class="ri-speed-up-fill text-xl"></i>
                        </div>
                        <div>
                            <h3 class="text-sm font-bold text-white">Speedtest by Ookla (Official CLI)</h3>
                            <p class="text-[11px] text-slate-400">วัดความเร็ว Download / Upload / Ping จากสายสัญญาณ VPS โดยตรง</p>
                        </div>
                    </div>
                    <button onclick="startSpeedtest()" id="btn-speedtest" class="bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-bold px-4 py-2.5 rounded-xl text-xs sm:text-sm shadow-lg shadow-cyan-500/15 transition flex items-center gap-1.5">
                        <i class="ri-play-circle-fill text-base"></i> เริ่มวัดความเร็ว
                    </button>
                </div>
                <pre id="speedtest-box" class="bg-slate-950/90 border border-slate-800 p-4 rounded-xl text-xs text-emerald-400 font-mono overflow-x-auto leading-relaxed min-h-[180px]">กดปุ่ม "เริ่มวัดความเร็ว" เพื่อเริ่มทดสอบ...</pre>
            </div>
        </div>
    </main>

    <div id="info-modal" class="hidden fixed inset-0 z-50 bg-black/75 backdrop-blur-sm flex items-center justify-center p-4">
        <div class="glass-card border border-white/15 rounded-3xl max-w-lg w-full p-5 space-y-4 shadow-2xl">
            <div class="flex items-center justify-between border-b border-white/10 pb-3">
                <div class="flex items-center gap-2">
                    <i class="ri-file-list-3-fill text-cyan-400 text-lg"></i>
                    <h3 id="modal-title" class="font-bold text-sm text-white">ข้อมูลบัญชีพร้อมใช้งาน</h3>
                </div>
                <button onclick="closeModal()" class="text-slate-400 hover:text-white"><i class="ri-close-line text-xl"></i></button>
            </div>
            <textarea id="modal-text" readonly rows="11" class="w-full bg-slate-950/90 border border-slate-800 rounded-xl p-3.5 text-xs text-cyan-200 font-mono focus:outline-none"></textarea>
            <div class="flex gap-2">
                <button onclick="copyModalText()" class="flex-1 bg-gradient-to-r from-cyan-400 to-blue-500 text-slate-950 font-bold py-2.5 rounded-xl text-xs sm:text-sm flex items-center justify-center gap-1.5">
                    <i class="ri-file-copy-2-line"></i> คัดลอกข้อมูลทั้งหมด
                </button>
                <button onclick="closeModal()" class="px-4 py-2.5 rounded-xl bg-slate-800 text-slate-300 text-xs sm:text-sm">ปิด</button>
            </div>
        </div>
    </div>

    <script>
        let currentDomain = location.hostname;
        let currentIp = location.hostname;

        function showToast(msg) {
            const t = document.getElementById('toast');
            document.getElementById('toast-msg').textContent = msg;
            t.classList.remove('hidden');
            setTimeout(() => t.classList.add('hidden'), 3200);
        }

        function randPass() {
            const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
            let out = '';
            for (let i = 0; i < 6; i++) out += chars.charAt(Math.floor(Math.random() * chars.length));
            document.getElementById('ssh-pass').value = out;
        }

        function switchTab(tab) {
            ['ssh', 'xray', 'speed'].forEach(t => {
                document.getElementById('tab-' + t).classList.add('hidden');
                document.getElementById('tab-btn-' + t).className = 'flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-medium text-xs sm:text-sm text-slate-300 hover:bg-slate-800/60 transition';
            });
            document.getElementById('tab-' + tab).classList.remove('hidden');
            document.getElementById('tab-btn-' + tab).className = 'flex items-center justify-center gap-1.5 py-2.5 px-2 rounded-xl font-semibold text-xs sm:text-sm bg-gradient-to-r from-cyan-400 to-blue-500 text-slate-950 shadow-md transition';
            if (tab === 'xray') loadXrayUsers();
            if (tab === 'speed') pollSpeedtest();
        }

        async function loadStats() {
            try {
                const res = await fetch('?ajax=stats');
                const d = await res.json();
                currentDomain = d.domain;
                currentIp = d.ip;

                document.getElementById('nav-domain').textContent = `${d.domain} (${d.ip})`;
                document.getElementById('stat-domain').textContent = d.domain;
                document.getElementById('stat-domain').title = d.domain;
                document.getElementById('stat-ip').textContent = `IP: ${d.ip}`;
                document.getElementById('stat-up').innerHTML = `<i class="ri-time-line"></i> ${d.uptime}`;

                const pct = Math.round((d.ram_used / d.ram_total) * 100);
                document.getElementById('stat-ram').textContent = `${d.ram_used} / ${d.ram_total} MB`;
                document.getElementById('stat-ram-pct').textContent = `ใช้งานไป ${pct}%`;
                document.getElementById('stat-ram-bar').style.width = pct + '%';
                document.getElementById('stat-cpu').textContent = d.cpu;
                document.getElementById('stat-online').textContent = d.ssh_online + ' เครื่อง';

                const labels = {
                    'ssh': 'OpenSSH (22)',
                    'dropbear': 'Dropbear (109/143)',
                    'nginx': 'Nginx (80/443)',
                    'xray': 'Xray Core',
                    'udp-custom': 'UDP Custom (7200)',
                    'udpgw@7300': 'BadVPN (7300)',
                    'zivpn': 'ZIVPN (5667)',
                    'hysteria': 'Hysteria 2 (8443)',
                    'ws-epro': 'SSH-WS (10015)',
                    'fail2ban': 'Fail2Ban'
                };
                let html = '';
                for (const [k, v] of Object.entries(d.services)) {
                    const isOn = v === 'ON';
                    const lbl = labels[k] ?? k;
                    html += `
                        <div class="bg-slate-950/70 border border-white/5 px-3 py-2.5 rounded-xl flex items-center justify-between gap-2">
                            <span class="text-slate-300 truncate text-[11px] sm:text-xs">${lbl}</span>
                            <span class="flex items-center gap-1.5 text-[10px] font-bold px-2 py-0.5 rounded-full ${isOn ? 'bg-emerald-500/15 text-emerald-400' : 'bg-rose-500/15 text-rose-400'}">
                                <span class="w-1.5 h-1.5 rounded-full ${isOn ? 'bg-emerald-400 glow-dot-on' : 'bg-rose-400 glow-dot-off'}"></span>
                                ${v}
                            </span>
                        </div>`;
                }
                document.getElementById('svc-grid').innerHTML = html;
            } catch (e) {}
        }

        function showSshModal(user, pass, exp) {
            const hysHop = `hysteria2://${encodeURIComponent(pass)}@${currentDomain}:20000/?insecure=1&sni=${currentDomain}&mport=20000-50000#${user}-Hys2`;
            const text = `=== ข้อมูลบัญชี VPN All-in-One ===
Host / Domain : ${currentDomain}
IP Address    : ${currentIp}
Username      : ${user}
Password      : ${pass}
หมดอายุวันที่    : ${exp}
---------------------------------
• SSH / WS Port : 22, 80, 443
• Dropbear Port : 109, 143
• UDP Custom    : 1-5999, 50001-65535
• BadVPN UDPGW  : 7300
• ZIVPN UDP     : 5667, 6000-19999 (รหัส: ${pass})
• Hysteria 2    : 8443, 20000-50000
---------------------------------
[Payload SSH-WS มาตรฐาน]
GET /ssh-ws HTTP/1.1[crlf]Host: ${currentDomain}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]

[ลิงก์ Hysteria 2 Port Hopping]
${hysHop}`;
            document.getElementById('modal-title').textContent = `ข้อมูลบัญชี: ${user}`;
            document.getElementById('modal-text').value = text;
            document.getElementById('info-modal').classList.remove('hidden');
        }

        function closeModal() {
            document.getElementById('info-modal').classList.add('hidden');
        }

        function copyModalText() {
            const el = document.getElementById('modal-text');
            navigator.clipboard.writeText(el.value);
            showToast('คัดลอกข้อมูลบัญชีเรียบร้อยแล้ว!');
        }

        async function loadSshUsers() {
            const res = await fetch('?ajax=list_ssh');
            const list = await res.json();
            document.getElementById('ssh-count').textContent = list.length;
            const tbody = document.getElementById('ssh-tbody');
            if (!list.length) {
                tbody.innerHTML = '<tr><td colspan="6" class="text-center py-8 text-slate-400">ยังไม่มีบัญชีในระบบ กดสร้างบัญชีด้านบนได้เลย</td></tr>';
                return;
            }
            tbody.innerHTML = list.map(u => `
                <tr class="hover:bg-white/[0.02] transition">
                    <td class="py-3 px-4 font-semibold text-white">${u.user}</td>
                    <td class="py-3 px-4">
                        <button onclick="setPass('${u.user}','${u.pass}')" class="text-cyan-300 hover:text-white font-mono underline decoration-dotted underline-offset-4 flex items-center gap-1" title="กดเพื่อตั้ง/บันทึกรหัสผ่าน">
                            <span>${u.pass}</span>
                            <i class="ri-edit-2-line text-xs text-slate-400"></i>
                        </button>
                    </td>
                    <td class="py-3 px-4 text-slate-300 whitespace-nowrap">${u.exp}</td>
                    <td class="py-3 px-4 whitespace-nowrap">
                        <span class="px-2.5 py-0.5 rounded-full text-[11px] ${u.online > 0 ? 'bg-emerald-500/20 text-emerald-300 font-bold border border-emerald-500/30' : 'bg-slate-800 text-slate-400'}">
                            ${u.online} เครื่อง
                        </span>
                    </td>
                    <td class="py-3 px-4">
                        <span class="px-2 py-0.5 rounded-md text-[11px] ${u.status === 'Active' ? 'bg-emerald-500/15 text-emerald-400' : 'bg-rose-500/15 text-rose-400'}">
                            ${u.status}
                        </span>
                    </td>
                    <td class="py-3 px-4 text-right whitespace-nowrap space-x-1">
                        <button onclick="showSshModal('${u.user}','${u.pass}','${u.exp}')" class="bg-cyan-500/15 hover:bg-cyan-500/25 text-cyan-300 border border-cyan-500/30 px-2.5 py-1 rounded-lg text-xs" title="ดูข้อมูล/คัดลอก">
                            <i class="ri-file-copy-2-line"></i> ข้อมูล
                        </button>
                        <button onclick="renewSsh('${u.user}')" class="bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-300 border border-emerald-500/30 px-2 py-1 rounded-lg text-xs" title="ต่ออายุ">
                            <i class="ri-calendar-todo-line"></i> ต่ออายุ
                        </button>
                        <button onclick="toggleSsh('${u.user}')" class="bg-amber-500/15 hover:bg-amber-500/25 text-amber-300 border border-amber-500/30 px-2 py-1 rounded-lg text-xs">
                            ${u.status === 'Active' ? '<i class="ri-lock-line"></i>' : '<i class="ri-lock-unlock-line"></i>'}
                        </button>
                        <button onclick="delSsh('${u.user}')" class="bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 border border-rose-500/30 px-2 py-1 rounded-lg text-xs" title="ลบ">
                            <i class="ri-delete-bin-line"></i>
                        </button>
                    </td>
                </tr>
            `).join('');
        }

        async function addSshUser(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('user', document.getElementById('ssh-user').value);
            fd.append('pass', document.getElementById('ssh-pass').value);
            fd.append('days', document.getElementById('ssh-days').value);
            const res = await fetch('?ajax=add_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            if (r.success) {
                document.getElementById('ssh-user').value = '';
                document.getElementById('ssh-pass').value = '';
                loadSshUsers();
                showSshModal(r.user, r.pass, r.exp);
            }
        }

        async function setPass(user, oldPass) {
            const def = oldPass === '-' ? '' : oldPass;
            const pass = prompt(`กำหนดหรือบันทึกรหัสผ่านสำหรับบัญชี "${user}"\n(ซิงค์เข้า SSH, UDP Custom, ZIVPN และ Hysteria 2 ทันที):`, def);
            if (!pass) return;
            const fd = new FormData();
            fd.append('user', user);
            fd.append('pass', pass);
            const res = await fetch('?ajax=set_pass', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function renewSsh(user) {
            const days = prompt(`ต้องการต่ออายุบัญชี "${user}" เพิ่มกี่วัน?`, '30');
            if (!days) return;
            const fd = new FormData();
            fd.append('user', user);
            fd.append('days', days);
            const res = await fetch('?ajax=renew_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function delSsh(user) {
            if (!confirm(`ยืนยันการลบบัญชี "${user}" ออกจากทุกโปรโตคอล?`)) return;
            const fd = new FormData();
            fd.append('user', user);
            const res = await fetch('?ajax=del_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function toggleSsh(user) {
            const fd = new FormData();
            fd.append('user', user);
            const res = await fetch('?ajax=toggle_ssh', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadSshUsers();
        }

        async function loadXrayUsers() {
            const res = await fetch('?ajax=list_xray');
            const list = await res.json();
            const tbody = document.getElementById('xray-tbody');
            if (!list.length) {
                tbody.innerHTML = '<tr><td colspan="4" class="text-center py-8 text-slate-400">ยังไม่มีบัญชี Xray ในระบบ</td></tr>';
                return;
            }
            tbody.innerHTML = list.map(u => `
                <tr class="hover:bg-white/[0.02] transition">
                    <td class="py-3 px-4 font-semibold text-white">
                        <div>${u.user}</div>
                        <div class="text-[10px] text-slate-500 font-mono truncate max-w-[140px]">${u.uuid}</div>
                    </td>
                    <td class="py-3 px-4 text-slate-300 whitespace-nowrap">${u.exp}</td>
                    <td class="py-3 px-4 whitespace-nowrap space-x-1">
                        <button onclick="copyLink('${u.vmess_tls}', 'Vmess TLS (443)')" class="text-xs bg-cyan-500/15 hover:bg-cyan-500/25 text-cyan-300 border border-cyan-500/30 px-2.5 py-1 rounded-lg">Vmess TLS</button>
                        <button onclick="copyLink('${u.vmess_http}', 'Vmess HTTP (80)')" class="text-xs bg-indigo-500/15 hover:bg-indigo-500/25 text-indigo-300 border border-indigo-500/30 px-2.5 py-1 rounded-lg">Vmess 80</button>
                        <button onclick="copyLink('${u.vless_tls}', 'Vless TLS (443)')" class="text-xs bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-300 border border-emerald-500/30 px-2.5 py-1 rounded-lg">Vless TLS</button>
                    </td>
                    <td class="py-3 px-4 text-right whitespace-nowrap space-x-1">
                        <button onclick="renewXray('${u.user}')" class="bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-300 border border-emerald-500/30 px-2 py-1 rounded-lg text-xs">
                            <i class="ri-calendar-todo-line"></i> ต่ออายุ
                        </button>
                        <button onclick="delXray('${u.user}')" class="bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 border border-rose-500/30 px-2 py-1 rounded-lg text-xs">
                            <i class="ri-delete-bin-line"></i>
                        </button>
                    </td>
                </tr>
            `).join('');
        }

        async function addXrayUser(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('user', document.getElementById('xray-user').value);
            fd.append('days', document.getElementById('xray-days').value);
            const res = await fetch('?ajax=add_xray', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            if (r.success) {
                document.getElementById('xray-user').value = '';
                loadXrayUsers();
            }
        }

        async function renewXray(user) {
            const days = prompt(`ต้องการต่ออายุบัญชี Xray "${user}" เพิ่มกี่วัน?`, '30');
            if (!days) return;
            const fd = new FormData();
            fd.append('user', user);
            fd.append('days', days);
            const res = await fetch('?ajax=renew_xray', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadXrayUsers();
        }

        async function delXray(user) {
            if (!confirm(`ยืนยันการลบบัญชี Xray "${user}" ?`)) return;
            const fd = new FormData();
            fd.append('user', user);
            const res = await fetch('?ajax=del_xray', { method: 'POST', body: fd });
            const r = await res.json();
            showToast(r.msg);
            loadXrayUsers();
        }

        function copyLink(text, label) {
            navigator.clipboard.writeText(text);
            showToast('คัดลอกลิงก์ ' + label + ' แล้ว!');
        }

        async function clearRam() {
            const res = await fetch('?ajax=clear_ram');
            const r = await res.json();
            showToast(r.msg);
            loadStats();
        }

        async function restartAll() {
            if (!confirm('ต้องการรีสตาร์ทบริการทั้งหมดใช่หรือไม่?')) return;
            const res = await fetch('?ajax=restart_all');
            const r = await res.json();
            showToast(r.msg);
            setTimeout(loadStats, 3500);
        }

        let speedTimer = null;
        async function startSpeedtest() {
            const res = await fetch('?ajax=run_speedtest');
            const r = await res.json();
            showToast(r.msg);
            pollSpeedtest();
        }

        async function pollSpeedtest() {
            const res = await fetch('?ajax=get_speedtest');
            const r = await res.json();
            document.getElementById('speedtest-box').textContent = r.output;
            const btn = document.getElementById('btn-speedtest');
            if (r.running) {
                btn.innerHTML = '<i class="ri-loader-4-line animate-spin text-base"></i> กำลังวัดความเร็ว...';
                btn.disabled = true;
                clearTimeout(speedTimer);
                speedTimer = setTimeout(pollSpeedtest, 2000);
            } else {
                btn.innerHTML = '<i class="ri-play-circle-fill text-base"></i> เริ่มวัดความเร็ว';
                btn.disabled = false;
            }
        }

        loadStats();
        loadSshUsers();
        setInterval(loadStats, 10000);
    </script>
<?php endif; ?>
</body>
</html>
EOF

chown -R www-data:www-data /home/vps/public_html
chmod -R 755 /home/vps/public_html

# ค้นหาและเปิดใช้งาน PHP-FPM ทุกเวอร์ชันอย่างแม่นยำ
for php_svc in $(systemctl list-unit-files --type=service | grep -oE 'php[0-9.]+-fpm\.service'); do
    systemctl enable "$php_svc" >/dev/null 2>&1
    systemctl restart "$php_svc" >/dev/null 2>&1
done
PHP_SOCK=$(find /run/php/ -name "php*-fpm.sock" | head -n 1)

cat <<EOF > /etc/nginx/conf.d/api.conf
server {
    listen 8081;
    listen [::]:8081;
    server_name _;
    root /home/vps/public_html;
    index index.php index.html;

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }
}
EOF

if ! iptables -C INPUT -p tcp --dport 8081 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport 8081 -j ACCEPT
fi
netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1
systemctl restart nginx

# 12. ตั้งค่าระบบล้าง Log / เคลียร์ RAM และตัดบัญชีหมดอายุอัตโนมัติ (Cron Job)
cat << 'EOF' > /usr/bin/clear-log
#!/bin/bash
sync; echo 3 > /proc/sys/vm/drop_caches
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete
truncate -s 0 /var/log/syslog 2>/dev/null
truncate -s 0 /var/log/auth.log 2>/dev/null
EOF
chmod +x /usr/bin/clear-log

cat << 'EOF' > /usr/bin/auto-check
#!/bin/bash
NOW=$(date +"%Y-%m-%d")
for u in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    exp_raw=$(chage -l "$u" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
    if [ "$exp_raw" != "never" ] && [ -n "$exp_raw" ]; then
        exp=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
        if [[ -n "$exp" && "$exp" < "$NOW" ]]; then
            passwd -l "$u" >/dev/null 2>&1
            killall -u "$u" >/dev/null 2>&1
        fi
    fi
done

if [ -f /etc/xray/xray-exp.txt ]; then
    while IFS=':' read -r u exp; do
        [ -z "$u" ] && continue
        if [[ "$exp" < "$NOW" ]]; then
            /usr/bin/panel-cmd del_xray "$u" >/dev/null 2>&1
        fi
    done < /etc/xray/xray-exp.txt
fi
EOF
chmod +x /usr/bin/auto-check

(crontab -l 2>/dev/null | grep -v "auto-check"; echo "0 0 * * * /usr/bin/auto-check") | crontab -
(crontab -l 2>/dev/null | grep -v "clear-log"; echo "0 3 * * * /usr/bin/clear-log") | crontab -

# 13. สร้างคำสั่งเช็กสถานะ (/usr/bin/running) และเมนูจัดการ (/usr/bin/menu)
cat << 'EOF' > /usr/bin/running
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MYIP=$(curl -sS --max-time 3 ipv4.icanhazip.com || hostname -I | awk '{print $1}')
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")

check_svc() {
    if systemctl is-active --quiet "$1"; then
        echo -e "${GREEN}RUNNING (ทำงานปกติ)${NC}"
    else
        echo -e "${RED}STOPPED (หยุดทำงาน)${NC}"
    fi
}

clear
echo -e "${YELLOW}==========================================================${NC}"
echo -e "           ${CYAN}STATUS SERVICES • TOEYVPN V2${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e " IP Address         : ${GREEN}${MYIP}${NC}"
echo -e " Domain             : ${GREEN}${DOMAIN}${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e " OpenSSH (22)       : $(check_svc ssh)"
echo -e " Dropbear (109/143) : $(check_svc dropbear)"
echo -e " SSH-WS (10015)     : $(check_svc ws-epro)"
echo -e " Nginx (80/443/8081): $(check_svc nginx)"
echo -e " Xray Core          : $(check_svc xray)"
echo -e " UDP Custom (7200)  : $(check_svc udp-custom)"
echo -e " BadVPN (7100/7300) : $(check_svc udpgw@7300)"
echo -e " ZIVPN UDP (5667)   : $(check_svc zivpn)"
echo -e " Hysteria 2 (8443)  : $(check_svc hysteria)"
echo -e " Fail2Ban           : $(check_svc fail2ban)"
echo -e "${YELLOW}==========================================================${NC}"
EOF
chmod +x /usr/bin/running

cat << 'EOF' > /usr/bin/menu
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

MYIP=$(curl -sS --max-time 3 ipv4.icanhazip.com || hostname -I | awk '{print $1}')
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "$MYIP")
CUR_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php 2>/dev/null | cut -d'"' -f2 || echo "VNEXT_SSH_999")

clear
echo -e "${YELLOW}==========================================================${NC}"
echo -e "        ${CYAN}TOEYVPN V2 • ALL-IN-ONE MANAGEMENT MENU${NC}"
echo -e "${YELLOW}==========================================================${NC}"
echo -e " IP Address : ${GREEN}${MYIP}${NC} | Domain : ${GREEN}${DOMAIN}${NC}"
echo -e " Web Panel  : ${CYAN}http://${MYIP}:8081${NC} (รหัสผ่าน: ${YELLOW}${CUR_KEY}${NC})"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e " ${GREEN}[1]${NC} สร้างบัญชี All-in-One (SSH/UDP/ZIVPN/Hysteria2)"
echo -e " ${GREEN}[2]${NC} ต่ออายุบัญชี All-in-One"
echo -e " ${GREEN}[3]${NC} ลบบัญชี All-in-One"
echo -e " ${GREEN}[4]${NC} ดูรายชื่อบัญชี All-in-One ทั้งหมด"
echo -e " ${GREEN}[5]${NC} สร้างบัญชี Xray (Vmess / Vless)"
echo -e " ${GREEN}[6]${NC} ลบบัญชี Xray"
echo -e " ${GREEN}[7]${NC} เช็กสถานะบริการทั้งหมด (running)"
echo -e " ${GREEN}[8]${NC} รีสตาร์ทบริการทั้งหมด"
echo -e " ${GREEN}[9]${NC} เปลี่ยนชื่อโดเมนและขอ SSL ใหม่"
echo -e " ${GREEN}[28]${NC} เปลี่ยนรหัส Secret Key (สำหรับเชื่อมเว็บ & เข้าพอร์ต 8081)"
echo -e " ${RED}[0]${NC} ออกจากเมนู"
echo -e "${YELLOW}==========================================================${NC}"
read -rp "เลือกเมนูที่ต้องการ : " opt

case "$opt" in
    1)
        read -rp "ชื่อผู้ใช้ (Username): " u
        read -rp "รหัสผ่าน (Password): " p
        read -rp "จำนวนวันใช้งาน (เช่น 30): " d
        /usr/bin/panel-cmd add_ssh "$u" "$p" "$d" | jq -r '.msg'
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    2)
        read -rp "ชื่อผู้ใช้ที่ต้องการต่ออายุ: " u
        read -rp "จำนวนวันที่ต้องการเพิ่ม: " d
        /usr/bin/panel-cmd renew_ssh "$u" "$d" | jq -r '.msg'
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    3)
        read -rp "ชื่อผู้ใช้ที่ต้องการลบ: " u
        /usr/bin/panel-cmd del_ssh "$u" | jq -r '.msg'
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    4)
        /usr/bin/panel-cmd list_ssh | jq -r '.[] | "User: \(.user) | Pass: \(.pass) | Exp: \(.exp) | Online: \(.online) | Status: \(.status)"'
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    5)
        read -rp "ชื่อบัญชี Xray: " u
        read -rp "จำนวนวันใช้งาน (เช่น 30): " d
        /usr/bin/panel-cmd add_xray "$u" "$d" | jq -r '.msg'
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    6)
        read -rp "ชื่อบัญชี Xray ที่ต้องการลบ: " u
        /usr/bin/panel-cmd del_xray "$u" | jq -r '.msg'
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    7)
        /usr/bin/running
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    8)
        /usr/bin/panel-cmd restart_all | jq -r '.msg'
        sleep 3
        menu
        ;;
    9)
        wget -q -O /root/slhost.sh "https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main/ssh/slhost.sh"
        chmod +x /root/slhost.sh && /root/slhost.sh
        read -n 1 -s -r -p "กดปุ่มใดก็ได้เพื่อกลับสู่เมนู..."
        menu
        ;;
    28)
        echo -e "Secret Key ปัจจุบันคือ: ${GREEN}${CUR_KEY}${NC}"
        read -rp "กรอก Secret Key ใหม่ที่ต้องการตั้ง: " new_key
        new_key=$(echo "$new_key" | tr -d '[:space:]')
        if [ -n "$new_key" ]; then
            sed -i "s/\$secret_key = \".*\";/\$secret_key = \"${new_key}\";/g" /home/vps/public_html/api_ssh.php
            cp -f /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php
            echo -e "${GREEN}เปลี่ยน Secret Key เป็น ${new_key} เรียบร้อยแล้ว!${NC}"
        fi
        sleep 2
        menu
        ;;
    0)
        clear
        exit 0
        ;;
    *)
        menu
        ;;
esac
EOF
chmod +x /usr/bin/menu

echo "ติดตั้งระบบ SSH, UDP Custom, BadVPN, ZIVPN, Hysteria 2, Web Panel (8081) และ Menu เรียบร้อยแล้ว!"
