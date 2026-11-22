#!/bin/bash
# ==============================================================================
#  ToeyVPN v2 — ALL-IN-ONE VPN SUITE: SSH/WS, UDP CUSTOM, BADVPN, ZIVPN, HYSTERIA 2, WEB PANEL
#  Support: Ubuntu 20.04 / 22.04 / 24.04 LTS & Debian 10 / 11 / 12
# ==============================================================================
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 0. รอให้ระบบอัปเดตอัตโนมัติหลังเปิดเครื่องใหม่ (apt/dpkg lock) ทำงานเสร็จก่อนเริ่มติดตั้ง
while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    echo "⏳ ระบบกำลังอัปเดตแพ็กเกจพื้นหลังของ VPS... กรุณารอสักครู่ (รอปลดล็อก dpkg)"
    sleep 3
done
dpkg --configure -a >/dev/null 2>&1

# 1. ลบ Apache2 และ UFW ป้องกันการแย่งพอร์ต 80
systemctl stop apache2 >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
apt-get purge -y ufw firewalld exim4 apache2 apache2-utils apache2-bin apache2-data >/dev/null 2>&1
apt-get autoremove -y >/dev/null 2>&1

# 2. ตั้งค่า Timezone เป็นเวลาไทย และเปิด IPv4 Forwarding
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
if ! grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -p >/dev/null 2>&1

# 3. ติดตั้งแพ็กเกจหลัก + PHP-FPM + Fail2Ban + Iptables-Persistent + Zip/Unzip + Rsyslog
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt-get update -y
apt-get install -y nginx dropbear stunnel4 libnginx-mod-stream vnstat curl wget jq python3 net-tools openssl socat cron fail2ban iptables iptables-persistent psmisc dos2unix php-fpm php-cli php-curl zip unzip rsyslog tar util-linux

# ติดตั้ง Speedtest by Ookla (Official CLI)
if [ ! -s /usr/local/bin/speedtest ]; then
    echo "กำลังติดตั้ง Speedtest by Ookla..."
    ARCH=$(uname -m)
    S_ARCH="x86_64"
    if [ "$ARCH" = "aarch64" ]; then S_ARCH="aarch64"; fi
    if [ "$ARCH" = "arm64" ]; then S_ARCH="aarch64"; fi
    wget -q -O /tmp/speedtest.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${S_ARCH}.tgz"
    tar -xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest 2>/dev/null
    chmod +x /usr/local/bin/speedtest
    rm -f /tmp/speedtest.tgz
fi

# เปิดใช้งาน rsyslog และเตรียมไฟล์ Log สำหรับ Ubuntu 24.04 และ Debian 12
touch /var/log/auth.log /var/log/syslog
systemctl enable rsyslog >/dev/null 2>&1
systemctl restart rsyslog

# ปลดล็อก OpenSSH 9.2+ บน Debian 12 / Ubuntu 24.04 ให้รองรับแอปมือถือ (ssh-rsa & PasswordAuth)
mkdir -p /etc/ssh/sshd_config.d
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null
cat <<EOF > /etc/ssh/sshd_config.d/99-vpn-compat.conf
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAcceptedKeyTypes +ssh-rsa,ssh-dss
HostKeyAlgorithms +ssh-rsa,ssh-dss
KexAlgorithms +diffie-hellman-group1-sha1,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1
EOF
systemctl restart ssh

# ลบหน้าเริ่มต้นของ Nginx (แก้ปัญหา HTTP 200 OK Welcome to nginx บน Debian 12)
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
systemctl restart fail2ban

# 5. ตั้งค่า Iptables บล็อก BitTorrent / P2P
for keyword in "get_peers" "announce_peer" "find_node" "BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "torrent" "announce" "info_hash"; do
    if ! iptables -C FORWARD -m string --string "$keyword" --algo bm -j DROP 2>/dev/null; then
        iptables -A FORWARD -m string --string "$keyword" --algo bm -j DROP
    fi
    if ! iptables -C OUTPUT -m string --string "$keyword" --algo bm -j DROP 2>/dev/null; then
        iptables -A OUTPUT -m string --string "$keyword" --algo bm -j DROP
    fi
done

# 6. เตรียมโฟลเดอร์หลัก, ถามชื่อโดเมน (เฉพาะเครื่องใหม่) และสร้าง SSL เบื้องต้น
mkdir -p /etc/xray /etc/zivpn /etc/hysteria /home/vps/public_html /root/vnext_api /root/udp
touch /etc/xray/xray-exp.txt /etc/xray/xray-lock.txt /etc/xray/trial-exp.txt /etc/xray/ssh-pass.txt /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)

# ถ้ายังไม่มีไฟล์โดเมน (ติดตั้งเครื่องใหม่ครั้งแรก) ให้ถามโดเมนก่อน
if [ -z "$DOMAIN" ]; then
    clear
    echo "======================================================"
    echo "   🌐 ตั้งค่าโดเมนสำหรับเซิร์ฟเวอร์ VPN เครื่องใหม่"
    echo "======================================================"
    read -rp "กรุณากรอกชื่อโดเมนของคุณ (หรือกด Enter เพื่อใช้ IP): " INPUT_DOMAIN
    if [ -n "$INPUT_DOMAIN" ]; then
        DOMAIN="$INPUT_DOMAIN"
    else
        DOMAIN="$MYIP"
    fi
    echo "$DOMAIN" > /etc/xray/domain
    echo "$DOMAIN" > /root/domain
fi

if [ ! -s /etc/xray/xray.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key \
        -out /etc/xray/xray.crt \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=PrivateVPN/CN=${DOMAIN}" >/dev/null 2>&1
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
StandardOutput=null
StandardError=null

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

sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1

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
LimitNOFILE=1000000
StandardOutput=null
StandardError=null
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
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable udp-custom >/dev/null 2>&1
systemctl restart udp-custom

# 10. Iptables NAT configuration will be applied at final step using dedicated chain (VPN_UDP).

# 11. ติดตั้งระบบ Web API & Web Dashboard (Port 8081) รองรับทั้งรายวันและรายชั่วโมง (hours=1)
cat << 'EOF' > /usr/bin/api-vpn
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TZ="Asia/Bangkok"

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
ZTMP="/tmp/zivpn_tmp_$$.json"

mkdir -p /etc/xray /etc/zivpn /etc/hysteria
touch /etc/xray/trial-exp.txt /etc/xray/ssh-pass.txt /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

# Wait briefly if user management processes are active (max ~3s) then clear stale locks
for _w in 1 2 3 4 5 6 7 8 9 10; do
    if pgrep -x "useradd" >/dev/null 2>&1 || pgrep -x "usermod" >/dev/null 2>&1 || pgrep -x "chpasswd" >/dev/null 2>&1; then
        sleep 0.3
    else
        rm -f /etc/passwd.lock /etc/shadow.lock /etc/group.lock /etc/gshadow.lock /etc/subuid.lock /etc/subgid.lock 2>/dev/null
        break
    fi
done

if [ "$ACTION" = "add_trial" ]; then
    EXP_TS=$(echo "$EXP" | tr -cd '0-9')
    if [ -z "$EXP_TS" ]; then
        EXP_TS=$(( $(date +%s) + 3600 ))
    fi
    EXP_DATE=$(date -d "@$EXP_TS" +"%Y-%m-%d")
    SHADOW_EXP=$(date -d "$EXP_DATE + 2 days" +"%Y-%m-%d")

    for i in 1 2 3; do
        if ! id "$USER" >/dev/null 2>&1; then
            sleep 0.2
            /usr/sbin/useradd -e "$SHADOW_EXP" -s /bin/false -M "$USER" 2>/dev/null || \
            /usr/sbin/useradd -e "$SHADOW_EXP" -s /bin/false -M -N "$USER" 2>/dev/null
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
    /usr/bin/passwd -u "$USER" 2>/dev/null
    /usr/bin/chage -E "$SHADOW_EXP" "$USER" 2>/dev/null
    /usr/sbin/usermod -e "$SHADOW_EXP" "$USER" 2>/dev/null

    sed -i "/^${USER}:/d" /etc/xray/trial-exp.txt
    echo "${USER}:${EXP_TS}" >> /etc/xray/trial-exp.txt
    if [ -n "$PASS" ]; then
        sed -i "/^${USER}:/d" /etc/xray/ssh-pass.txt
        echo "${USER}:${PASS}" >> /etc/xray/ssh-pass.txt
    fi

    if [ -n "$PASS" ] && [ -f /etc/zivpn/config.json ]; then
        jq --arg p "$PASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > "$ZTMP"
        if [ -s "$ZTMP" ]; then
            mv "$ZTMP" /etc/zivpn/config.json
        else
            rm -f "$ZTMP"
        fi
        sed -i "/^${PASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${PASS}:${EXP_DATE}" >> /etc/zivpn/zivpn-exp.txt
        sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
        echo "${USER}:${PASS}" >> /etc/zivpn/zivpn-users.txt
        (systemctl restart zivpn >/dev/null 2>&1) 200>&- &
    fi

    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        sed -i "/^${USER}:/d" /etc/hysteria/hys-users.txt
        echo "${USER}:${PASS}:${EXP_DATE}" >> /etc/hysteria/hys-users.txt
        (/usr/bin/rebuild-hysteria >/dev/null 2>&1) 200>&- &
    fi

    flock -u 200
    exit 0
fi

if ! echo "$EXP" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    EXP=$(date -d "+1 days" +"%Y-%m-%d")
fi
SHADOW_EXP=$(date -d "$EXP + 1 day" +"%Y-%m-%d")

if [ "$ACTION" = "add" ]; then
    for i in 1 2 3; do
        if ! id "$USER" >/dev/null 2>&1; then
            sleep 0.2
            /usr/sbin/useradd -e "$SHADOW_EXP" -s /bin/false -M "$USER" 2>/dev/null || \
            /usr/sbin/useradd -e "$SHADOW_EXP" -s /bin/false -M -N "$USER" 2>/dev/null
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
    /usr/bin/passwd -u "$USER" 2>/dev/null
    /usr/bin/chage -E "$SHADOW_EXP" "$USER" 2>/dev/null
    /usr/sbin/usermod -e "$SHADOW_EXP" "$USER" 2>/dev/null
    sed -i "/^${USER}:/d" /etc/xray/trial-exp.txt 2>/dev/null
    if [ -n "$PASS" ]; then
        sed -i "/^${USER}:/d" /etc/xray/ssh-pass.txt
        echo "${USER}:${PASS}" >> /etc/xray/ssh-pass.txt
    fi

    if [ -n "$PASS" ] && [ -f /etc/zivpn/config.json ]; then
        jq --arg p "$PASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > "$ZTMP"
        if [ -s "$ZTMP" ]; then
            mv "$ZTMP" /etc/zivpn/config.json
        else
            rm -f "$ZTMP"
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
    sed -i "/^${USER}:/d" /etc/xray/trial-exp.txt 2>/dev/null
    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
    HPASS=$(grep "^${USER}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
    SPASS=$(grep "^${USER}:" /etc/xray/ssh-pass.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
    [ -z "$ZPASS" ] && [ -n "$HPASS" ] && ZPASS="$HPASS"
    [ -z "$ZPASS" ] && [ -n "$SPASS" ] && ZPASS="$SPASS"
    [ -n "$PASS" ] && ZPASS="$PASS"
    [ -z "$HPASS" ] && [ -n "$ZPASS" ] && HPASS="$ZPASS"
    [ -n "$PASS" ] && HPASS="$PASS"

    if ! id "$USER" >/dev/null 2>&1; then
        for i in 1 2 3; do
            if ! id "$USER" >/dev/null 2>&1; then
                /usr/sbin/useradd -e "$SHADOW_EXP" -s /bin/false -M "$USER" 2>/dev/null || \
                /usr/sbin/useradd -e "$SHADOW_EXP" -s /bin/false -M -N "$USER" 2>/dev/null
                sleep 0.3
            else
                break
            fi
        done
    fi

    if ! id "$USER" >/dev/null 2>&1; then
        flock -u 200
        exit 1
    fi

    if [ -n "$PASS" ]; then
        echo "$USER:$PASS" | /usr/sbin/chpasswd 2>/dev/null
        sed -i "/^${USER}:/d" /etc/xray/ssh-pass.txt
        echo "${USER}:${PASS}" >> /etc/xray/ssh-pass.txt
    elif [ -n "$ZPASS" ]; then
        echo "$USER:$ZPASS" | /usr/sbin/chpasswd 2>/dev/null
        sed -i "/^${USER}:/d" /etc/xray/ssh-pass.txt
        echo "${USER}:${ZPASS}" >> /etc/xray/ssh-pass.txt
    fi

    /usr/sbin/usermod -U "$USER" 2>/dev/null
    /usr/bin/passwd -u "$USER" 2>/dev/null
    /usr/bin/chage -E "$SHADOW_EXP" "$USER" 2>/dev/null
    /usr/sbin/usermod -e "$SHADOW_EXP" "$USER" 2>/dev/null

    if [ -n "$ZPASS" ]; then
        sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
        echo "${USER}:${ZPASS}" >> /etc/zivpn/zivpn-users.txt
        sed -i "/^${ZPASS}:/d" /etc/zivpn/zivpn-exp.txt
        echo "${ZPASS}:${EXP}" >> /etc/zivpn/zivpn-exp.txt
        if [ -f /etc/zivpn/config.json ]; then
            jq --arg p "$ZPASS" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > "$ZTMP"
            if [ -s "$ZTMP" ]; then
                mv "$ZTMP" /etc/zivpn/config.json
            else
                rm -f "$ZTMP"
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
    sed -i "/^${USER}:/d" /etc/xray/trial-exp.txt 2>/dev/null
    /usr/bin/killall -u "$USER" 2>/dev/null
    /usr/sbin/userdel -f "$USER" 2>/dev/null
    /usr/sbin/groupdel "$USER" 2>/dev/null

    ZPASS=$(grep "^${USER}:" /etc/zivpn/zivpn-users.txt | cut -d: -f2 | tail -n 1)
    sed -i "/^${USER}:/d" /etc/zivpn/zivpn-users.txt
    if [ -n "$ZPASS" ] && [ -f /etc/zivpn/config.json ]; then
        if ! grep -q ":${ZPASS}$" /etc/zivpn/zivpn-users.txt; then
            jq --arg p "$ZPASS" '.auth.config -= [$p]' /etc/zivpn/config.json > "$ZTMP"
            if [ -s "$ZTMP" ]; then
                mv "$ZTMP" /etc/zivpn/config.json
            else
                rm -f "$ZTMP"
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
export TZ="Asia/Bangkok"
ACTION="$1"

MYIP=$(curl -sS --max-time 2 ipv4.icanhazip.com 2>/dev/null)
if [ -z "$MYIP" ]; then
    MYIP=$(hostname -I | awk '{print $1}')
fi
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
if [ -z "$DOMAIN" ]; then
    DOMAIN="$MYIP"
fi

get_user_exp() {
    local usr="$1"
    local texp=$(grep "^${usr}:" /etc/xray/trial-exp.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
    if [ -n "$texp" ]; then
        date -d "@$texp" "+%Y-%m-%d %H:%M (Trial)" 2>/dev/null && return
    fi
    local hexp=$(grep "^${usr}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f3 | tail -n 1)
    if [ -n "$hexp" ]; then
        echo "$hexp"
        return
    fi
    local raw=$(chage -l "$usr" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
    if [ "$raw" = "never" ] || [ -z "$raw" ]; then
        echo "Never"
    else
        date -d "$raw" +%Y-%m-%d 2>/dev/null || echo "$raw"
    fi
}

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

        Services=("ssh" "dropbear" "stunnel4" "nginx" "xray" "udp-custom" "udpgw@7300" "zivpn" "hysteria" "ws-epro" "fail2ban")
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
        USERS_LIST=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | tac)
        for u in $USERS_LIST; do
            exp=$(get_user_exp "$u")
            pstat=$(passwd -S "$u" 2>/dev/null | awk '{print $2}')
            if [ "$pstat" = "L" ]; then
                stat="Locked"
            else
                stat="Active"
            fi
            on_cnt=$(pgrep -u "$u" sshd 2>/dev/null | wc -l)
            pass=$(grep "^${u}:" /etc/zivpn/zivpn-users.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
            [ -z "$pass" ] && pass=$(grep "^${u}:" /etc/xray/ssh-pass.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
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
        exp_old=$(grep "^${USER}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f3 | tail -n 1)
        if [ -z "$exp_old" ]; then
            exp_old=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
        fi
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
        EXP=$(grep "^${USER}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f3 | tail -n 1)
        if [ -z "$EXP" ]; then
            exp_raw=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
            EXP=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
        fi
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
            XTMP=$(mktemp /tmp/xray_cfg.XXXXXX.json 2>/dev/null || echo "/tmp/xray_tmp.json")
            jq --arg u "$USER" --arg id "$UUID" \
               '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] |
                .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' \
               /etc/xray/config.json > "$XTMP" && mv "$XTMP" /etc/xray/config.json
            echo "$USER:$EXP" >> /etc/xray/xray-exp.txt
        ) 200>/var/lock/xray-config.lock
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
            XTMP=$(mktemp /tmp/xray_cfg.XXXXXX.json 2>/dev/null || echo "/tmp/xray_tmp.json")
            jq --arg u "$USER" \
               '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
               /etc/xray/config.json > "$XTMP" && mv "$XTMP" /etc/xray/config.json
            sed -i "/^${USER}:/d" /etc/xray/xray-exp.txt
            sed -i "/^${USER}:/d" /etc/xray/xray-lock.txt 2>/dev/null
        ) 200>/var/lock/xray-config.lock
        (sleep 1 && systemctl restart xray) >/dev/null 2>&1 &
        echo "{\"success\":true,\"msg\":\"ลบบัญชี Xray $USER เรียบร้อยแล้ว\"}"
        ;;

    restart_all)
        (sleep 1 && systemctl restart rsyslog ssh dropbear xray zivpn hysteria udp-custom ws-epro udpgw@7100 udpgw@7300 fail2ban cron nginx) >/dev/null 2>&1 &
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
        echo "⏳ กำลังเชื่อมต่อเซิร์ฟเวอร์ Ookla Speedtest... กรุณารอ 15-25 วินาที" > /tmp/speedtest_panel.log
        (
            if [ ! -s /usr/local/bin/speedtest ]; then
                ARCH=$(uname -m)
                S_ARCH="x86_64"
                [ "$ARCH" = "aarch64" ] && S_ARCH="aarch64"
                [ "$ARCH" = "arm64" ] && S_ARCH="aarch64"
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

    warp_status)
        /usr/bin/warp-route status
        ;;

    warp_install)
        LKEY=$(echo "$2" | tr -cd 'a-zA-Z0-9_-')
        /usr/bin/warp-route install "$LKEY"
        ;;

    warp_manual)
        PKEY=$(echo "$2" | tr -cd 'a-zA-Z0-9+/=')
        IPV6=$(echo "$3" | tr -cd '0-9a-fA-F:/')
        RESV=$(echo "$4" | tr -cd '0-9,')
        /usr/bin/warp-route manual "$PKEY" "$IPV6" "$RESV"
        ;;

    warp_endpoint)
        EP=$(echo "$2" | tr -cd 'a-zA-Z0-9.:-')
        /usr/bin/warp-route endpoint "$EP"
        ;;

    warp_toggle)
        TARGET=$(echo "$2" | tr -cd 'a-z')
        STATE=$(echo "$3" | tr -cd 'a-z')
        if [ "$STATE" = "on" ]; then
            /usr/bin/warp-route on "$TARGET"
        else
            /usr/bin/warp-route off "$TARGET"
        fi
        ;;

    warp_add)
        DOM=$(echo "$2" | tr -cd 'a-zA-Z0-9.:_/@!-, ')
        /usr/bin/warp-route add "$DOM"
        ;;

    warp_del)
        DOM=$(echo "$2" | tr -cd 'a-zA-Z0-9.:_@!-')
        /usr/bin/warp-route del "$DOM"
        ;;

    warp_preset)
        PTYPE=$(echo "$2" | tr -cd 'a-z')
        /usr/bin/warp-route preset "$PTYPE"
        ;;

    warp_apply)
        /usr/bin/warp-route apply
        ;;

    warp_test)
        /usr/bin/warp-route test
        ;;

    warp_uninstall)
        /usr/bin/warp-route uninstall
        ;;
esac
EOF
chmod +x /usr/bin/panel-cmd

# ==============================================================================
#  ระบบควบคุม WARP Split-Routing สำหรับ SSH + Xray (/usr/bin/warp-route)
# ==============================================================================
cat << 'EOF' > /usr/bin/warp-route
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TZ="Asia/Bangkok"
export XRAY_LOCATION_ASSET="/usr/local/share/xray"

WARP_DIR="/etc/xray/warp"
WARP_JSON="${WARP_DIR}/warp.json"
WARP_CONF="/etc/xray/warp.conf"
WARP_DOMAINS="/etc/xray/warp-domains.txt"
WARP_HASH="/etc/xray/warp-applied.hash"
XRAY_CFG="/etc/xray/config.json"
WGCF_BIN="/usr/local/bin/wgcf"
CGROUP_STATE="/run/warp-cgroup.state"

mkdir -p /etc/xray "$WARP_DIR" /usr/local/share/xray
touch "$WARP_DOMAINS"

init_conf() {
    if [ ! -s "$WARP_CONF" ]; then
        local rpass
        rpass=$(openssl rand -hex 8 2>/dev/null || echo "warp$(date +%s)")
        cat <<CFG > "$WARP_CONF"
XRAY_WARP=off
SSH_WARP=off
BLOCK_QUIC=on
WARP_ENDPOINT=162.159.192.1:2408
TEST_USER=warptest
TEST_PASS=${rpass}
CFG
        chmod 600 "$WARP_CONF"
    fi
}

load_conf() {
    init_conf
    XRAY_WARP=off
    SSH_WARP=off
    BLOCK_QUIC=on
    WARP_ENDPOINT="162.159.192.1:2408"
    TEST_USER="warptest"
    TEST_PASS=""
    # shellcheck disable=SC1090
    source "$WARP_CONF" 2>/dev/null
    [ -z "$WARP_ENDPOINT" ] && WARP_ENDPOINT="162.159.192.1:2408"
    [ -z "$TEST_USER" ] && TEST_USER="warptest"
    if [ -z "$TEST_PASS" ]; then
        TEST_PASS=$(openssl rand -hex 8 2>/dev/null || echo "warp9988")
        sed -i '/^TEST_PASS=/d' "$WARP_CONF"
        echo "TEST_PASS=${TEST_PASS}" >> "$WARP_CONF"
    fi
}

set_conf_val() {
    local k="$1" v="$2"
    init_conf
    if grep -q "^${k}=" "$WARP_CONF" 2>/dev/null; then
        sed -i "s|^${k}=.*|${k}=${v}|g" "$WARP_CONF"
    else
        echo "${k}=${v}" >> "$WARP_CONF"
    fi
}

calc_hash() {
    init_conf
    { cat "$WARP_CONF" 2>/dev/null; echo "---"; sort -u "$WARP_DOMAINS" 2>/dev/null; } | md5sum | awk '{print $1}'
}

json_ok() {
    jq -nc --arg m "$1" '{success:true, msg:$m}'
}

json_err() {
    jq -nc --arg m "$1" '{success:false, msg:$m}'
}

normalize_domain() {
    local raw="$1"
    raw=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -d ' \t\r\n')
    [ -z "$raw" ] && return 1
    case "$raw" in
        geosite:*|domain:*|full:*|keyword:*)
            ;;
        regexp:*)
            return 1
            ;;
        *)
            raw="${raw#http://}"
            raw="${raw#https://}"
            raw="${raw%%/*}"
            raw="${raw%%:*}"
            [ -z "$raw" ] && return 1
            raw="domain:${raw}"
            ;;
    esac
    if ! printf '%s' "$raw" | grep -qE '^(geosite|domain|full|keyword):[a-z0-9._@!-]+$'; then
        return 1
    fi
    printf '%s' "$raw"
    return 0
}

ensure_xray_version() {
    local ver major minor patch
    ver=$(/usr/local/bin/xray version 2>/dev/null | head -n1 | awk '{print $2}')
    major=$(echo "$ver" | cut -d. -f1 | tr -cd '0-9')
    minor=$(echo "$ver" | cut -d. -f2 | tr -cd '0-9')
    patch=$(echo "$ver" | cut -d. -f3 | tr -cd '0-9')
    [ -z "$major" ] && major=0
    [ -z "$minor" ] && minor=0
    [ -z "$patch" ] && patch=0
    if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 8 ]; } || { [ "$major" -eq 1 ] && [ "$minor" -eq 8 ] && [ "$patch" -lt 6 ]; }; then
        bash -c "$(curl -fsSL -m 30 https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
        chmod +x /usr/local/bin/xray 2>/dev/null
        rm -rf /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d
        systemctl daemon-reload >/dev/null 2>&1
    fi
}

ensure_geodata() {
    if [ ! -s /usr/local/share/xray/geosite.dat ]; then
        curl -fsSL -m 25 -o /usr/local/share/xray/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" 2>/dev/null || \
        curl -fsSL -m 25 -o /usr/local/share/xray/geosite.dat "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat" 2>/dev/null || true
    fi
    if [ ! -s /usr/local/share/xray/geoip.dat ]; then
        curl -fsSL -m 25 -o /usr/local/share/xray/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" 2>/dev/null || true
    fi
}

cmd_ipt_clear() {
    while iptables -t nat -C OUTPUT -j WARP_SSH 2>/dev/null; do
        iptables -t nat -D OUTPUT -j WARP_SSH 2>/dev/null
    done
    iptables -t nat -F WARP_SSH 2>/dev/null
    iptables -t nat -X WARP_SSH 2>/dev/null

    while iptables -C OUTPUT -j WARP_QUIC 2>/dev/null; do
        iptables -D OUTPUT -j WARP_QUIC 2>/dev/null
    done
    iptables -F WARP_QUIC 2>/dev/null
    iptables -X WARP_QUIC 2>/dev/null

    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -C OUTPUT -j WARP_SSH6 2>/dev/null; do
            ip6tables -D OUTPUT -j WARP_SSH6 2>/dev/null
        done
        ip6tables -F WARP_SSH6 2>/dev/null
        ip6tables -X WARP_SSH6 2>/dev/null
    fi
}

cmd_ipt_apply() {
    load_conf
    cmd_ipt_clear

    if [ "$SSH_WARP" != "on" ] || [ ! -s "$WARP_JSON" ]; then
        return 0
    fi
    if ! systemctl is-active --quiet xray 2>/dev/null; then
        return 0
    fi
    if ! ss -ltn 2>/dev/null | grep -qE '127\.0\.0\.1:12345[[:space:]]|:12345[[:space:]]'; then
        return 0
    fi
    if [ ! -s "$WARP_DOMAINS" ]; then
        return 0
    fi

    local myip db_cg cg_ok udpgw_cg
    myip=$(curl -sS --max-time 3 ipv4.icanhazip.com 2>/dev/null)
    [ -z "$myip" ] && myip=$(hostname -I | awk '{print $1}')

    iptables -t nat -N WARP_SSH 2>/dev/null
    iptables -t nat -F WARP_SSH
    iptables -t nat -A WARP_SSH -d 0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16,224.0.0.0/4,240.0.0.0/4 -j RETURN
    [ -n "$myip" ] && iptables -t nat -A WARP_SSH -d "$myip" -j RETURN
    # OpenSSH sessions run under the customer's Linux UID (1000-60000)
    iptables -t nat -A WARP_SSH -p tcp -m multiport --dports 80,443 -m owner --uid-owner 1000-60000 -j REDIRECT --to-ports 12345

    # Dropbear processes run as root inside dropbear.service cgroup
    cg_ok="false"
    db_cg=$(systemctl show -p ControlGroup --value dropbear 2>/dev/null | sed 's|^/||')
    [ -z "$db_cg" ] && db_cg="system.slice/dropbear.service"
    if iptables -t nat -A WARP_SSH -p tcp -m multiport --dports 80,443 -m cgroup --path "$db_cg" -j REDIRECT --to-ports 12345 2>/dev/null; then
        cg_ok="true"
    fi
    echo "$cg_ok" > "$CGROUP_STATE"

    iptables -t nat -I OUTPUT 1 -j WARP_SSH

    # Optional QUIC (UDP 443) block so YouTube/Google fall back to TCP -> WARP
    if [ "$BLOCK_QUIC" = "on" ]; then
        iptables -N WARP_QUIC 2>/dev/null
        iptables -F WARP_QUIC
        iptables -A WARP_QUIC -p udp --dport 443 -m owner --uid-owner 1000-60000 -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || true
        udpgw_cg=$(systemctl show -p ControlGroup --value udpgw@7300 2>/dev/null | sed 's|^/||' | sed 's|/udpgw@7300\.service$||')
        [ -z "$udpgw_cg" ] && udpgw_cg="system.slice/system-udpgw.slice"
        iptables -A WARP_QUIC -p udp --dport 443 -m cgroup --path "$udpgw_cg" -j REJECT --reject-with icmp-port-unreachable 2>/dev/null || true
        iptables -I OUTPUT 1 -j WARP_QUIC
    fi

    # Force IPv4 fallback if VPS has global IPv6 so traffic enters IPv4 WARP redirect
    if command -v ip6tables >/dev/null 2>&1 && ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
        ip6tables -N WARP_SSH6 2>/dev/null
        ip6tables -F WARP_SSH6
        ip6tables -A WARP_SSH6 -p tcp -m multiport --dports 80,443 -m owner --uid-owner 1000-60000 -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || true
        if [ "$cg_ok" = "true" ]; then
            ip6tables -A WARP_SSH6 -p tcp -m multiport --dports 80,443 -m cgroup --path "$db_cg" -j REJECT --reject-with icmp6-port-unreachable 2>/dev/null || true
        fi
        ip6tables -I OUTPUT 1 -j WARP_SSH6 2>/dev/null || true
    fi
    return 0
}

cmd_install() {
    local lkey="$1"
    load_conf
    ensure_xray_version

    local arch warch tag url fsize
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) warch="amd64" ;;
        aarch64|arm64) warch="arm64" ;;
        *) json_err "ไม่รองรับสถาปัตยกรรม CPU: $arch"; return 1 ;;
    esac

    fsize=$(stat -c%s "$WGCF_BIN" 2>/dev/null || echo 0)
    if [ ! -x "$WGCF_BIN" ] || [ "$fsize" -lt 1000000 ]; then
        tag=$(curl -fsSL -m 10 "https://api.github.com/repos/ViRb3/wgcf/releases/latest" 2>/dev/null | jq -r '.tag_name // empty')
        [ -z "$tag" ] && tag="v2.2.22"
        url="https://github.com/ViRb3/wgcf/releases/download/${tag}/wgcf_${tag#v}_linux_${warch}"
        curl -fsSL -m 30 -o "$WGCF_BIN" "$url" 2>/dev/null || wget -4 -q --timeout=25 -O "$WGCF_BIN" "$url" 2>/dev/null
        fsize=$(stat -c%s "$WGCF_BIN" 2>/dev/null || echo 0)
        if [ "$fsize" -lt 1000000 ]; then
            url="https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_${warch}"
            curl -fsSL -m 30 -o "$WGCF_BIN" "$url" 2>/dev/null || wget -4 -q --timeout=25 -O "$WGCF_BIN" "$url" 2>/dev/null
            fsize=$(stat -c%s "$WGCF_BIN" 2>/dev/null || echo 0)
        fi
        if [ "$fsize" -lt 1000000 ]; then
            rm -f "$WGCF_BIN"
            json_err "ดาวน์โหลด wgcf ไม่สำเร็จ กรุณาตรวจสอบอินเทอร์เน็ตของ VPS"
            return 1
        fi
        chmod +x "$WGCF_BIN"
    fi

    cd "$WARP_DIR" || { json_err "เข้าโฟลเดอร์ $WARP_DIR ไม่ได้"; return 1; }

    if [ ! -s "${WARP_DIR}/wgcf-account.toml" ]; then
        local reg_out
        reg_out=$(timeout 25 "$WGCF_BIN" register --accept-tos 2>&1)
        if [ ! -s "${WARP_DIR}/wgcf-account.toml" ]; then
            json_err "ลงทะเบียน WARP อัตโนมัติไม่สำเร็จ (อาจโดน Rate Limit 429 จาก Cloudflare) กรุณาลองใหม่หรือใช้โหมดใส่คีย์เอง (Manual): $(echo "$reg_out" | tail -n 1)"
            return 1
        fi
    fi

    local is_plus=false
    if [ -n "$lkey" ]; then
        sed -i "s|^license_key = .*|license_key = '${lkey}'|g" "${WARP_DIR}/wgcf-account.toml" 2>/dev/null
        if timeout 20 "$WGCF_BIN" update >/dev/null 2>&1; then
            is_plus=true
        fi
    fi

    if ! timeout 20 "$WGCF_BIN" generate >/dev/null 2>&1 || [ ! -s "${WARP_DIR}/wgcf-profile.conf" ]; then
        json_err "สร้างโปรไฟล์ WireGuard (wgcf generate) ไม่สำเร็จ"
        return 1
    fi

    local priv pub addr_all v4 v6 dev_id tok cid resv
    priv=$(grep -E '^PrivateKey' "${WARP_DIR}/wgcf-profile.conf" | head -n1 | awk -F'=' '{print $2}' | tr -d ' \r\n')
    pub=$(grep -E '^PublicKey' "${WARP_DIR}/wgcf-profile.conf" | head -n1 | awk -F'=' '{print $2}' | tr -d ' \r\n')
    addr_all=$(grep -E '^Address' "${WARP_DIR}/wgcf-profile.conf" | awk -F'=' '{print $2}' | tr ',' '\n' | tr -d ' \r')
    v4=$(echo "$addr_all" | grep -E '^[0-9]+\.' | head -n1)
    v6=$(echo "$addr_all" | grep ':' | head -n1)
    [ -z "$v4" ] && v4="172.16.0.2/32"
    [ -z "$pub" ] && pub="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    if [ -n "$v6" ] && ! echo "$v6" | grep -q '/'; then v6="${v6}/128"; fi

    if [ -z "$priv" ] || [ -z "$v6" ]; then
        json_err "อ่าน PrivateKey หรือ IPv6 จาก wgcf-profile.conf ไม่สำเร็จ"
        return 1
    fi

    dev_id=$(grep -E '^device_id' "${WARP_DIR}/wgcf-account.toml" | head -n1 | awk -F'=' '{print $2}' | tr -d " '\"\r\n")
    tok=$(grep -E '^access_token' "${WARP_DIR}/wgcf-account.toml" | head -n1 | awk -F'=' '{print $2}' | tr -d " '\"\r\n")
    resv="[0,0,0]"
    if [ -n "$dev_id" ] && [ -n "$tok" ]; then
        cid=$(curl -fsSL -m 10 -H "Authorization: Bearer ${tok}" -H "User-Agent: okhttp/3.12.1" "https://api.cloudflareclient.com/v0a2158/reg/${dev_id}" 2>/dev/null | jq -r '.config.client_id // empty')
        if [ -n "$cid" ]; then
            local rtmp
            rtmp=$(printf '%s' "$cid" | base64 -d 2>/dev/null | od -An -tu1 | awk 'NF>=3{print "["$1","$2","$3"]"; exit}')
            [ -n "$rtmp" ] && resv="$rtmp"
        fi
    fi

    jq -n \
        --arg pk "$priv" \
        --arg a4 "$v4" \
        --arg a6 "$v6" \
        --arg pub "$pub" \
        --argjson res "$resv" \
        --argjson wp "$is_plus" \
        '{private_key:$pk, address_v4:$a4, address_v6:$a6, public_key:$pub, reserved:$res, mtu:1280, warp_plus:$wp}' \
        > "$WARP_JSON"
    chmod 600 "$WARP_JSON"

    cmd_apply
}

cmd_manual() {
    local priv="$1" v6="$2" res_in="$3"
    load_conf
    ensure_xray_version
    if [ -z "$priv" ] || [ -z "$v6" ]; then
        json_err "กรุณากรอก Private Key และ IPv6 Address ให้ครบถ้วน"
        return 1
    fi
    if ! echo "$v6" | grep -q '/'; then v6="${v6}/128"; fi
    local resv="[0,0,0]"
    if [ -n "$res_in" ]; then
        local r1 r2 r3
        r1=$(echo "$res_in" | cut -d, -f1 | tr -cd '0-9')
        r2=$(echo "$res_in" | cut -d, -f2 | tr -cd '0-9')
        r3=$(echo "$res_in" | cut -d, -f3 | tr -cd '0-9')
        if [ -n "$r1" ] && [ -n "$r2" ] && [ -n "$r3" ]; then
            resv="[${r1},${r2},${r3}]"
        fi
    fi
    jq -n \
        --arg pk "$priv" \
        --arg a4 "172.16.0.2/32" \
        --arg a6 "$v6" \
        --arg pub "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=" \
        --argjson res "$resv" \
        '{private_key:$pk, address_v4:$a4, address_v6:$a6, public_key:$pub, reserved:$res, mtu:1280, warp_plus:false}' \
        > "$WARP_JSON"
    chmod 600 "$WARP_JSON"
    cmd_apply
}

cmd_apply() {
    local no_restart=0
    [ "$1" = "--no-restart" ] && no_restart=1
    load_conf

    if [ ! -s "$XRAY_CFG" ] || ! jq . "$XRAY_CFG" >/dev/null 2>&1; then
        json_err "ไฟล์ /etc/xray/config.json ไม่ถูกต้อง"
        return 1
    fi

    local has_geosite=0 warn_msg=""
    if grep -q '^geosite:' "$WARP_DOMAINS" 2>/dev/null; then
        ensure_geodata
        if [ -s /usr/local/share/xray/geosite.dat ]; then
            has_geosite=1
        else
            warn_msg=" (ข้ามรายการ geosite เนื่องจากโหลด geosite.dat ไม่สำเร็จ)"
        fi
    fi

    local domains_json="[]"
    if [ -s "$WARP_DOMAINS" ]; then
        if [ "$has_geosite" -eq 1 ]; then
            domains_json=$(grep -v '^[[:space:]]*$' "$WARP_DOMAINS" | sort -u | jq -R . | jq -s .)
        else
            domains_json=$(grep -v '^[[:space:]]*$' "$WARP_DOMAINS" | grep -v '^geosite:' | sort -u | jq -R . | jq -s .)
        fi
    fi

    local has_warp=0
    [ -s "$WARP_JSON" ] && jq . "$WARP_JSON" >/dev/null 2>&1 && has_warp=1

    local err_out=""
    (
        flock -x 200
        local tmp_cfg
        tmp_cfg=$(mktemp /tmp/xray_warp_cfg.XXXXXX.json)

        if [ "$has_warp" -eq 1 ]; then
            local pk a4 a6 pub resv dom_cnt
            pk=$(jq -r '.private_key' "$WARP_JSON")
            a4=$(jq -r '.address_v4 // "172.16.0.2/32"' "$WARP_JSON")
            a6=$(jq -r '.address_v6' "$WARP_JSON")
            pub=$(jq -r '.public_key // "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="' "$WARP_JSON")
            resv=$(jq -c '.reserved // [0,0,0]' "$WARP_JSON")
            dom_cnt=$(echo "$domains_json" | jq 'length')

            jq \
                --arg pk "$pk" \
                --arg a4 "$a4" \
                --arg a6 "$a6" \
                --arg pub "$pub" \
                --arg ep "$WARP_ENDPOINT" \
                --argjson resv "$resv" \
                --arg tu "$TEST_USER" \
                --arg tp "$TEST_PASS" \
                --arg xon "$XRAY_WARP" \
                --arg son "$SSH_WARP" \
                --argjson doms "$domains_json" \
                --argjson dcnt "$dom_cnt" '
                .inbounds[0].tag = "vmess-in" |
                .inbounds[0].sniffing = {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true} |
                .inbounds[1].tag = "vless-in" |
                .inbounds[1].sniffing = {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true} |
                .inbounds = ([.inbounds[] | select((.tag // "") != "ssh-redir" and (.tag // "") != "warp-test")] + [
                    {
                        "tag": "ssh-redir",
                        "listen": "127.0.0.1",
                        "port": 12345,
                        "protocol": "dokodemo-door",
                        "settings": {"network": "tcp", "followRedirect": true},
                        "streamSettings": {"sockopt": {"tproxy": "redirect"}},
                        "sniffing": {"enabled": true, "destOverride": ["http", "tls"], "routeOnly": true}
                    },
                    {
                        "tag": "warp-test",
                        "listen": "127.0.0.1",
                        "port": 40000,
                        "protocol": "socks",
                        "settings": {"auth": "password", "accounts": [{"user": $tu, "pass": $tp}], "udp": false}
                    }
                ]) |
                .outbounds = [
                    {"protocol": "freedom", "tag": "direct"},
                    {"protocol": "blackhole", "tag": "blocked"},
                    {
                        "protocol": "wireguard",
                        "tag": "warp",
                        "settings": {
                            "secretKey": $pk,
                            "address": [$a4, $a6],
                            "peers": [{
                                "publicKey": $pub,
                                "allowedIPs": ["0.0.0.0/0", "::/0"],
                                "endpoint": $ep,
                                "keepAlive": 30
                            }],
                            "reserved": $resv,
                            "mtu": 1280,
                            "domainStrategy": "ForceIPv4",
                            "noKernelTun": true
                        }
                    }
                ] |
                .routing = {
                    "domainStrategy": "AsIs",
                    "rules": (
                        [{"type": "field", "inboundTag": ["warp-test"], "outboundTag": "warp"}]
                        + (if ($xon == "on" and $dcnt > 0) then [{"type": "field", "inboundTag": ["vmess-in", "vless-in"], "domain": $doms, "outboundTag": "warp"}] else [] end)
                        + (if ($son == "on" and $dcnt > 0) then [{"type": "field", "inboundTag": ["ssh-redir"], "domain": $doms, "outboundTag": "warp"}] else [] end)
                        + [{"type": "field", "inboundTag": ["ssh-redir"], "outboundTag": "direct"}]
                    )
                }
                ' "$XRAY_CFG" > "$tmp_cfg"
        else
            jq '
                .inbounds = [.inbounds[] | select((.tag // "") != "ssh-redir" and (.tag // "") != "warp-test")] |
                .outbounds = [{"protocol": "freedom", "tag": "direct"}] |
                del(.routing)
            ' "$XRAY_CFG" > "$tmp_cfg"
        fi

        if [ ! -s "$tmp_cfg" ]; then
            rm -f "$tmp_cfg"
            exit 2
        fi
        if ! XRAY_LOCATION_ASSET=/usr/local/share/xray /usr/local/bin/xray run -test -config "$tmp_cfg" >/tmp/warp_xray_test.err 2>&1; then
            rm -f "$tmp_cfg"
            exit 3
        fi
        mv "$tmp_cfg" "$XRAY_CFG"
        chmod 644 "$XRAY_CFG"
    ) 200>/var/lock/xray-config.lock

    local rc=$?
    if [ "$rc" -ne 0 ]; then
        err_out=$(tail -n 2 /tmp/warp_xray_test.err 2>/dev/null | tr '\n' ' ')
        rm -f /tmp/warp_xray_test.err
        json_err "ตรวจสอบคอนฟิก Xray ไม่ผ่าน (คงค่าเดิมไว้ให้แล้ว): ${err_out}"
        return 1
    fi
    rm -f /tmp/warp_xray_test.err
    calc_hash > "$WARP_HASH"

    if [ "$no_restart" -eq 0 ]; then
        systemctl restart xray >/dev/null 2>&1
        for _t in 1 2 3 4 5 6; do
            if systemctl is-active --quiet xray && { [ "$has_warp" -eq 0 ] || ss -ltn 2>/dev/null | grep -q ':12345 '; }; then
                break
            fi
            sleep 0.5
        done
        cmd_ipt_apply
    fi

    json_ok "บันทึกคอนฟิกและรีสตาร์ท Xray เรียบร้อยแล้ว${warn_msg}"
}

cmd_add() {
    local raw_input="$1" added=0 skipped=0
    local token norm
    for token in $(printf '%s' "$raw_input" | tr ',' ' '); do
        norm=$(normalize_domain "$token") || { skipped=$((skipped + 1)); continue; }
        if ! grep -qxF "$norm" "$WARP_DOMAINS" 2>/dev/null; then
            echo "$norm" >> "$WARP_DOMAINS"
            added=$((added + 1))
        fi
    done
    if [ "$added" -eq 0 ] && [ "$skipped" -gt 0 ]; then
        json_err "รูปแบบโดเมนไม่ถูกต้อง (ห้ามใช้ regexp: หรืออักขระพิเศษ)"
        return 1
    fi
    if [ "$added" -eq 0 ]; then
        json_ok "โดเมนนี้มีอยู่ในรายการแล้ว"
        return 0
    fi
    json_ok "เพิ่มโดเมน ${added} รายการแล้ว (กด 'บันทึกและรีสตาร์ท Xray' เพื่อให้มีผล)"
}

cmd_del() {
    local raw="$1" norm
    norm=$(normalize_domain "$raw") || norm="$raw"
    grep -vxF "$norm" "$WARP_DOMAINS" > /tmp/warp_dom_tmp.$$ 2>/dev/null || true
    mv /tmp/warp_dom_tmp.$$ "$WARP_DOMAINS"
    json_ok "ลบ ${norm} แล้ว (กด 'บันทึกและรีสตาร์ท Xray' เพื่อให้มีผล)"
}

cmd_preset() {
    local ptype="$1"
    local list
    if [ "$ptype" = "youtube" ]; then
        list="domain:youtube.com domain:googlevideo.com domain:ytimg.com domain:youtubei.googleapis.com"
    else
        list="full:www.cloudflare.com geosite:netflix domain:truemoney.com domain:7eleven.co.th domain:m-fixer.net domain:play-rfcdn.ais.th domain:ovp.ais.th domain:ovpplay.com"
    fi
    local added=0 item
    for item in $list; do
        if ! grep -qxF "$item" "$WARP_DOMAINS" 2>/dev/null; then
            echo "$item" >> "$WARP_DOMAINS"
            added=$((added + 1))
        fi
    done
    json_ok "เพิ่มรายการแนะนำ ${added} โดเมนแล้ว (กด 'บันทึกและรีสตาร์ท Xray' เพื่อให้มีผล)"
}

cmd_status() {
    load_conf
    local installed=false registered=false xray_on=false ssh_on=false bquic=false cg_ok=true wp=false pending=false
    [ -x "$WGCF_BIN" ] && installed=true
    if [ -s "$WARP_JSON" ] && jq . "$WARP_JSON" >/dev/null 2>&1; then
        registered=true
        [ "$(jq -r '.warp_plus // false' "$WARP_JSON")" = "true" ] && wp=true
    fi
    [ "$XRAY_WARP" = "on" ] && xray_on=true
    [ "$SSH_WARP" = "on" ] && ssh_on=true
    [ "$BLOCK_QUIC" = "on" ] && bquic=true
    if [ -f "$CGROUP_STATE" ]; then
        [ "$(cat "$CGROUP_STATE" 2>/dev/null)" = "true" ] && cg_ok=true || cg_ok=false
    else
        local db_cg
        db_cg=$(systemctl show -p ControlGroup --value dropbear 2>/dev/null | sed 's|^/||')
        [ -z "$db_cg" ] && db_cg="system.slice/dropbear.service"
        if ! iptables -t nat -C OUTPUT -m cgroup --path "$db_cg" -j RETURN 2>/dev/null; then
            if iptables -t nat -N _WARP_CG_CHK 2>/dev/null; then
                if ! iptables -t nat -A _WARP_CG_CHK -m cgroup --path "$db_cg" -j RETURN 2>/dev/null; then
                    cg_ok=false
                fi
                iptables -t nat -F _WARP_CG_CHK 2>/dev/null
                iptables -t nat -X _WARP_CG_CHK 2>/dev/null
            fi
        fi
    fi

    local cur_h app_h
    cur_h=$(calc_hash)
    app_h=$(cat "$WARP_HASH" 2>/dev/null)
    if [ "$registered" = "true" ] && [ "$cur_h" != "$app_h" ]; then
        pending=true
    fi

    local doms="[]"
    if [ -s "$WARP_DOMAINS" ]; then
        doms=$(grep -v '^[[:space:]]*$' "$WARP_DOMAINS" | jq -R . | jq -s .)
    fi
    local ssh_chain=false
    iptables -t nat -L WARP_SSH -n >/dev/null 2>&1 && ssh_chain=true

    jq -nc \
        --argjson inst "$installed" \
        --argjson reg "$registered" \
        --argjson xon "$xray_on" \
        --argjson son "$ssh_on" \
        --argjson bq "$bquic" \
        --argjson cg "$cg_ok" \
        --arg ep "$WARP_ENDPOINT" \
        --argjson wp "$wp" \
        --argjson pend "$pending" \
        --argjson sc "$ssh_chain" \
        --argjson doms "$doms" \
        '{installed:$inst, registered:$reg, xray_on:$xon, ssh_on:$son, block_quic:$bq, cgroup_ok:$cg, endpoint:$ep, warp_plus:$wp, pending:$pend, ssh_chain:$sc, domains:$doms}'
}

cmd_test() {
    load_conf
    local trace warp_ip warp_st colo vps_trace vps_ip ssh_chain=false ssh_pkts=0 listen_12345=false
    if [ -s "$WARP_JSON" ]; then
        trace=$(curl -fsSL -m 10 -x "socks5h://${TEST_USER}:${TEST_PASS}@127.0.0.1:40000" "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)
    fi
    warp_ip=$(echo "$trace" | awk -F= '$1=="ip"{print $2}')
    warp_st=$(echo "$trace" | awk -F= '$1=="warp"{print $2}')
    colo=$(echo "$trace" | awk -F= '$1=="colo"{print $2}')
    [ -z "$warp_st" ] && warp_st="off"

    vps_trace=$(curl -fsSL -m 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)
    vps_ip=$(echo "$vps_trace" | awk -F= '$1=="ip"{print $2}')
    [ -z "$vps_ip" ] && vps_ip=$(curl -sS --max-time 3 ipv4.icanhazip.com 2>/dev/null)

    if iptables -t nat -L WARP_SSH -n >/dev/null 2>&1; then
        ssh_chain=true
        ssh_pkts=$(iptables -t nat -L WARP_SSH -v -n -x 2>/dev/null | awk '/REDIRECT/{s+=$1} END{print s+0}')
    fi
    ss -ltn 2>/dev/null | grep -qE ':12345[[:space:]]' && listen_12345=true

    jq -nc \
        --arg wip "$warp_ip" \
        --arg wst "$warp_st" \
        --arg colo "$colo" \
        --arg vip "$vps_ip" \
        --argjson sc "$ssh_chain" \
        --argjson sp "${ssh_pkts:-0}" \
        --argjson l12 "$listen_12345" \
        '{success:($wst=="on" or $wst=="plus"), warp_ip:$wip, warp:$wst, colo:$colo, vps_ip:$vip, ssh_chain:$sc, ssh_packets:$sp, listen_12345:$l12}'
}

cmd_uninstall() {
    cmd_ipt_clear
    set_conf_val XRAY_WARP off
    set_conf_val SSH_WARP off
    rm -f "$WARP_JSON" "$WARP_HASH"
    cmd_apply >/dev/null 2>&1
    json_ok "ปิดระบบ WARP Routing เรียบร้อยแล้ว (ไฟล์บัญชีเดิมยังคงเก็บไว้ใน /etc/xray/warp)"
}

case "$1" in
    install)    cmd_install "$2" ;;
    manual)     cmd_manual "$2" "$3" "$4" ;;
    endpoint)
        if ! echo "$2" | grep -qE '^[a-zA-Z0-9.-]+:[0-9]{2,5}$'; then
            json_err "รูปแบบ Endpoint ไม่ถูกต้อง (ตัวอย่าง: 162.159.192.1:2408)"
            exit 1
        fi
        set_conf_val WARP_ENDPOINT "$2"
        json_ok "ตั้งค่า Endpoint เป็น $2 แล้ว (กด 'บันทึกและรีสตาร์ท Xray' เพื่อให้มีผล)"
        ;;
    apply)      cmd_apply "$2" ;;
    on|off)
        case "$2" in
            xray) set_conf_val XRAY_WARP "$1" ;;
            ssh)  set_conf_val SSH_WARP "$1" ;;
            quic) set_conf_val BLOCK_QUIC "$1" ;;
            *) json_err "ไม่รู้จักสวิตช์: $2"; exit 1 ;;
        esac
        json_ok "ปรับสวิตช์ $2 เป็น $1 แล้ว (กด 'บันทึกและรีสตาร์ท Xray' เพื่อให้มีผล)"
        ;;
    add)        cmd_add "$2" ;;
    del)        cmd_del "$2" ;;
    preset)     cmd_preset "$2" ;;
    ipt-apply)  cmd_ipt_apply ;;
    ipt-clear)  cmd_ipt_clear ;;
    status)     cmd_status ;;
    test)       cmd_test ;;
    uninstall)  cmd_uninstall ;;
    *)          echo "Usage: warp-route {install|manual|endpoint|apply|on|off|add|del|preset|ipt-apply|ipt-clear|status|test|uninstall}" ;;
esac
EOF
chmod +x /usr/bin/warp-route

cat <<EOF > /etc/sudoers.d/vpn-api
www-data ALL=(ALL) NOPASSWD: /usr/bin/api-vpn, /usr/bin/panel-cmd, /usr/bin/rebuild-hysteria, /usr/sbin/useradd, /usr/sbin/usermod, /usr/sbin/groupdel, /usr/sbin/chpasswd, /usr/bin/chage, /usr/sbin/userdel, /usr/bin/killall, /usr/bin/passwd -u *, /usr/bin/passwd -l *, /bin/systemctl restart *, /bin/systemctl is-active *, /bin/systemctl daemon-reload
EOF
chmod 440 /etc/sudoers.d/vpn-api

REPO_URL="https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main"
mkdir -p /home/vps/public_html /root/vnext_api

if [ -s /home/vps/public_html/api_ssh.php ]; then
    SAVED_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php | cut -d'"' -f2)
fi
[ -z "$SAVED_KEY" ] && SAVED_KEY=$(openssl rand -hex 16 2>/dev/null || echo "TOEYVPN_$(date +%s)")

# ดาวน์โหลดไฟล์ Web Panel & API จาก GitHub Repository v2
echo "กำลังดาวน์โหลดไฟล์ Web Dashboard & API..."
wget -4 -q --no-check-certificate -O /home/vps/public_html/api_ssh.php "${REPO_URL}/web/api_ssh.php?v=$(date +%s)"
wget -4 -q --no-check-certificate -O /home/vps/public_html/index.php "${REPO_URL}/web/index.php?v=$(date +%s)"
wget -4 -q --no-check-certificate -O /home/vps/public_html/qrcode.min.js "${REPO_URL}/web/qrcode.min.js?v=$(date +%s)"

# ปรับแก้ Secret Key ลงในไฟล์ API
sed -i "s/__SECRET_KEY__/${SAVED_KEY}/g" /home/vps/public_html/api_ssh.php
cp -f /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php

chown -R www-data:www-data /home/vps/public_html
chmod -R 755 /home/vps/public_html

systemctl enable php*-fpm >/dev/null 2>&1
systemctl restart php*-fpm
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

# 11.5 ติดตั้ง Xray Core, ออกใบรับรอง SSL (Let's Encrypt) และตั้งค่า Nginx (Port 80/443)
if [ ! -s /usr/local/bin/xray ]; then
    echo "กำลังติดตั้ง Xray Core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
    chmod +x /usr/local/bin/xray 2>/dev/null
    rm -rf /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d
fi

# สร้าง config.json ของ Xray เฉพาะกรณีติดตั้งใหม่ (ไม่ทับบัญชีลูกค้าเดิมตอนกดเมนู 27)
if [ ! -s /etc/xray/config.json ] || ! jq . /etc/xray/config.json >/dev/null 2>&1; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    cat <<JSON > /etc/xray/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "email": "default"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "email": "default"
          }
        ],
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
      "protocol": "freedom"
    }
  ]
}
JSON
fi

mkdir -p /var/log/xray /etc/xray /usr/local/etc/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chmod -R 777 /var/log/xray
chown -R root:root /var/log/xray /etc/xray /usr/local/etc/xray 2>/dev/null

cat << 'SVC' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
ExecStartPost=-/bin/bash -c 'sleep 1; [ -x /usr/bin/warp-route ] && /usr/bin/warp-route ipt-apply >/dev/null 2>&1 || true'
ExecStopPost=-/bin/bash -c '[ -x /usr/bin/warp-route ] && /usr/bin/warp-route ipt-clear >/dev/null 2>&1 || true'
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SVC

# ขอใบรับรอง SSL ของจริง (Let's Encrypt) เฉพาะตอนติดตั้งใหม่ที่ยังไม่ได้ขอ acme.sh
if [[ ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [ ! -d "/root/.acme.sh/${DOMAIN}_ecc" ]; then
    echo "กำลังออกใบรับรอง SSL สำหรับโดเมน ${DOMAIN}..."
    systemctl stop nginx >/dev/null 2>&1
    curl https://get.acme.sh | sh -s email=admin@${DOMAIN} >/dev/null 2>&1
    /root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    /root/.acme.sh/acme.sh --issue -d "${DOMAIN}" --standalone -k ec-256 --force
    /root/.acme.sh/acme.sh --installcert -d "${DOMAIN}" \
        --fullchainpath /etc/xray/xray.crt \
        --keypath /etc/xray/xray.key --ecc
    chmod 644 /etc/xray/xray.crt /etc/xray/xray.key
    /usr/bin/rebuild-hysteria
fi

# ตั้งค่า Nginx Stream บนพอร์ต 443 เพื่อแยกทราฟฟิก (Multiplex 443):
# 1) Direct SSL (Stunnel4) -> ส่งต่อไปยัง 127.0.0.1:444 (Dropbear SSH)
# 2) Web / Xray / SSH-WS -> ส่งต่อไปยัง 127.0.0.1:8443 (Nginx HTTPS)
sed -i '/# Multiplex Port 443/,$d' /etc/nginx/nginx.conf 2>/dev/null
sed -i '/stream_mux.conf/d' /etc/nginx/nginx.conf 2>/dev/null
rm -f /etc/nginx/stream_mux.conf

cat << 'MUX' > /etc/nginx/stream_mux.conf
stream {
    map $ssl_preread_alpn_protocols $upstream_443 {
        "~\b(h2|http/1\.1)\b"  127.0.0.1:8443;
        default               127.0.0.1:444;
    }

    server {
        listen 443 reuseport;
        listen [::]:443 reuseport;
        proxy_pass $upstream_443;
        ssl_preread on;
    }
}
MUX
echo "include /etc/nginx/stream_mux.conf;" >> /etc/nginx/nginx.conf

# สร้างไฟล์คอนฟิก Nginx พอร์ต 80 และ 8443 (/vmess, /vless, และ /ssh-ws)
cat <<NGX > /etc/nginx/conf.d/xray.conf
server {
    listen 80;
    listen [::]:80;
    listen 127.0.0.1:8443 ssl http2;
    server_name ${DOMAIN} _;

    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location = /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location = /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10015;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGX

for xport in 80 443; do
    if ! iptables -C INPUT -p tcp --dport "$xport" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "$xport" -j ACCEPT
    fi
done
netfilter-persistent save >/dev/null 2>&1
systemctl daemon-reload
systemctl enable xray nginx >/dev/null 2>&1
mkdir -p /usr/local/etc/xray
rm -f /usr/local/etc/xray/config.json
ln -s /etc/xray/config.json /usr/local/etc/xray/config.json
systemctl restart xray nginx

# 12. ติดตั้ง BadVPN UDPGW (พอร์ต 7100 และ 7300)
if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    echo "กำลังติดตั้ง BadVPN UDPGW..."
    wget -q -O /usr/local/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
fi
if [ ! -s /usr/local/bin/badvpn-udpgw ]; then
    wget -q -O /usr/local/bin/badvpn-udpgw "https://github.com/ambrop72/badvpn/raw/master/badvpn-udpgw64"
fi
chmod +x /usr/local/bin/badvpn-udpgw

cat <<EOF > /etc/systemd/system/udpgw@.service
[Unit]
Description=BadVPN UDPGW Service on Port %i
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:%i --max-clients 1000 --max-connections-for-client 100
Restart=on-failure
RestartSec=3
LimitNOFILE=1000000
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

systemctl stop udpgw@7200 >/dev/null 2>&1
systemctl disable udpgw@7200 >/dev/null 2>&1
systemctl daemon-reload
for port in 7100 7300; do
    systemctl enable udpgw@${port} >/dev/null 2>&1
    systemctl restart udpgw@${port}
done

# 13. ตั้งค่า Dropbear (พอร์ต 109 และ 143) และ SSH WebSocket (ws-epro พอร์ต 10015)
cat <<EOF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

if ! grep -qxF '/bin/false' /etc/shells; then echo "/bin/false" >> /etc/shells; fi
if ! grep -qxF '/usr/sbin/nologin' /etc/shells; then echo "/usr/sbin/nologin" >> /etc/shells; fi

cat <<EOF > /etc/issue.net
<p style="text-align:center"><b>=== PRIVATE VPN SERVER (NO TORRENT) ===</b></p>
EOF

systemctl enable dropbear >/dev/null 2>&1
systemctl restart dropbear

cat << 'EOF' > /usr/local/bin/ws-epro
#!/usr/bin/env python3
import socket, threading, select

LISTEN_HOST = '127.0.0.1'
LISTEN_PORT = 10015
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 22

def handle_client(client_sock):
    target_sock = None
    try:
        client_sock.settimeout(10)
        data = client_sock.recv(4096)
        if not data:
            return
        client_sock.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
        client_sock.settimeout(None)

        target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_sock.connect((TARGET_HOST, TARGET_PORT))

        sockets = [client_sock, target_sock]
        while True:
            r, _, _ = select.select(sockets, [], [], 120)
            if not r:
                break
            for s in r:
                buf = s.recv(16384)
                if not buf:
                    return
                if s is client_sock:
                    target_sock.sendall(buf)
                else:
                    client_sock.sendall(buf)
    except Exception:
        pass
    finally:
        try: client_sock.close()
        except: pass
        try:
            if target_sock: target_sock.close()
        except: pass

def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((LISTEN_HOST, LISTEN_PORT))
    server.listen(1024)
    while True:
        client_sock, _ = server.accept()
        threading.Thread(target=handle_client, args=(client_sock,), daemon=True).start()

if __name__ == '__main__':
    main()
EOF
chmod +x /usr/local/bin/ws-epro

cat <<EOF > /etc/systemd/system/ws-epro.service
[Unit]
Description=SSH WebSocket Proxy Service (Port 10015)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/ws-epro
Restart=always
RestartSec=2
LimitNOFILE=1000000
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable ws-epro >/dev/null 2>&1
systemctl restart ws-epro

# 13.5 ติดตั้งและตั้งค่า Stunnel4 (SSL/TLS Wrapper พอร์ต 444, 777 และพอร์ตภายใน 10443)
echo "กำลังตั้งค่า Stunnel4 (SSL/TLS Wrapper พอร์ต 444, 777, 10443)..."
mkdir -p /etc/stunnel /var/run/stunnel4
cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem 2>/dev/null
chmod 600 /etc/stunnel/stunnel.pem 2>/dev/null

sed -i 's/ENABLED=0/ENABLED=1/g' /etc/default/stunnel4 2>/dev/null
grep -qxF 'ENABLED=1' /etc/default/stunnel4 2>/dev/null || echo 'ENABLED=1' >> /etc/default/stunnel4 2>/dev/null

cat << 'EOF' > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel4.pid
cert = /etc/stunnel/stunnel.pem
client = no
debug = 0
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[dropbear-ssl-444]
accept = 444
connect = 127.0.0.1:109

[openssh-ssl-777]
accept = 777
connect = 127.0.0.1:22

[dropbear-ssl-10443]
accept = 10443
connect = 127.0.0.1:109
EOF

cat << 'EOF' > /etc/systemd/system/stunnel4.service
[Unit]
Description=SSL tunnel for network daemons (Stunnel4)
After=network.target

[Service]
Type=forking
PIDFile=/var/run/stunnel4.pid
ExecStart=/usr/bin/stunnel4 /etc/stunnel/stunnel.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

for sport in 444 777 10443; do
    if ! iptables -C INPUT -p tcp --dport "$sport" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p tcp --dport "$sport" -j ACCEPT
    fi
done

systemctl daemon-reload
systemctl enable stunnel4 >/dev/null 2>&1
systemctl restart stunnel4 >/dev/null 2>&1


# 14. สร้างสคริปต์ลบบัญชีหมดอายุอัตโนมัติ (xp)
cat << 'EOF' > /usr/bin/xp
#!/bin/bash
export LC_ALL=en_US.UTF-8
export TZ="Asia/Bangkok"
today=$(date +%Y-%m-%d)
today_sec=$(date -d "$today" +%s)

# 1. ตรวจสอบบัญชี SSH หมดอายุ
for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    exp_date=$(grep "^${user}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f3 | tail -n 1)
    if [ -z "$exp_date" ]; then
        exp_date=$(chage -l "$user" 2>/dev/null | grep "Account expires" | awk -F": " '{print $2}')
    fi
    if [ "$exp_date" != "never" ] && [ -n "$exp_date" ]; then
        exp_sec=$(date -d "$exp_date" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && continue
        if [ $today_sec -gt $exp_sec ]; then
            /usr/bin/api-vpn delete "$user" "" "" >/dev/null 2>&1
            echo "Deleted Expired SSH Account: $user (Exp: $exp_date)"
        fi
    fi
done

# 2. ตรวจสอบบัญชี Xray หมดอายุ (ใช้ Snapshot file ป้องกัน loop ข้ามบรรทัด)
if [ -s /etc/xray/xray-exp.txt ]; then
    cp /etc/xray/xray-exp.txt /tmp/xray-exp-snap.txt
    xray_changed=0
    while IFS=':' read -r x_user x_exp; do
        [ -z "$x_user" ] && continue
        exp_sec=$(date -d "$x_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && continue
        if [ $today_sec -gt $exp_sec ]; then
            (
                flock -x 200
                XTMP=$(mktemp /tmp/xray_cfg.XXXXXX.json 2>/dev/null || echo "/tmp/xray_tmp.json")
                jq --arg u "$x_user" \
                   '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                    (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
                   /etc/xray/config.json > "$XTMP" && mv "$XTMP" /etc/xray/config.json
                sed -i "/^$x_user:/d" /etc/xray/xray-exp.txt
                sed -i "/^$x_user:/d" /etc/xray/xray-lock.txt 2>/dev/null
            ) 200>/var/lock/xray-config.lock
            xray_changed=1
            echo "Deleted Expired Xray Account: $x_user"
        fi
    done < /tmp/xray-exp-snap.txt
    rm -f /tmp/xray-exp-snap.txt
    [ $xray_changed -eq 1 ] && systemctl restart xray >/dev/null 2>&1
fi

# 3. ตรวจสอบรหัสผ่าน ZIVPN หมดอายุ (ใช้ Snapshot file)
if [ -s /etc/zivpn/zivpn-exp.txt ]; then
    cp /etc/zivpn/zivpn-exp.txt /tmp/zivpn-exp-snap.txt
    zivpn_changed=0
    while IFS=':' read -r z_pass z_exp; do
        [ -z "$z_pass" ] && continue
        exp_sec=$(date -d "$z_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && continue
        if [ $today_sec -gt $exp_sec ]; then
            ZTMP=$(mktemp /tmp/zivpn_cfg.XXXXXX.json 2>/dev/null || echo "/tmp/zivpn_tmp.json")
            jq --arg p "$z_pass" '.auth.config -= [$p]' /etc/zivpn/config.json > "$ZTMP" && mv "$ZTMP" /etc/zivpn/config.json
            sed -i "/^$z_pass:/d" /etc/zivpn/zivpn-exp.txt
            sed -i "/:$z_pass$/d" /etc/zivpn/zivpn-users.txt 2>/dev/null
            zivpn_changed=1
            echo "Deleted Expired ZIVPN Password: $z_pass"
        fi
    done < /tmp/zivpn-exp-snap.txt
    rm -f /tmp/zivpn-exp-snap.txt
    [ $zivpn_changed -eq 1 ] && systemctl restart zivpn >/dev/null 2>&1
fi

# 4. ตรวจสอบบัญชี Hysteria 2 หมดอายุ (ใช้ Snapshot file)
if [ -s /etc/hysteria/hys-users.txt ]; then
    cp /etc/hysteria/hys-users.txt /tmp/hys-users-snap.txt
    hys_changed=0
    while IFS=':' read -r h_user h_pass h_exp; do
        if [ -n "$h_exp" ]; then
            exp_sec=$(date -d "$h_exp" +%s 2>/dev/null)
            [ -z "$exp_sec" ] && exp_sec=9999999999
            if [ $today_sec -gt $exp_sec ]; then
                sed -i "/^$h_user:/d" /etc/hysteria/hys-users.txt
                echo "Deleted Expired Hysteria2 Account: $h_user"
                hys_changed=1
            fi
        fi
    done < /tmp/hys-users-snap.txt
    rm -f /tmp/hys-users-snap.txt
    [ $hys_changed -eq 1 ] && /usr/bin/rebuild-hysteria >/dev/null 2>&1
fi
EOF
chmod +x /usr/bin/xp

# 15. สร้างสคริปต์ลบตัวทดลองรายชั่วโมง + เตะคนล็อกอินซ้อน (tendang), ล้างขยะ (clear-log), สำรองข้อมูล (backup-vpn / restore-vpn)
[ ! -f /etc/xray/limit-ssh ] && echo "2" > /etc/xray/limit-ssh
[ ! -f /etc/xray/autoreboot-status ] && echo "เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)" > /etc/xray/autoreboot-status

cat << 'EOF' > /usr/bin/tendang
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TZ="Asia/Bangkok"
exec 200>/var/lock/tendang.lock
flock -n 200 || exit 0

# Watchdog ตรวจสอบกฎ WARP_SSH (ถ้า Xray ดับให้ปลดกฎทันที กันลูกค้า SSH เข้าเว็บไม่ได้)
if [ -x /usr/bin/warp-route ]; then
    if iptables -t nat -L WARP_SSH -n >/dev/null 2>&1; then
        if ! systemctl is-active --quiet xray 2>/dev/null || ! ss -ltn 2>/dev/null | grep -qE ':12345[[:space:]]'; then
            /usr/bin/warp-route ipt-clear >/dev/null 2>&1
        fi
    elif grep -q '^SSH_WARP=on' /etc/xray/warp.conf 2>/dev/null && [ -s /etc/xray/warp/warp.json ]; then
        if systemctl is-active --quiet xray 2>/dev/null && ss -ltn 2>/dev/null | grep -qE ':12345[[:space:]]'; then
            /usr/bin/warp-route ipt-apply >/dev/null 2>&1
        fi
    fi
fi

# จำกัดขนาด /var/log/xray/access.log ไม่ให้เกิน 100MB (เก็บ 2000 บรรทัดล่าสุดไว้สำหรับเมนู 19)
if [ -f /var/log/xray/access.log ]; then
    ACC_SIZE=$(stat -c%s /var/log/xray/access.log 2>/dev/null || echo 0)
    if [ "$ACC_SIZE" -gt 104857600 ]; then
        tail -n 2000 /var/log/xray/access.log > /tmp/xray_acc_tail.log 2>/dev/null && cat /tmp/xray_acc_tail.log > /var/log/xray/access.log 2>/dev/null
        rm -f /tmp/xray_acc_tail.log
    fi
fi

# ตรวจสอบและลบบัญชีทดลองรายชั่วโมง (hours=1) ที่หมดเวลาทุก 1 นาที (ใช้ Snapshot file)
if [ -s /etc/xray/trial-exp.txt ]; then
    cp /etc/xray/trial-exp.txt /tmp/trial-exp-snap.txt
    NOW_TS=$(date +%s)
    while IFS=':' read -r t_user t_exp; do
        [ -z "$t_user" ] && continue
        if [ -n "$t_exp" ] && [ "$NOW_TS" -ge "$t_exp" ]; then
            /usr/bin/api-vpn delete "$t_user" "" "" >/dev/null 2>&1
            sed -i "/^${t_user}:/d" /etc/xray/trial-exp.txt 2>/dev/null
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Deleted Expired Trial User: $t_user" >> /var/log/autokill.log
        fi
    done < /tmp/trial-exp-snap.txt
    rm -f /tmp/trial-exp-snap.txt
fi

MAX=$(cat /etc/xray/limit-ssh 2>/dev/null)
[ -z "$MAX" ] && MAX=2
if [ "$MAX" -le 0 ]; then
    exit 0
fi

for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    pids=$(pgrep -u "$user" sshd)
    if [ -n "$pids" ]; then
        count=$(echo "$pids" | wc -l)
    else
        count=0
    fi

    if [ $count -gt $MAX ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Kick Multi-Login User: $user ($count/$MAX sessions)" >> /var/log/autokill.log
        kill -9 $pids 2>/dev/null
    fi
done
EOF
chmod +x /usr/bin/tendang

mkdir -p /etc/systemd/journald.conf.d
cat << 'EOF' > /etc/systemd/journald.conf.d/99-limit.conf
[Journal]
SystemMaxUse=50M
RuntimeMaxUse=30M
MaxRetentionSec=3day
EOF
systemctl restart systemd-journald >/dev/null 2>&1

cat << 'EOF' > /usr/bin/clear-log
#!/bin/bash
for logfile in /var/log/xray/access.log /var/log/xray/error.log /var/log/nginx/access.log /var/log/nginx/error.log /var/log/syslog /var/log/syslog.1 /var/log/auth.log /var/log/daemon.log /var/log/kern.log /var/log/btmp /var/log/messages /var/log/debug /var/log/fail2ban.log; do
    if [ -f "$logfile" ]; then
        truncate -s 0 "$logfile" 2>/dev/null
    fi
done
find /var/log -path /var/log/journal -prune -o -type f \( -name "*.gz" -o -name "*.1" -o -name "*.2" -o -name "*.3" \) -delete 2>/dev/null
journalctl --vacuum-size=30M >/dev/null 2>&1
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
EOF
chmod +x /usr/bin/clear-log

cat << 'EOF' > /usr/bin/backup-vpn
#!/bin/bash
export TZ="Asia/Bangkok"
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

MYIP=$(curl -sS ipv4.icanhazip.com)
DATE=$(date +%Y-%m-%d_%H-%M)
RAND_KEY=$(openssl rand -hex 4)
BACKUP_DIR="/tmp/vpn_backup_data"
ZIP_NAME="vpn-backup-${DATE}-${RAND_KEY}.zip"

rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/xray" "$BACKUP_DIR/zivpn" "$BACKUP_DIR/hysteria" "$BACKUP_DIR/api"

> "$BACKUP_DIR/ssh-users.txt"
for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
    hash=$(grep "^${user}:" /etc/shadow | cut -d: -f2)
    exp_ymd=$(grep "^${user}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f3 | tail -n 1)
    if [ -z "$exp_ymd" ]; then
        exp_raw=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
        if [ "$exp_raw" = "never" ] || [ -z "$exp_raw" ]; then
            exp_ymd="never"
        else
            exp_ymd=$(date -d "$exp_raw" +%Y-%m-%d 2>/dev/null)
            [ -z "$exp_ymd" ] && exp_ymd="never"
        fi
    fi
    echo "${user}|${hash}|${exp_ymd}" >> "$BACKUP_DIR/ssh-users.txt"
done

cp -f /etc/xray/config.json "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/xray-exp.txt "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/xray-lock.txt "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/trial-exp.txt "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/ssh-pass.txt "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/limit-ssh "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/warp-domains.txt "$BACKUP_DIR/xray/" 2>/dev/null
cp -f /etc/xray/warp.conf "$BACKUP_DIR/xray/" 2>/dev/null
[ -d /etc/xray/warp ] && cp -rf /etc/xray/warp "$BACKUP_DIR/xray/" 2>/dev/null

cp -f /etc/zivpn/config.json "$BACKUP_DIR/zivpn/" 2>/dev/null
cp -f /etc/zivpn/zivpn-exp.txt "$BACKUP_DIR/zivpn/" 2>/dev/null
cp -f /etc/zivpn/zivpn-users.txt "$BACKUP_DIR/zivpn/" 2>/dev/null

cp -f /etc/hysteria/hys-users.txt "$BACKUP_DIR/hysteria/" 2>/dev/null
cp -f /home/vps/public_html/api_ssh.php "$BACKUP_DIR/api/" 2>/dev/null

cd "$BACKUP_DIR" || exit
zip -r -q "/root/${ZIP_NAME}" ./*
cd /root || exit
rm -rf "$BACKUP_DIR"

mkdir -p /home/vps/public_html
find /home/vps/public_html -name "vpn-backup-*.zip" -mmin +60 -delete 2>/dev/null
rm -f /home/vps/public_html/vpn-backup-*.zip
cp "/root/${ZIP_NAME}" "/home/vps/public_html/${ZIP_NAME}"
chown www-data:www-data "/home/vps/public_html/${ZIP_NAME}"
chmod 644 "/home/vps/public_html/${ZIP_NAME}"

TELE_STAT="ไม่ได้ตั้งค่า"
if [ -f /etc/xray/tele-bot.conf ]; then
    source /etc/xray/tele-bot.conf
    if [ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ]; then
        curl -s -F chat_id="$CHAT_ID" \
             -F document=@"/root/${ZIP_NAME}" \
             -F caption="📦 Backup ข้อมูล VPN เซิร์ฟเวอร์: ${MYIP} (${DATE})" \
             "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" >/dev/null 2>&1
        TELE_STAT="${GREEN}ส่งเข้า Telegram เรียบร้อยแล้ว${NC}"
    fi
fi

if [ "$1" != "silent" ]; then
    clear
    echo -e "${YELLOW}================= สำรองข้อมูลสำเร็จ (BACKUP) =================${NC}"
    echo -e "ไฟล์สำรองในเครื่อง : ${GREEN}/root/${ZIP_NAME}${NC}"
    echo -e "ลิงก์สำหรับดึงย้ายเครื่อง : ${CYAN}http://${MYIP}:8081/${ZIP_NAME}${NC}"
    echo -e "สถานะ Telegram : ${TELE_STAT}"
    echo -e "${YELLOW}------------------------------------------------------------${NC}"
    echo -e "วิธีใช้งาน: นำลิงก์ด้านบนไปวางในเมนู [30] ของเซิร์ฟเวอร์เครื่องใหม่ได้เลย"
    echo -e "${YELLOW}============================================================${NC}"
fi
EOF
chmod +x /usr/bin/backup-vpn

cat << 'EOF' > /usr/bin/restore-vpn
#!/bin/bash
export TZ="Asia/Bangkok"
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${YELLOW}============= กู้คืนข้อมูลบัญชีทั้งหมด (RESTORE) =============${NC}"
echo -e "สามารถใส่ได้ทั้ง ลิงก์ตรง (http://...:8081/vpn-backup-xxx.zip)"
echo -e "หรือ พาธไฟล์ในเครื่อง (เช่น /root/vpn-backup-xxx.zip)"
echo -e "${YELLOW}------------------------------------------------------------${NC}"
read -rp "กรอกลิงก์ หรือ พาธไฟล์ Backup (.zip): " src_input

if [ -z "$src_input" ]; then
    echo -e "${RED}ยกเลิกการทำรายการ${NC}"
    exit 1
fi

RESTORE_ZIP="/tmp/restore_target.zip"
RESTORE_DIR="/tmp/vpn_restore_data"
rm -rf "$RESTORE_ZIP" "$RESTORE_DIR"

case "$src_input" in
    http*)
        echo -e "${CYAN}กำลังดาวน์โหลดไฟล์สำรองข้อมูล...${NC}"
        wget -q -O "$RESTORE_ZIP" "$src_input"
        ;;
    *)
        if [ -f "$src_input" ]; then
            cp "$src_input" "$RESTORE_ZIP"
        fi
        ;;
esac

if [ ! -s "$RESTORE_ZIP" ]; then
    echo -e "${RED}ไม่พบไฟล์สำรองข้อมูล หรือดาวน์โหลดไม่สำเร็จ!${NC}"
    exit 1
fi

mkdir -p "$RESTORE_DIR"
unzip -q "$RESTORE_ZIP" -d "$RESTORE_DIR"

if [ -f "$RESTORE_DIR/ssh-users.txt" ]; then
    while IFS='|' read -r u hash exp; do
        if [ -n "$u" ] && [ -n "$hash" ]; then
            if ! id "$u" >/dev/null 2>&1; then
                useradd -s /bin/false -M "$u" 2>/dev/null
            fi
            usermod -p "$hash" "$u" 2>/dev/null
            if [ "$exp" != "never" ] && [ -n "$exp" ]; then
                s_exp=$(date -d "$exp + 1 day" +%Y-%m-%d 2>/dev/null || echo "$exp")
                chage -E "$s_exp" "$u" 2>/dev/null
                usermod -e "$s_exp" "$u" 2>/dev/null
            fi
        fi
    done < "$RESTORE_DIR/ssh-users.txt"
fi

mkdir -p /etc/xray /usr/local/etc/xray /var/log/xray
if [ ! -s /usr/local/bin/xray ]; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
    chmod +x /usr/local/bin/xray 2>/dev/null
fi
if [ -f "$RESTORE_DIR/xray/config.json" ]; then
    if jq . "$RESTORE_DIR/xray/config.json" >/dev/null 2>&1; then
        cp -f "$RESTORE_DIR/xray/config.json" /etc/xray/config.json
    else
        echo -e "${RED}Warning: config.json from Backup is Invalid JSON!${NC}"
    fi
fi
if [ ! -s /etc/xray/config.json ] || ! jq . /etc/xray/config.json >/dev/null 2>&1; then
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    cat <<JSON > /etc/xray/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "email": "default"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "email": "default"
          }
        ],
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
      "protocol": "freedom"
    }
  ]
}
JSON
fi
[ -f "$RESTORE_DIR/xray/xray-exp.txt" ] && cp -f "$RESTORE_DIR/xray/xray-exp.txt" /etc/xray/xray-exp.txt
[ -f "$RESTORE_DIR/xray/xray-lock.txt" ] && cp -f "$RESTORE_DIR/xray/xray-lock.txt" /etc/xray/xray-lock.txt
[ -f "$RESTORE_DIR/xray/trial-exp.txt" ] && cp -f "$RESTORE_DIR/xray/trial-exp.txt" /etc/xray/trial-exp.txt
[ -f "$RESTORE_DIR/xray/ssh-pass.txt" ] && cp -f "$RESTORE_DIR/xray/ssh-pass.txt" /etc/xray/ssh-pass.txt
[ -f "$RESTORE_DIR/xray/limit-ssh" ] && cp -f "$RESTORE_DIR/xray/limit-ssh" /etc/xray/limit-ssh
[ -f "$RESTORE_DIR/xray/warp-domains.txt" ] && cp -f "$RESTORE_DIR/xray/warp-domains.txt" /etc/xray/warp-domains.txt
[ -f "$RESTORE_DIR/xray/warp.conf" ] && cp -f "$RESTORE_DIR/xray/warp.conf" /etc/xray/warp.conf
if [ -d "$RESTORE_DIR/xray/warp" ]; then
    mkdir -p /etc/xray/warp
    cp -rf "$RESTORE_DIR/xray/warp/." /etc/xray/warp/ 2>/dev/null
fi
if [ -x /usr/bin/warp-route ] && [ -s /etc/xray/warp/warp.json ]; then
    /usr/bin/warp-route apply --no-restart >/dev/null 2>&1
fi

touch /var/log/xray/access.log /var/log/xray/error.log
chmod -R 777 /var/log/xray
chown -R root:root /var/log/xray /etc/xray /usr/local/etc/xray 2>/dev/null
rm -f /usr/local/etc/xray/config.json
ln -sf /etc/xray/config.json /usr/local/etc/xray/config.json 2>/dev/null
rm -rf /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d
if [ -f /etc/systemd/system/xray.service ] && ! grep -q "warp-route ipt-apply" /etc/systemd/system/xray.service 2>/dev/null; then
    cat << 'XSVC' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
ExecStartPost=-/bin/bash -c 'sleep 1; [ -x /usr/bin/warp-route ] && /usr/bin/warp-route ipt-apply >/dev/null 2>&1 || true'
ExecStopPost=-/bin/bash -c '[ -x /usr/bin/warp-route ] && /usr/bin/warp-route ipt-clear >/dev/null 2>&1 || true'
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
XSVC
fi
killall -9 xray 2>/dev/null || true

mkdir -p /etc/zivpn
[ -f "$RESTORE_DIR/zivpn/config.json" ] && cp -f "$RESTORE_DIR/zivpn/config.json" /etc/zivpn/config.json
[ -f "$RESTORE_DIR/zivpn/zivpn-exp.txt" ] && cp -f "$RESTORE_DIR/zivpn/zivpn-exp.txt" /etc/zivpn/zivpn-exp.txt
[ -f "$RESTORE_DIR/zivpn/zivpn-users.txt" ] && cp -f "$RESTORE_DIR/zivpn/zivpn-users.txt" /etc/zivpn/zivpn-users.txt

mkdir -p /etc/hysteria
if [ -f "$RESTORE_DIR/hysteria/hys-users.txt" ]; then
    cp -f "$RESTORE_DIR/hysteria/hys-users.txt" /etc/hysteria/hys-users.txt
    /usr/bin/rebuild-hysteria
fi

if [ -f "$RESTORE_DIR/api/api_ssh.php" ]; then
    SAVED_RESTORE_KEY=$(grep '$secret_key =' "$RESTORE_DIR/api/api_ssh.php" | cut -d'"' -f2)
    if [ -n "$SAVED_RESTORE_KEY" ]; then
        mkdir -p /home/vps/public_html /root/vnext_api
        sed -i "s/\$secret_key = \".*\";/\$secret_key = \"${SAVED_RESTORE_KEY}\";/g" /home/vps/public_html/api_ssh.php
        cp -f /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php
        chown -R www-data:www-data /home/vps/public_html
        chmod -R 755 /home/vps/public_html
    fi
fi

rm -rf "$RESTORE_ZIP" "$RESTORE_DIR"
systemctl daemon-reload
cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem 2>/dev/null
chmod 600 /etc/stunnel/stunnel.pem 2>/dev/null
systemctl restart ssh dropbear stunnel4 xray zivpn hysteria udp-custom nginx >/dev/null 2>&1

echo -e "${GREEN}กู้คืนข้อมูลบัญชีทั้งหมด (SSH, UDP Custom, Xray, ZIVPN, Hysteria 2 และ API) เรียบร้อยแล้ว!${NC}"
EOF
chmod +x /usr/bin/restore-vpn

if [ ! -f /etc/cron.d/vpn-cron ]; then
cat <<EOF > /etc/cron.d/vpn-cron
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
* * * * * root /usr/bin/tendang
0 */6 * * * root /usr/bin/clear-log
0 3 * * * root /sbin/reboot
EOF
fi
systemctl restart cron

# 16. สร้างคำสั่งเช็กสถานะ 'running'
cat << 'EOF' > /usr/bin/running
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

check_status() {
    if systemctl is-active --quiet "$1"; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

TorrentRules=$(iptables -L OUTPUT -n | grep -c "BitTorrent")
if [ "$TorrentRules" -gt 0 ]; then
    TORRENT_STAT="${GREEN}[ACTIVE]${NC}"
else
    TORRENT_STAT="${RED}[INACTIVE]${NC}"
fi

if netstat -tunlp | grep -q ":8081 "; then
    API_STAT="${GREEN}[ON]${NC}"
else
    API_STAT="${RED}[OFF]${NC}"
fi

REBOOT_STAT=$(cat /etc/xray/autoreboot-status 2>/dev/null)
[ -z "$REBOOT_STAT" ] && REBOOT_STAT="เปิดใช้งาน (03:00 น.)"

clear
echo -e "${YELLOW}=========================================${NC}"
echo -e "           ${CYAN}STATUS RUNNING SERVICE${NC}"
echo -e "${YELLOW}=========================================${NC}"
echo -e " OpenSSH Service          : $(check_status ssh)"
echo -e " Dropbear Service         : $(check_status dropbear)"
echo -e " Stunnel4 (443/444/777)   : $(check_status stunnel4)"
echo -e " Nginx Proxy (80 / 443)   : $(check_status nginx)"
echo -e " Web Panel & API (8081)   : ${API_STAT}"
echo -e " Xray Core (Vmess/Vless)  : $(check_status xray)"
echo -e " UDP Custom (Port 7200)   : $(check_status udp-custom)"
echo -e " BadVPN UDPGW (Port 7300) : $(check_status udpgw@7300)"
echo -e " ZIVPN UDP (5667/6000+)   : $(check_status zivpn)"
echo -e " Hysteria 2 (8443/20000+) : $(check_status hysteria)"
echo -e " SSH WebSocket (10015)    : $(check_status ws-epro)"
echo -e " Fail2Ban (Anti-Brute)    : $(check_status fail2ban)"
echo -e " Anti-Torrent Firewall    : ${TORRENT_STAT}"
echo -e " Cron (Auto-Kill / Exp)   : $(check_status cron)"
echo -e " Auto-Reboot Schedule     : ${GREEN}${REBOOT_STAT}${NC}"
echo -e "${YELLOW}=========================================${NC}"
EOF
chmod +x /usr/bin/running

# 17. สร้างคำสั่งหน้าหลัก 'menu'
cat << 'EOF' > /usr/bin/menu
#!/bin/bash
export TZ="Asia/Bangkok"
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

MYIP=$(curl -sS ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null)
[ -z "$DOMAIN" ] && DOMAIN="$MYIP"
MAX_LOGIN=$(cat /etc/xray/limit-ssh 2>/dev/null)
[ -z "$MAX_LOGIN" ] && MAX_LOGIN="2"
REBOOT_STAT=$(cat /etc/xray/autoreboot-status 2>/dev/null)
[ -z "$REBOOT_STAT" ] && REBOOT_STAT="เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)"
RAM_USAGE=$(free -m | awk 'NR==2{printf "%s/%s MB (%.1f%%)", $3,$2,$3*100/$2 }')
mkdir -p /etc/xray /etc/zivpn /etc/hysteria
touch /etc/xray/xray-exp.txt /etc/xray/xray-lock.txt /etc/xray/trial-exp.txt /etc/xray/ssh-pass.txt /etc/zivpn/zivpn-exp.txt /etc/zivpn/zivpn-users.txt /etc/hysteria/hys-users.txt

clear
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
echo -e "               ${CYAN}PRIVATE VPN MENU${NC}"
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
echo -e " IP Address  : ${GREEN}${MYIP}${NC}"
echo -e " Domain      : ${GREEN}${DOMAIN}${NC}"
echo -e " Web Panel   : ${CYAN}http://${DOMAIN}:8081${NC}"
echo -e " RAM Usage   : ${GREEN}${RAM_USAGE}${NC}"
echo -e " Multi-Login : ${GREEN}สูงสุด ${MAX_LOGIN} เครื่อง/บัญชี${NC}"
echo -e " Auto-Reboot : ${GREEN}${REBOOT_STAT}${NC}"
echo -e "${YELLOW}☉—————— [ จัดการบัญชี SSH / ZIVPN / HYS2 ] ——————☉${NC}"
echo -e " [1]  สร้างบัญชี All-in-One (SSH + UDP Custom + ZIVPN + Hys2)"
echo -e " [2]  ต่ออายุบัญชี All-in-One (Renew)"
echo -e " [3]  ระงับ / ปลดล็อกบัญชี SSH (Lock/Unlock)"
echo -e " [4]  ลบบัญชี All-in-One (Delete)"
echo -e " [5]  ดูรายชื่อบัญชี SSH ทั้งหมด"
echo -e "${YELLOW}☉——————————— [ จัดการบัญชี XRAY CORE ] ——————————☉${NC}"
echo -e " [6]  สร้างบัญชี Xray (Vmess & Vless)"
echo -e " [7]  ต่ออายุบัญชี Xray (Renew)"
echo -e " [8]  ระงับ / ปลดล็อกบัญชี Xray (Lock/Unlock)"
echo -e " [9]  ลบบัญชี Xray (Vmess & Vless)"
echo -e " [10] ดูรายชื่อบัญชี Xray และขอดูลิงก์ย้อนหลัง"
echo -e "${YELLOW}☉——————————— [ จัดการบัญชี ZIVPN UDP ] ——————————☉${NC}"
echo -e " [11] สร้างรหัสผ่าน ZIVPN UDP แยกเฉพาะ"
echo -e " [12] ต่ออายุรหัสผ่าน ZIVPN UDP (Renew)"
echo -e " [13] ลบรหัสผ่าน ZIVPN UDP (Delete)"
echo -e " [14] ดูรหัสผ่าน ZIVPN UDP ทั้งหมด"
echo -e "${YELLOW}☉——————————— [ จัดการบัญชี HYSTERIA 2 ] —————————☉${NC}"
echo -e " [15] สร้างบัญชี Hysteria 2 แยกเฉพาะ"
echo -e " [16] ต่ออายุบัญชี Hysteria 2 (Renew)"
echo -e " [17] ลบบัญชี Hysteria 2 (Delete)"
echo -e " [18] ดูรายชื่อบัญชี Hysteria 2 และขอดูลิงก์เชื่อมต่อ"
echo -e "${YELLOW}☉—————— [ ความปลอดภัย / บำรุงรักษา / สำรองข้อมูล ] —————☉${NC}"
echo -e " [19] เช็กผู้ใช้ออนไลน์ (SSH / Dropbear / Xray)"
echo -e " [20] ตั้งค่าจำกัดจำนวนเครื่องล็อกอิน (Auto-Kill)"
echo -e " [21] เปลี่ยนโดเมนและขอ SSL ใหม่ (Port 443)"
echo -e " [22] เช็กสถานะบริการและไฟร์วอลล์ (running)"
echo -e " [23] รีสตาร์ทบริการทั้งหมด"
echo -e " [24] ลบบัญชีที่หมดอายุทันที (เคลียร์ขยะบัญชี)"
echo -e " [25] ล้างไฟล์ขยะ Log และเคลียร์ RAM ทันที"
echo -e " [26] ตั้งเวลา Auto-Reboot เซิร์ฟเวอร์อัตโนมัติ"
echo -e " [27] อัปเดตสคริปต์และเมนูเวอร์ชันล่าสุดจาก GitHub"
echo -e " [28] ดูข้อมูลเชื่อมต่อ Web Panel & API (Port 8081)"
echo -e " [29] สำรองข้อมูลบัญชีทั้งหมด (Backup & Telegram Bot)"
echo -e " [30] กู้คืนข้อมูลบัญชีทั้งหมด (Restore ย้ายเซิร์ฟเวอร์)"
echo -e " [31] ทดสอบความเร็วอินเทอร์เน็ตเซิร์ฟเวอร์ (Speedtest by Ookla)"
echo -e " [32] จัดการ WARP Split-Routing (แยกโดเมนออก WARP สำหรับ SSH + Xray)"
echo -e " [0]  ออกจากเมนู"
echo -e "${YELLOW}☉———————————————————————————————————————————————☉${NC}"
read -rp "เลือกเมนู [0-32]: " opt

case $opt in
    1)
        read -rp "ชื่อผู้ใช้ (Username): " user
        if id "$user" >/dev/null 2>&1; then
            echo -e "${RED}ชื่อผู้ใช้นี้มีอยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "รหัสผ่าน (Password): " pass
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")
        /usr/bin/api-vpn add "$user" "$pass" "$exp"
        if ! id "$user" >/dev/null 2>&1; then
            echo -e "${RED}สร้างบัญชีไม่สำเร็จ! ระบบติดล็อก กรุณาลองใหม่อีกครั้ง${NC}"
            exit 1
        fi
        pass_enc=$(echo -n "$pass" | jq -sRr @uri)
        HYS_LINK="hysteria2://${pass_enc}@${DOMAIN}:8443/?insecure=1&sni=${DOMAIN}#${user}-Hysteria2"
        HYS_HOP="hysteria2://${pass_enc}@${DOMAIN}:20000/?insecure=1&sni=${DOMAIN}&mport=20000-50000#${user}-Hys2-Hopping"
        clear
        echo -e "${YELLOW}=== ข้อมูลบัญชี SSH, UDP Custom, ZIVPN & Hysteria 2 ===${NC}"
        echo -e "Host/IP      : $DOMAIN ($MYIP)"
        echo -e "Username     : $user"
        echo -e "Password     : $pass"
        echo -e "OpenSSH      : 22 | Dropbear : 109, 143"
        echo -e "Stunnel4 SSL : 443, 444, 777 (พอร์ตภายใน 10443)"
        echo -e "WS Port      : 80 | WS TLS   : 443"
        echo -e "UDP Custom   : 1-5999, 50001-65535 (พอร์ตภายใน 7200)"
        echo -e "BadVPN UDPGW : 7100, 7300"
        echo -e "ZIVPN UDP    : 5667, 6000-19999 (ใช้รหัส $pass)"
        echo -e "Hysteria 2   : 8443, 20000-50000 (ใช้รหัส $pass)"
        echo -e "Payload WS   : GET /ssh-ws HTTP/1.1[crlf]Host: ${DOMAIN}[crlf]Upgrade: websocket[crlf][crlf]"
        echo -e "หมดอายุวันที่   : ${exp}"
        echo -e "${YELLOW}----------------------------------------------------${NC}"
        echo -e "${CYAN}[ลิงก์เชื่อมต่อ Hysteria 2 แบบ Port Hopping (20000-50000)]${NC}"
        echo -e "${HYS_HOP}"
        echo -e "${YELLOW}====================================================${NC}"
        ;;
    2)
        read -rp "พิมพ์ชื่อบัญชีที่ต้องการต่ออายุ: " user
        if ! id "$user" >/dev/null 2>&1; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        exp_old=$(grep "^${user}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f3 | tail -n 1)
        if [ -z "$exp_old" ]; then
            exp_old=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
        fi
        today_sec=$(date +%s)
        exp_sec=$(date -d "$exp_old" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$exp_old" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        /usr/bin/api-vpn renew "$user" "" "$new_exp"
        echo -e "${GREEN}ต่ออายุบัญชี ${user} (SSH + UDP Custom + ZIVPN + Hysteria 2) สำเร็จ! หมดอายุ: ${new_exp}${NC}"
        ;;
    3)
        echo -e " [1] ระงับบัญชีชั่วคราว (Lock)"
        echo -e " [2] ปลดล็อกบัญชี (Unlock)"
        read -rp "เลือกทำรายการ [1-2]: " lopt
        read -rp "พิมพ์ชื่อบัญชี SSH: " user
        if ! id "$user" >/dev/null 2>&1; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        if [ "$lopt" = "1" ]; then
            passwd -l "$user" >/dev/null 2>&1
            killall -u "$user" 2>/dev/null
            echo -e "${YELLOW}ระงับการใช้งานและตัดการเชื่อมต่อบัญชี ${user} เรียบร้อยแล้ว!${NC}"
        elif [ "$lopt" = "2" ]; then
            passwd -u "$user" >/dev/null 2>&1
            echo -e "${GREEN}ปลดล็อกบัญชี ${user} ให้กลับมาใช้งานได้ตามปกติแล้ว!${NC}"
        fi
        ;;
    4)
        read -rp "พิมพ์ชื่อบัญชีที่ต้องการลบ: " delssh
        if id "$delssh" >/dev/null 2>&1; then
            /usr/bin/api-vpn delete "$delssh" "" ""
            echo -e "${GREEN}ลบบัญชี ${delssh} ออกจากทั้ง SSH, UDP Custom, ZIVPN และ Hysteria 2 เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบชื่อบัญชี ${delssh} ในระบบ!${NC}"
        fi
        ;;
    5)
        clear
        echo -e "${YELLOW}========= รายชื่อบัญชี SSH ทั้งหมด =========${NC}"
        printf "%-18s %-20s %s\n" "Username" "Expire Date" "Status"
        echo -e "---------------------------------------------------"
        for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | tac); do
            texp=$(grep "^${user}:" /etc/xray/trial-exp.txt 2>/dev/null | cut -d: -f2 | tail -n 1)
            if [ -n "$texp" ]; then
                exp=$(date -d "@$texp" "+%Y-%m-%d %H:%M")
            else
                exp=$(grep "^${user}:" /etc/hysteria/hys-users.txt 2>/dev/null | cut -d: -f3 | tail -n 1)
                [ -z "$exp" ] && exp=$(chage -l "$user" | grep "Account expires" | awk -F": " '{print $2}')
            fi
            passwd_stat=$(passwd -S "$user" 2>/dev/null | awk '{print $2}')
            if [ "$passwd_stat" = "L" ]; then
                stat="${RED}Locked${NC}"
            else
                stat="${GREEN}Active${NC}"
            fi
            printf "%-18s %-20s %b\n" "$user" "$exp" "$stat"
        done
        echo -e "${YELLOW}=========================================${NC}"
        ;;
    6)
        read -rp "ตั้งชื่อบัญชี Xray (ห้ามซ้ำ): " user
        if [ -z "$user" ]; then
            echo -e "${RED}ชื่อบัญชีห้ามเว้นว่าง!${NC}"
            exit 1
        fi
        if grep -q "^${user}:" /etc/xray/xray-exp.txt; then
            echo -e "${RED}มีชื่อบัญชีนี้อยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")
        UUID=$(cat /proc/sys/kernel/random/uuid)

        (
            flock -x 200
            XTMP=$(mktemp /tmp/xray_cfg.XXXXXX.json 2>/dev/null || echo "/tmp/xray_tmp.json")
            jq --arg u "$user" --arg id "$UUID" \
               '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] |
                .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' \
               /etc/xray/config.json > "$XTMP" && mv "$XTMP" /etc/xray/config.json
            echo "$user:$exp" >> /etc/xray/xray-exp.txt
        ) 200>/var/lock/xray-config.lock
        systemctl restart xray

        VMESS_TLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${user}-TLS","add":"${DOMAIN}","port":"443","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"tls"}
JSON
)
        VMESS_NTLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${user}-HTTP","add":"${DOMAIN}","port":"80","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"none"}
JSON
)
        VLESS_TLS="vless://${UUID}@${DOMAIN}:443?path=%2Fvless&security=tls&encryption=none&type=ws&host=${DOMAIN}&sni=${DOMAIN}#${user}-TLS"
        VLESS_NTLS="vless://${UUID}@${DOMAIN}:80?path=%2Fvless&security=none&encryption=none&type=ws&host=${DOMAIN}#${user}-HTTP"

        clear
        echo -e "${YELLOW}====== ข้อมูลบัญชี Xray (Vmess / Vless) ======${NC}"
        echo -e "ชื่อบัญชี        : ${GREEN}${user}${NC}"
        echo -e "Host / Domain : ${GREEN}${DOMAIN}${NC}"
        echo -e "Port TLS/HTTP : 443 / 80"
        echo -e "UUID          : ${GREEN}${UUID}${NC}"
        echo -e "หมดอายุวันที่     : ${GREEN}${exp} (${days} วัน)${NC}"
        echo -e "${YELLOW}-------------------------------------------${NC}"
        echo -e "${CYAN}[ลิงก์ Vmess SSL/TLS (Port 443)]${NC}\nvmess://${VMESS_TLS}\n"
        echo -e "${CYAN}[ลิงก์ Vmess HTTP (Port 80)]${NC}\nvmess://${VMESS_NTLS}\n"
        echo -e "${CYAN}[ลิงก์ Vless SSL/TLS (Port 443)]${NC}\n${VLESS_TLS}\n"
        echo -e "${CYAN}[ลิงก์ Vless HTTP (Port 80)]${NC}\n${VLESS_NTLS}\n"
        echo -e "${YELLOW}===========================================${NC}"
        ;;
    7)
        read -rp "พิมพ์ชื่อบัญชี Xray ที่ต้องการต่ออายุ: " user
        old_exp=$(grep "^${user}:" /etc/xray/xray-exp.txt | cut -d: -f2)
        if [ -z "$old_exp" ]; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        sed -i "s/^${user}:${old_exp}/${user}:${new_exp}/g" /etc/xray/xray-exp.txt
        echo -e "${GREEN}ต่ออายุบัญชี Xray: ${user} สำเร็จ! วันหมดอายุใหม่คือ: ${new_exp}${NC}"
        ;;
    8)
        echo -e " [1] ระงับบัญชี Xray ชั่วคราว (Lock)"
        echo -e " [2] ปลดล็อกบัญชี Xray (Unlock)"
        read -rp "เลือกทำรายการ [1-2]: " xlopt
        read -rp "พิมพ์ชื่อบัญชี Xray: " user
        if ! grep -q "^${user}:" /etc/xray/xray-exp.txt; then
            echo -e "${RED}ไม่พบชื่อบัญชี ${user} ในระบบ!${NC}"
            exit 1
        fi
        if [ "$xlopt" = "1" ]; then
            if grep -q "^${user}:" /etc/xray/xray-lock.txt; then
                echo -e "${YELLOW}บัญชีนี้ถูกระงับอยู่แล้ว!${NC}"
                exit 1
            fi
            uuid=$(jq -r --arg u "$user" '.inbounds[0].settings.clients[] | select(.email == $u) | .id' /etc/xray/config.json)
            echo "${user}:${uuid}" >> /etc/xray/xray-lock.txt
            jq --arg u "$user" \
               '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            systemctl restart xray
            echo -e "${YELLOW}ระงับการใช้งานบัญชี Xray: ${user} ชั่วคราวเรียบร้อยแล้ว!${NC}"
        elif [ "$xlopt" = "2" ]; then
            uuid=$(grep "^${user}:" /etc/xray/xray-lock.txt | cut -d: -f2)
            if [ -z "$uuid" ]; then
                echo -e "${RED}บัญชีนี้ไม่ได้อยู่ในสถานะถูกระงับ!${NC}"
                exit 1
            fi
            jq --arg u "$user" --arg id "$uuid" \
               '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] |
                .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' \
               /etc/xray/config.json > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json /etc/xray/config.json
            sed -i "/^${user}:/d" /etc/xray/xray-lock.txt
            systemctl restart xray
            echo -e "${GREEN}ปลดล็อกบัญชี Xray: ${user} (UUID เดิม) เรียบร้อยแล้ว!${NC}"
        fi
        ;;
    9)
        read -rp "พิมพ์ชื่อบัญชี Xray ที่ต้องการลบถาวร: " deluser
        if [ "$deluser" = "default" ]; then
            echo -e "${RED}ไม่สามารถลบบัญชีเริ่มต้น (default) ได้!${NC}"
            exit 1
        fi
        (
            flock -x 200
            XTMP=$(mktemp /tmp/xray_cfg.XXXXXX.json 2>/dev/null || echo "/tmp/xray_tmp.json")
            jq --arg u "$deluser" \
               '(.inbounds[0].settings.clients) |= map(select(.email != $u)) |
                (.inbounds[1].settings.clients) |= map(select(.email != $u))' \
               /etc/xray/config.json > "$XTMP" && mv "$XTMP" /etc/xray/config.json
            sed -i "/^$deluser:/d" /etc/xray/xray-exp.txt
            sed -i "/^$deluser:/d" /etc/xray/xray-lock.txt 2>/dev/null
        ) 200>/var/lock/xray-config.lock
        systemctl restart xray
        echo -e "${GREEN}ลบบัญชี ${deluser} ถาวรเรียบร้อยแล้ว!${NC}"
        ;;
    10)
        clear
        echo -e "${YELLOW}================= รายชื่อบัญชี Xray ทั้งหมด =================${NC}"
        printf "%-15s %-15s %-12s %s\n" "Username" "Expire Date" "Status" "UUID"
        echo -e "------------------------------------------------------------"
        if [ -s /etc/xray/xray-exp.txt ]; then
            while IFS=':' read -r u exp; do
                if grep -q "^${u}:" /etc/xray/xray-lock.txt; then
                    uuid=$(grep "^${u}:" /etc/xray/xray-lock.txt | cut -d: -f2)
                    stat="${RED}Locked${NC}"
                else
                    uuid=$(jq -r --arg usr "$u" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json)
                    stat="${GREEN}Active${NC}"
                fi
                printf "%-15s %-15s %-21b %s\n" "$u" "$exp" "$stat" "$uuid"
            done < /etc/xray/xray-exp.txt
        else
            echo "ยังไม่มีการสร้างบัญชี Xray ในระบบ"
        fi
        echo -e "${YELLOW}============================================================${NC}"
        read -rp "ต้องการดูลิงก์เชื่อมต่อของบัญชีใดไหมครับ? (พิมพ์ชื่อบัญชี หรือกด Enter เพื่อข้าม): " showuser
        if [ -n "$showuser" ]; then
            UUID=$(jq -r --arg usr "$showuser" '.inbounds[0].settings.clients[] | select(.email == $usr) | .id' /etc/xray/config.json)
            if [ -z "$UUID" ]; then
                UUID=$(grep "^${showuser}:" /etc/xray/xray-lock.txt | cut -d: -f2)
            fi
            if [ -n "$UUID" ]; then
                VMESS_TLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${showuser}-TLS","add":"${DOMAIN}","port":"443","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"tls"}
JSON
)
                VMESS_NTLS=$(cat <<JSON | base64 -w 0
{"v":"2","ps":"${showuser}-HTTP","add":"${DOMAIN}","port":"80","id":"${UUID}","aid":"0","net":"ws","path":"/vmess","type":"none","host":"${DOMAIN}","tls":"none"}
JSON
)
                VLESS_TLS="vless://${UUID}@${DOMAIN}:443?path=%2Fvless&security=tls&encryption=none&type=ws&host=${DOMAIN}&sni=${DOMAIN}#${showuser}-TLS"
                VLESS_NTLS="vless://${UUID}@${DOMAIN}:80?path=%2Fvless&security=none&encryption=none&type=ws&host=${DOMAIN}#${showuser}-HTTP"
                echo -e "\n${CYAN}[ลิงก์ Vmess SSL/TLS (443)]${NC}\nvmess://${VMESS_TLS}\n"
                echo -e "${CYAN}[ลิงก์ Vmess HTTP (80)]${NC}\nvmess://${VMESS_NTLS}\n"
                echo -e "${CYAN}[ลิงก์ Vless SSL/TLS (443)]${NC}\n${VLESS_TLS}\n"
                echo -e "${CYAN}[ลิงก์ Vless HTTP (80)]${NC}\n${VLESS_NTLS}\n"
            else
                echo -e "${RED}ไม่พบบัญชี ${showuser}${NC}"
            fi
        fi
        ;;
    11)
        read -rp "กำหนดรหัสผ่าน (udp password) [กด Enter เพื่อสุ่มอัตโนมัติ 8 หลัก]: " zpass
        if [ -z "$zpass" ]; then
            zpass=$(openssl rand -hex 4)
        fi
        if grep -q "^${zpass}:" /etc/zivpn/zivpn-exp.txt; then
            echo -e "${RED}รหัสผ่านนี้มีอยู่ในระบบแล้ว!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")

        jq --arg p "$zpass" '.auth.config += [$p] | .auth.config |= unique' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
        echo "${zpass}:${exp}" >> /etc/zivpn/zivpn-exp.txt
        systemctl restart zivpn

        clear
        echo -e "${YELLOW}====== ข้อมูลการเชื่อมต่อ ZIVPN (UDP Tunnel) ======${NC}"
        echo -e "Receive window : ${GREEN}3 (หรือค่าเริ่มต้น)${NC}"
        echo -e "udp server     : ${GREEN}${DOMAIN}${NC} (หรือ ${MYIP})"
        echo -e "udp password   : ${GREEN}${zpass}${NC}"
        echo -e "Port Range     : 5667, 6000-19999 (UDP)"
        echo -e "หมดอายุวันที่     : ${GREEN}${exp} (${days} วัน)${NC}"
        echo -e "${YELLOW}=================================================${NC}"
        ;;
    12)
        read -rp "พิมพ์รหัสผ่าน ZIVPN (udp password) ที่ต้องการต่ออายุ: " zpass
        old_exp=$(grep "^${zpass}:" /etc/zivpn/zivpn-exp.txt | cut -d: -f2)
        if [ -z "$old_exp" ]; then
            echo -e "${RED}ไม่พบรหัสผ่าน ${zpass} ในระบบ!${NC}"
            exit 1
        fi
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        sed -i "s/^${zpass}:${old_exp}/${zpass}:${new_exp}/g" /etc/zivpn/zivpn-exp.txt
        echo -e "${GREEN}ต่ออายุรหัสผ่าน ZIVPN: ${zpass} สำเร็จ! วันหมดอายุใหม่คือ: ${new_exp}${NC}"
        ;;
    13)
        read -rp "พิมพ์รหัสผ่าน ZIVPN (udp password) ที่ต้องการลบ: " delpass
        if grep -q "^${delpass}:" /etc/zivpn/zivpn-exp.txt; then
            jq --arg p "$delpass" '.auth.config -= [$p]' /etc/zivpn/config.json > /tmp/zivpn_tmp.json && mv /tmp/zivpn_tmp.json /etc/zivpn/config.json
            sed -i "/^${delpass}:/d" /etc/zivpn/zivpn-exp.txt
            sed -i "/:${delpass}$/d" /etc/zivpn/zivpn-users.txt 2>/dev/null
            systemctl restart zivpn
            echo -e "${GREEN}ลบรหัสผ่าน ZIVPN: ${delpass} เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบรหัสผ่าน ${delpass} ในระบบ!${NC}"
        fi
        ;;
    14)
        clear
        echo -e "${YELLOW}========= รายชื่อรหัสผ่าน ZIVPN UDP ทั้งหมด =========${NC}"
        echo -e "UDP Server : ${GREEN}${DOMAIN}${NC} (${MYIP})"
        echo -e "------------------------------------------------------------"
        printf "%-20s %-18s %-15s %s\n" "UDP Password" "Owner (SSH User)" "Expire Date" "Status"
        echo -e "------------------------------------------------------------"
        if [ -s /etc/zivpn/zivpn-exp.txt ]; then
            while IFS=':' read -r zp zexp; do
                owner=$(grep ":${zp}$" /etc/zivpn/zivpn-users.txt 2>/dev/null | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
                [ -z "$owner" ] && owner="-"
                printf "%-20s %-18s %-15s %b\n" "$zp" "$owner" "$zexp" "${GREEN}Active${NC}"
            done < /etc/zivpn/zivpn-exp.txt
        else
            echo "ยังไม่มีการสร้างรหัสผ่าน ZIVPN ในระบบ"
        fi
        echo -e "${YELLOW}============================================================${NC}"
        ;;
    15)
        read -rp "ตั้งชื่อผู้ใช้สำหรับบันทึกในระบบ (Username): " huser
        if grep -q "^${huser}:" /etc/hysteria/hys-users.txt; then
            echo -e "${RED}มีชื่อผู้ใช้นี้ในระบบ Hysteria 2 แล้ว!${NC}"
            exit 1
        fi
        read -rp "ตั้งรหัสผ่าน (Password) [กด Enter เพื่อสุ่ม 8 หลัก]: " hpass
        [ -z "$hpass" ] && hpass=$(openssl rand -hex 4)
        read -rp "จำนวนวันที่ใช้งาน (เช่น 30): " days
        exp=$(date -d "$days days" +"%Y-%m-%d")

        echo "${huser}:${hpass}:${exp}" >> /etc/hysteria/hys-users.txt
        /usr/bin/rebuild-hysteria

        pass_enc=$(echo -n "$hpass" | jq -sRr @uri)
        HYS_LINK="hysteria2://${pass_enc}@${DOMAIN}:8443/?insecure=1&sni=${DOMAIN}#${huser}-Hysteria2"
        HYS_HOP="hysteria2://${pass_enc}@${DOMAIN}:20000/?insecure=1&sni=${DOMAIN}&mport=20000-50000#${huser}-Hys2-Hopping"
        clear
        echo -e "${YELLOW}====== ข้อมูลการเชื่อมต่อ Hysteria 2 (UDP QUIC) ======${NC}"
        echo -e "Host / Domain  : ${GREEN}${DOMAIN}${NC} (${MYIP})"
        echo -e "ชื่อกำกับบัญชี      : ${GREEN}${huser}${NC}"
        echo -e "Password       : ${GREEN}${hpass}${NC}"
        echo -e "Main UDP Port  : 20000 (หรือ 8443)"
        echo -e "Port Hopping   : 20000-50000 (UDP)"
        echo -e "หมดอายุวันที่     : ${GREEN}${exp} (${days} วัน)${NC}"
        echo -e "${YELLOW}----------------------------------------------------${NC}"
        echo -e "${CYAN}[ลิงก์ Hysteria 2 แบบ Port Hopping (20000-50000)]${NC}"
        echo -e "${HYS_HOP}\n"
        echo -e "${CYAN}[ลิงก์ Hysteria 2 แบบพอร์ตเดียว (Port 8443)]${NC}"
        echo -e "${HYS_LINK}"
        echo -e "${YELLOW}====================================================${NC}"
        ;;
    16)
        read -rp "พิมพ์ชื่อบัญชี Hysteria 2 ที่ต้องการต่ออายุ: " huser
        line=$(grep "^${huser}:" /etc/hysteria/hys-users.txt)
        if [ -z "$line" ]; then
            echo -e "${RED}ไม่พบบัญชี ${huser} ในระบบ Hysteria 2!${NC}"
            exit 1
        fi
        hpass=$(echo "$line" | cut -d: -f2)
        old_exp=$(echo "$line" | cut -d: -f3)
        read -rp "จำนวนวันที่ต้องการเพิ่ม (เช่น 30): " days
        today_sec=$(date +%s)
        exp_sec=$(date -d "$old_exp" +%s 2>/dev/null)
        [ -z "$exp_sec" ] && exp_sec="$today_sec"
        if [ "$exp_sec" -lt "$today_sec" ]; then
            base_date=$(date +%Y-%m-%d)
        else
            base_date=$(date -d "$old_exp" +%Y-%m-%d)
        fi
        new_exp=$(date -d "$base_date + $days days" +%Y-%m-%d)
        sed -i "/^${huser}:/d" /etc/hysteria/hys-users.txt
        echo "${huser}:${hpass}:${new_exp}" >> /etc/hysteria/hys-users.txt
        /usr/bin/rebuild-hysteria
        echo -e "${GREEN}ต่ออายุบัญชี Hysteria 2: ${huser} สำเร็จ! วันหมดอายุใหม่คือ: ${new_exp}${NC}"
        ;;
    17)
        read -rp "พิมพ์ชื่อบัญชี Hysteria 2 ที่ต้องการลบ: " delhys
        if grep -q "^${delhys}:" /etc/hysteria/hys-users.txt; then
            sed -i "/^${delhys}:/d" /etc/hysteria/hys-users.txt
            /usr/bin/rebuild-hysteria
            echo -e "${GREEN}ลบบัญชี Hysteria 2: ${delhys} เรียบร้อยแล้ว!${NC}"
        else
            echo -e "${RED}ไม่พบบัญชี ${delhys} ในระบบ!${NC}"
        fi
        ;;
    18)
        clear
        echo -e "${YELLOW}========= รายชื่อบัญชี Hysteria 2 ทั้งหมด =========${NC}"
        printf "%-18s %-18s %-15s %s\n" "Username" "Password" "Expire Date" "Status"
        echo -e "------------------------------------------------------------"
        if [ -s /etc/hysteria/hys-users.txt ]; then
            while IFS=':' read -r hu hp hexp; do
                printf "%-18s %-18s %-15s %b\n" "$hu" "$hp" "$hexp" "${GREEN}Active${NC}"
            done < /etc/hysteria/hys-users.txt
        else
            echo "ยังไม่มีการสร้างบัญชี Hysteria 2 ในระบบ"
        fi
        echo -e "${YELLOW}============================================================${NC}"
        read -rp "ต้องการดูลิงก์เชื่อมต่อของบัญชีใดไหมครับ? (พิมพ์ชื่อผู้ใช้ หรือกด Enter เพื่อข้าม): " showhys
        if [ -n "$showhys" ]; then
            hline=$(grep "^${showhys}:" /etc/hysteria/hys-users.txt)
            if [ -n "$hline" ]; then
                hp=$(echo "$hline" | cut -d: -f2)
                hp_enc=$(echo -n "$hp" | jq -sRr @uri)
                echo -e "\n${CYAN}[ลิงก์ Hysteria 2 แบบ Port Hopping (20000-50000)]${NC}"
                echo -e "hysteria2://${hp_enc}@${DOMAIN}:20000/?insecure=1&sni=${DOMAIN}&mport=20000-50000#${showhys}-Hys2-Hopping\n"
                echo -e "${CYAN}[ลิงก์ Hysteria 2 แบบพอร์ตเดียว (Port 8443)]${NC}"
                echo -e "hysteria2://${hp_enc}@${DOMAIN}:8443/?insecure=1&sni=${DOMAIN}#${showhys}-Hysteria2\n"
            else
                echo -e "${RED}ไม่พบบัญชี ${showhys}${NC}"
            fi
        fi
        ;;
    19)
        clear
        echo -e "${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ (OpenSSH / SSH-WS / UDP Custom) ===${NC}"
        printf "%-18s %-15s %s\n" "Username" "จำนวนที่เชื่อมต่อ" "PID"
        echo -e "---------------------------------------------------"
        has_online=0
        for user in $(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd); do
            pids=$(pgrep -u "$user" sshd 2>/dev/null | tr '\n' ' ')
            if [ -z "$pids" ]; then
                pids=$(ps -ef | grep -E "sshd: ${user}" | grep -v grep | awk '{print $2}' | tr '\n' ' ')
            fi
            if [ -n "$pids" ]; then
                count=$(echo "$pids" | wc -w)
                printf "%-18s %-15s %s\n" "$user" "${count} เครื่อง" "$pids"
                has_online=1
            fi
        done
        [ $has_online -eq 0 ] && echo "ไม่มีผู้ใช้ออนไลน์ผ่าน OpenSSH / SSH-WS / UDP Custom ในขณะนี้"

        echo -e "\n${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ (Dropbear Port 109/143) ===${NC}"
        db_pids=$(ps aux | grep -i dropbear | awk '{print $2}')
        has_db=0
        for pid in $db_pids; do
            db_log=$(grep -i "dropbear\[$pid\]" /var/log/auth.log 2>/dev/null | grep -i "Password auth succeeded" | tail -n 1)
            if [ -n "$db_log" ]; then
                db_user=$(echo "$db_log" | awk '{print $10}' | tr -d "'")
                printf "%-18s %-15s %s\n" "$db_user" "1 เครื่อง" "$pid"
                has_db=1
            fi
        done
        [ $has_db -eq 0 ] && echo "ไม่มีผู้ใช้ออนไลน์ผ่าน Dropbear ในขณะนี้"

        echo -e "\n${YELLOW}=== รายชื่อผู้ใช้ออนไลน์ล่าสุด (Xray Vmess/Vless) ===${NC}"
        if [ -s /var/log/xray/access.log ]; then
            xray_active=$(tail -n 300 /var/log/xray/access.log | grep "email:" | awk -F"email: " '{print $2}' | sort -u)
            if [ -n "$xray_active" ]; then
                for xusr in $xray_active; do
                    last_time=$(tail -n 300 /var/log/xray/access.log | grep "email: $xusr" | tail -n 1 | awk '{print $1, $2}')
                    echo -e "- บัญชี: ${GREEN}${xusr}${NC} (ใช้งานล่าสุด: ${last_time})"
                done
            else
                echo "ไม่มีความเคลื่อนไหวของบัญชี Xray ในช่วงเวลานี้"
            fi
        else
            echo "ยังไม่มีข้อมูลการเชื่อมต่อ Xray"
        fi

        echo -e "\n${YELLOW}=== ประวัติการเตะล็อกอินซ้อน 10 รายการล่าสุด ===${NC}"
        if [ -s /var/log/autokill.log ]; then
            tail -n 10 /var/log/autokill.log
        else
            echo "ยังไม่มีประวัติการทำผิดกฎ"
        fi
        echo -e "${YELLOW}===================================================${NC}"
        ;;
    20)
        read -rp "กำหนดจำนวนเครื่องสูงสุดต่อ 1 บัญชี (เช่น 1 หรือ 2, ใส่ 0 เพื่อปิด): " max_num
        echo "$max_num" > /etc/xray/limit-ssh
        echo -e "${GREEN}บันทึกการจำกัดล็อกอินไว้ที่ ${max_num} เครื่อง เรียบร้อยแล้ว!${NC}"
        ;;
    21)
        read -rp "กรอกโดเมนใหม่ของคุณ (ชี้ IP มายังเซิร์ฟเวอร์นี้แล้ว): " newdom
        if [ -z "$newdom" ]; then
            echo -e "${RED}ยกเลิกการทำรายการ${NC}"
            exit 1
        fi
        echo "$newdom" > /etc/xray/domain
        echo "$newdom" > /root/domain
        systemctl stop nginx
        curl https://get.acme.sh | sh -s email=admin@${newdom}
        /root/.acme.sh/acme.sh --issue -d "${newdom}" --standalone -k ec-256 --force
        /root/.acme.sh/acme.sh --installcert -d "${newdom}" \
            --fullchainpath /etc/xray/xray.crt \
            --keypath /etc/xray/xray.key --ecc
        cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem 2>/dev/null
        chmod 600 /etc/stunnel/stunnel.pem 2>/dev/null
        systemctl start nginx
        systemctl restart xray hysteria stunnel4
        echo -e "${GREEN}อัปเดตโดเมนและติดตั้ง SSL สำหรับ Xray และ Hysteria 2 เรียบร้อยแล้ว!${NC}"
        ;;
    22)
        running
        ;;
    23)
        systemctl restart rsyslog ssh dropbear stunnel4 nginx php*-fpm xray zivpn hysteria udp-custom ws-epro udpgw@7100 udpgw@7300 fail2ban cron
        echo -e "${GREEN}รีสตาร์ทบริการทั้งหมดเรียบร้อยแล้ว!${NC}"
        ;;
    24)
        echo -e "${CYAN}กำลังสแกนหาและลบบัญชีที่หมดอายุ...${NC}"
        /usr/bin/xp
        echo -e "${GREEN}เคลียร์บัญชีหมดอายุเสร็จสิ้น!${NC}"
        ;;
    25)
        echo -e "${CYAN}กำลังล้างไฟล์ Log และเคลียร์ RAM Cache...${NC}"
        BEFORE_RAM=$(free -m | awk 'NR==2{print $3}')
        /usr/bin/clear-log
        AFTER_RAM=$(free -m | awk 'NR==2{print $3}')
        echo -e "${GREEN}ล้างไฟล์ขยะและเคลียร์ RAM สำเร็จ! (RAM ที่ใช้งานลดลงจาก ${BEFORE_RAM} MB เหลือ ${AFTER_RAM} MB)${NC}"
        ;;
    26)
        echo -e "${YELLOW}=== ตั้งเวลา Auto-Reboot เซิร์ฟเวอร์อัตโนมัติ ===${NC}"
        echo -e " [1] รีบูตทุกวัน เวลา 03:00 น. (แนะนำ)"
        echo -e " [2] รีบูตทุกวัน เวลา 05:00 น."
        echo -e " [3] รีบูตทุกๆ 12 ชั่วโมง (00:00 น. และ 12:00 น.)"
        echo -e " [4] ปิดระบบ Auto-Reboot"
        read -rp "เลือกตั้งเวลา [1-4]: " rb_opt
        sed -i '/\/sbin\/reboot/d' /etc/cron.d/vpn-cron
        case $rb_opt in
            1)
                echo "0 3 * * * root /sbin/reboot" >> /etc/cron.d/vpn-cron
                echo "เปิดใช้งาน (ทุกวัน เวลา 03:00 น.)" > /etc/xray/autoreboot-status
                echo -e "${GREEN}ตั้งค่า Auto-Reboot ทุกวัน เวลา 03:00 น. เรียบร้อยแล้ว!${NC}"
                ;;
            2)
                echo "0 5 * * * root /sbin/reboot" >> /etc/cron.d/vpn-cron
                echo "เปิดใช้งาน (ทุกวัน เวลา 05:00 น.)" > /etc/xray/autoreboot-status
                echo -e "${GREEN}ตั้งค่า Auto-Reboot ทุกวัน เวลา 05:00 น. เรียบร้อยแล้ว!${NC}"
                ;;
            3)
                echo "0 */12 * * * root /sbin/reboot" >> /etc/cron.d/vpn-cron
                echo "เปิดใช้งาน (ทุกๆ 12 ชั่วโมง)" > /etc/xray/autoreboot-status
                echo -e "${GREEN}ตั้งค่า Auto-Reboot ทุกๆ 12 ชั่วโมง เรียบร้อยแล้ว!${NC}"
                ;;
            4)
                echo "ปิดใช้งาน (OFF)" > /etc/xray/autoreboot-status
                echo -e "${YELLOW}ปิดระบบ Auto-Reboot เรียบร้อยแล้ว!${NC}"
                ;;
            *)
                echo -e "${RED}ตัวเลือกไม่ถูกต้อง${NC}"
                ;;
        esac
        systemctl restart cron
        ;;
    27)
        echo -e "${CYAN}กำลังดึงไฟล์อัปเดตล่าสุดจาก GitHub (jannarong01/toeyvpn)...${NC}"
        rm -f /root/update-vpn.sh
        wget -4 -q --no-check-certificate -O /root/update-vpn.sh "https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main/ssh/ssh-vpn.sh?v=$(date +%s)"
        if [ ! -s /root/update-vpn.sh ]; then
            curl -4 -fsSL "https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main/ssh/ssh-vpn.sh?v=$(date +%s)" -o /root/update-vpn.sh 2>/dev/null
        fi
        if [ -s /root/update-vpn.sh ]; then
            sed -i 's/\r$//' /root/update-vpn.sh
            chmod +x /root/update-vpn.sh
            /root/update-vpn.sh
            rm -f /root/update-vpn.sh
            echo -e "${GREEN}อัปเดตสคริปต์และเมนูเป็นเวอร์ชันล่าสุดเรียบร้อยแล้ว!${NC}"
            exit 0
        else
            rm -f /root/update-vpn.sh
            echo -e "${RED}ไม่สามารถดาวน์โหลดไฟล์จาก GitHub ได้ กรุณาตรวจสอบลิงก์หรือการเชื่อมต่ออินเทอร์เน็ต${NC}"
            exit 1
        fi
        ;;
    28)
        CUR_KEY=$(grep '$secret_key =' /home/vps/public_html/api_ssh.php | cut -d'"' -f2)
        clear
        echo -e "${YELLOW}====== ข้อมูล Web Panel & API (Port 8081) ======${NC}"
        echo -e "เข้าหน้าเว็บจัดการ : ${CYAN}http://${DOMAIN}:8081/${NC}"
        echo -e "URL API เว็บขาย  : ${GREEN}http://${MYIP}:8081/api_ssh.php${NC}"
        echo -e "รหัสผ่าน / Key   : ${GREEN}${CUR_KEY}${NC}"
        echo -e "Path ไฟล์ระบบ   : /home/vps/public_html/"
        echo -e "${YELLOW}=================================================${NC}"
        read -rp "ต้องการเปลี่ยนรหัส Secret Key / รหัสแอดมินใหม่หรือไม่? (พิมพ์รหัสใหม่ หรือกด Enter เพื่อข้าม): " new_key
        if [ -n "$new_key" ]; then
            sed -i "s/\$secret_key = \".*\";/\$secret_key = \"${new_key}\";/g" /home/vps/public_html/api_ssh.php
            cp -f /home/vps/public_html/api_ssh.php /root/vnext_api/api_ssh.php
            echo -e "${GREEN}เปลี่ยนรหัสผ่าน Web Panel และ Secret Key เป็น ${new_key} เรียบร้อยแล้ว!${NC}"
        fi
        ;;
    29)
        clear
        echo -e "${YELLOW}====== ระบบสำรองข้อมูล (Backup & Telegram Bot) ======${NC}"
        echo -e " [1] สำรองข้อมูลทันที (สร้างไฟล์ .zip และลิงก์ย้ายเครื่อง)"
        echo -e " [2] ตั้งค่า Telegram Bot (ส่งไฟล์ Backup เข้าแชทอัตโนมัติทุกเที่ยงคืน)"
        read -rp "เลือกทำรายการ [1-2]: " b_opt
        if [ "$b_opt" = "1" ]; then
            /usr/bin/backup-vpn
        elif [ "$b_opt" = "2" ]; then
            read -rp "กรอก Telegram Bot Token: " t_token
            read -rp "กรอก Telegram Chat ID: " t_chat
            cat <<CONF > /etc/xray/tele-bot.conf
BOT_TOKEN="${t_token}"
CHAT_ID="${t_chat}"
CONF
            sed -i '/\/usr\/bin\/backup-vpn/d' /etc/cron.d/vpn-cron
            echo "5 0 * * * root /usr/bin/backup-vpn silent" >> /etc/cron.d/vpn-cron
            systemctl restart cron
            echo -e "${GREEN}บันทึกการตั้งค่า Telegram Bot และเปิดใช้งาน Auto-Backup ทุกวันเวลา 00:05 น. เรียบร้อยแล้ว!${NC}"
            /usr/bin/backup-vpn
        fi
        ;;
    30)
        /usr/bin/restore-vpn
        ;;
    31)
        clear
        echo -e "${YELLOW}====== ทดสอบความเร็วอินเทอร์เน็ตเซิร์ฟเวอร์ (Speedtest by Ookla) ======${NC}"
        if [ ! -s /usr/local/bin/speedtest ]; then
            echo -e "${CYAN}กำลังติดตั้ง Speedtest CLI...${NC}"
            ARCH=$(uname -m)
            S_ARCH="x86_64"
            if [ "$ARCH" = "aarch64" ]; then S_ARCH="aarch64"; fi
            if [ "$ARCH" = "arm64" ]; then S_ARCH="aarch64"; fi
            wget -q -O /tmp/speedtest.tgz "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${S_ARCH}.tgz"
            tar -xzf /tmp/speedtest.tgz -C /usr/local/bin speedtest 2>/dev/null
            chmod +x /usr/local/bin/speedtest
            rm -f /tmp/speedtest.tgz
        fi
        /usr/local/bin/speedtest --accept-license --accept-gdpr
        echo -e "${YELLOW}=================================================================${NC}"
        ;;
    32)
        while true; do
            clear
            WST=$(/usr/bin/warp-route status 2>/dev/null)
            W_REG=$(echo "$WST" | jq -r '.registered')
            W_XRAY=$(echo "$WST" | jq -r '.xray_on')
            W_SSH=$(echo "$WST" | jq -r '.ssh_on')
            W_QUIC=$(echo "$WST" | jq -r '.block_quic')
            W_EP=$(echo "$WST" | jq -r '.endpoint')
            W_PEND=$(echo "$WST" | jq -r '.pending')
            W_CNT=$(echo "$WST" | jq -r '.domains | length')
            echo -e "${YELLOW}========== จัดการ WARP Split-Routing (SSH + Xray) ==========${NC}"
            echo -e " สถานะบัญชี WARP   : $([ "$W_REG" = "true" ] && echo -e "${GREEN}ลงทะเบียนแล้ว${NC}" || echo -e "${RED}ยังไม่ลงทะเบียน${NC}")"
            echo -e " ใช้กับ Xray       : $([ "$W_XRAY" = "true" ] && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}") | ใช้กับ SSH : $([ "$W_SSH" = "true" ] && echo -e "${GREEN}ON${NC}" || echo -e "${RED}OFF${NC}")"
            echo -e " บล็อก QUIC (SSH)  : $([ "$W_QUIC" = "true" ] && echo -e "${GREEN}ON${NC}" || echo -e "${YELLOW}OFF${NC}") | Endpoint : ${CYAN}${W_EP}${NC}"
            echo -e " จำนวนโดเมนในรายการ : ${CYAN}${W_CNT} รายการ${NC} $([ "$W_PEND" = "true" ] && echo -e "${YELLOW}(ยังไม่บันทึก! กด 10)${NC}" || echo "")"
            echo -e "${YELLOW}------------------------------------------------------------${NC}"
            echo -e " [1]  ลงทะเบียน WARP อัตโนมัติ (wgcf)"
            echo -e " [2]  ทดสอบการเชื่อมต่อและเช็ก IP ของ WARP"
            echo -e " [3]  เปิด / ปิด การใช้งานกับ Xray (Vmess/Vless)"
            echo -e " [4]  เปิด / ปิด การใช้งานกับ SSH (OpenSSH/Dropbear)"
            echo -e " [5]  เปิด / ปิด การบล็อก QUIC (UDP 443) สำหรับ SSH"
            echo -e " [6]  เพิ่มโดเมน (เช่น youtube.com, geosite:netflix)"
            echo -e " [7]  ลบโดเมนออกจากรายการ"
            echo -e " [8]  ดูรายการโดเมนทั้งหมด"
            echo -e " [9]  เพิ่มรายการแนะนำ (TrueMoney / 7-Eleven / AIS / Netflix / YouTube)"
            echo -e " [10] บันทึกและรีสตาร์ท Xray (Apply)"
            echo -e " [11] ใส่ WARP+ License Key"
            echo -e " [12] ใส่คีย์ WireGuard เอง (โหมด Manual กรณีติด 429)"
            echo -e " [13] เปลี่ยน WARP Endpoint (2408 / 500 / 1701 / 4500)"
            echo -e " [14] ปิดระบบ WARP (Uninstall)"
            echo -e " [0]  กลับสู่เมนูหลัก"
            echo -e "${YELLOW}============================================================${NC}"
            read -rp "เลือกทำรายการ [0-14]: " wopt
            case "$wopt" in
                1)
                    echo -e "${CYAN}กำลังติดตั้งและลงทะเบียน WARP... กรุณารอสักครู่${NC}"
                    /usr/bin/warp-route install | jq -r '.msg'
                    read -rp "กด Enter เพื่อดำเนินการต่อ..." _
                    ;;
                2)
                    echo -e "${CYAN}กำลังทดสอบการเชื่อมต่อผ่าน WARP...${NC}"
                    WT=$(/usr/bin/warp-route test)
                    echo -e " WARP Status  : $(echo "$WT" | jq -r '.warp')"
                    echo -e " WARP IP      : $(echo "$WT" | jq -r '.warp_ip') (Colo: $(echo "$WT" | jq -r '.colo'))"
                    echo -e " VPS IP       : $(echo "$WT" | jq -r '.vps_ip')"
                    echo -e " SSH Redirect : $(echo "$WT" | jq -r '.ssh_chain') (Packets: $(echo "$WT" | jq -r '.ssh_packets'))"
                    read -rp "กด Enter เพื่อดำเนินการต่อ..." _
                    ;;
                3)
                    [ "$W_XRAY" = "true" ] && /usr/bin/warp-route off xray | jq -r '.msg' || /usr/bin/warp-route on xray | jq -r '.msg'
                    sleep 1
                    ;;
                4)
                    [ "$W_SSH" = "true" ] && /usr/bin/warp-route off ssh | jq -r '.msg' || /usr/bin/warp-route on ssh | jq -r '.msg'
                    sleep 1
                    ;;
                5)
                    [ "$W_QUIC" = "true" ] && /usr/bin/warp-route off quic | jq -r '.msg' || /usr/bin/warp-route on quic | jq -r '.msg'
                    sleep 1
                    ;;
                6)
                    read -rp "กรอกโดเมนที่ต้องการ (คั่นด้วยเว้นวรรคได้ เช่น youtube.com netflix.com): " wdom
                    [ -n "$wdom" ] && /usr/bin/warp-route add "$wdom" | jq -r '.msg'
                    sleep 1
                    ;;
                7)
                    nl -w2 -s'. ' /etc/xray/warp-domains.txt 2>/dev/null
                    read -rp "พิมพ์ชื่อโดเมนที่ต้องการลบ: " wdel
                    [ -n "$wdel" ] && /usr/bin/warp-route del "$wdel" | jq -r '.msg'
                    sleep 1
                    ;;
                8)
                    echo -e "${CYAN}--- รายการโดเมนที่วิ่งผ่าน WARP ---${NC}"
                    nl -w2 -s'. ' /etc/xray/warp-domains.txt 2>/dev/null
                    read -rp "กด Enter เพื่อกลับ..." _
                    ;;
                9)
                    echo " [1] ชุดแอปไทย + Netflix (TrueMoney, 7-Eleven, AIS, Netflix, Cloudflare Trace)"
                    echo " [2] ชุด YouTube (youtube.com, googlevideo.com, ytimg.com)"
                    read -rp "เลือกชุด [1-2]: " pchoice
                    if [ "$pchoice" = "2" ]; then
                        /usr/bin/warp-route preset youtube | jq -r '.msg'
                    else
                        /usr/bin/warp-route preset thai | jq -r '.msg'
                    fi
                    sleep 1
                    ;;
                10)
                    echo -e "${CYAN}กำลังตรวจสอบคอนฟิกและรีสตาร์ท Xray...${NC}"
                    /usr/bin/warp-route apply | jq -r '.msg'
                    read -rp "กด Enter เพื่อดำเนินการต่อ..." _
                    ;;
                11)
                    read -rp "กรอก WARP+ License Key: " wkey
                    [ -n "$wkey" ] && /usr/bin/warp-route install "$wkey" | jq -r '.msg'
                    read -rp "กด Enter เพื่อดำเนินการต่อ..." _
                    ;;
                12)
                    read -rp "Private Key (Base64): " mpk
                    read -rp "IPv6 Address (เช่น 2606:4700:110:...::2/128): " mv6
                    read -rp "Reserved (เช่น 12,34,56 หรือ Enter ใช้ 0,0,0): " mres
                    /usr/bin/warp-route manual "$mpk" "$mv6" "$mres" | jq -r '.msg'
                    read -rp "กด Enter เพื่อดำเนินการต่อ..." _
                    ;;
                13)
                    echo " ตัวอย่าง: 162.159.192.1:2408 | 162.159.192.1:500 | 162.159.192.1:1701 | 162.159.192.1:4500"
                    read -rp "กรอก Endpoint ใหม่: " wep
                    [ -n "$wep" ] && /usr/bin/warp-route endpoint "$wep" | jq -r '.msg'
                    sleep 1
                    ;;
                14)
                    read -rp "ยืนยันปิดระบบ WARP Routing? (y/n): " wy
                    if [ "$wy" = "y" ] || [ "$wy" = "Y" ]; then
                        /usr/bin/warp-route uninstall | jq -r '.msg'
                    fi
                    read -rp "กด Enter เพื่อดำเนินการต่อ..." _
                    ;;
                0) break ;;
            esac
        done
        ;;
    0)
        exit 0
        ;;
    *)
        echo -e "${RED}เลือกเมนูไม่ถูกต้อง${NC}"
        ;;
esac
EOF
# ปลดล็อกสิทธิ์คำสั่งเมนูและสคริปต์ระบบทั้งหมด (ใช้ c ตัวพิมพ์เล็ก)
chmod +x /usr/bin/menu /usr/bin/running /usr/bin/xp /usr/bin/tendang /usr/bin/clear-log /usr/bin/backup-vpn /usr/bin/restore-vpn /usr/bin/api-vpn /usr/bin/panel-cmd /usr/bin/hys-auth /usr/bin/rebuild-hysteria /usr/bin/warp-route

# ------------------------------------------------------------------------------
#  FIX 1: ตั้งค่า Iptables NAT ด้วย Chain เฉพาะ (VPN_UDP) ปลอดภัยไม่กระทบ Rule อื่น
# ------------------------------------------------------------------------------
NET_IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)

iptables -t nat -N VPN_UDP 2>/dev/null || iptables -t nat -F VPN_UDP
iptables -t nat -C PREROUTING -j VPN_UDP 2>/dev/null || iptables -t nat -A PREROUTING -j VPN_UDP

iptables -t nat -A VPN_UDP -i "$NET_IFACE" -p udp --dport 5667 -j ACCEPT
iptables -t nat -A VPN_UDP -i "$NET_IFACE" -p udp --dport 8443 -j ACCEPT
iptables -t nat -A VPN_UDP -i "$NET_IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A VPN_UDP -i "$NET_IFACE" -p udp --dport 20000:50000 -j DNAT --to-destination :8443
iptables -t nat -A VPN_UDP -i "$NET_IFACE" -p udp --dport 1:5999 -j DNAT --to-destination :7200
iptables -t nat -A VPN_UDP -i "$NET_IFACE" -p udp --dport 50001:65535 -j DNAT --to-destination :7200

if ! iptables -t nat -C POSTROUTING -o "$NET_IFACE" -j MASQUERADE 2>/dev/null; then
    iptables -t nat -A POSTROUTING -o "$NET_IFACE" -j MASQUERADE
fi

for uport in 7200 5667 8443; do
    if ! iptables -C INPUT -p udp --dport "$uport" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport "$uport" -j ACCEPT
    fi
done

netfilter-persistent save >/dev/null 2>&1
netfilter-persistent reload >/dev/null 2>&1
systemctl restart udp-custom

# ------------------------------------------------------------------------------
#  FIX 2: บังคับสิทธิ์ Xray, เชื่อม Symlink และรีสตาร์ทให้สถานะ [ON] 100%
# ------------------------------------------------------------------------------
if [ ! -s /usr/local/bin/xray ]; then
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
    chmod +x /usr/local/bin/xray 2>/dev/null
fi
if [ ! -s /etc/xray/config.json ] || ! jq . /etc/xray/config.json >/dev/null 2>&1; then
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    cat <<JSON > /etc/xray/config.json
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "email": "default"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "email": "default"
          }
        ],
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
      "protocol": "freedom"
    }
  ]
}
JSON
fi
mkdir -p /etc/xray /usr/local/etc/xray /var/log/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chmod -R 777 /var/log/xray
chown -R root:root /var/log/xray /etc/xray /usr/local/etc/xray 2>/dev/null

rm -f /usr/local/etc/xray/config.json
ln -sf /etc/xray/config.json /usr/local/etc/xray/config.json 2>/dev/null

rm -rf /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d
sed -i -E 's/User=(nobody|xray)/User=root/g' /etc/systemd/system/xray.service 2>/dev/null
sed -i -E 's/Group=(nogroup|xray)/Group=root/g' /etc/systemd/system/xray.service 2>/dev/null
killall -9 xray 2>/dev/null || true
if [ -s /etc/xray/xray.key ] && [ -s /etc/xray/xray.crt ]; then
    mkdir -p /etc/stunnel
    cat /etc/xray/xray.key /etc/xray/xray.crt > /etc/stunnel/stunnel.pem 2>/dev/null
    chmod 600 /etc/stunnel/stunnel.pem 2>/dev/null
fi

# ตรวจสอบและเปิดใช้งาน Nginx Stream Multiplexer บนพอร์ต 443
sed -i '/# Multiplex Port 443/,$d' /etc/nginx/nginx.conf 2>/dev/null
if [ ! -s /etc/nginx/stream_mux.conf ]; then
    cat << 'MUX' > /etc/nginx/stream_mux.conf
stream {
    map $ssl_preread_alpn_protocols $upstream_443 {
        "~\b(h2|http/1\.1)\b"  127.0.0.1:8443;
        default               127.0.0.1:444;
    }

    server {
        listen 443 reuseport;
        listen [::]:443 reuseport;
        proxy_pass $upstream_443;
        ssl_preread on;
    }
}
MUX
fi
if ! grep -q "stream_mux.conf" /etc/nginx/nginx.conf 2>/dev/null; then
    echo "include /etc/nginx/stream_mux.conf;" >> /etc/nginx/nginx.conf
fi
sed -i 's/listen 443 ssl http2 reuseport;/listen 127.0.0.1:8443 ssl http2;/g' /etc/nginx/conf.d/xray.conf 2>/dev/null
sed -i 's/listen \[::\]:443 ssl http2 reuseport;//g' /etc/nginx/conf.d/xray.conf 2>/dev/null

# คงค่า Hook ของ WARP บน xray.service และ Apply คอนฟิก WARP กลับคืนหลังอัปเดตเมนู 27
if [ -f /etc/systemd/system/xray.service ] && ! grep -q "warp-route ipt-apply" /etc/systemd/system/xray.service 2>/dev/null; then
    cat << 'XSVC2' > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=root
Environment=XRAY_LOCATION_ASSET=/usr/local/share/xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
ExecStartPost=-/bin/bash -c 'sleep 1; [ -x /usr/bin/warp-route ] && /usr/bin/warp-route ipt-apply >/dev/null 2>&1 || true'
ExecStopPost=-/bin/bash -c '[ -x /usr/bin/warp-route ] && /usr/bin/warp-route ipt-clear >/dev/null 2>&1 || true'
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
XSVC2
fi
if [ -x /usr/bin/warp-route ] && [ -s /etc/xray/warp/warp.json ]; then
    /usr/bin/warp-route apply --no-restart >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl enable stunnel4 xray nginx >/dev/null 2>&1
systemctl restart stunnel4 xray nginx
/usr/bin/clear-log >/dev/null 2>&1

echo "✅ All-in-One VPN Suite + Modern Web Dashboard (Port 8081) Installed Successfully!"
