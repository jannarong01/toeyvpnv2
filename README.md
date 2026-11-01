# ToeyVPN v2 — Private VPN Auto-Installer Suite

![Shell Script](https://img.shields.io/badge/Shell-Bash-green?logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian-orange)

> ระบบติดตั้ง VPN อัตโนมัติครบวงจร รองรับ SSH/WS, UDP Custom, Xray (Vmess/Vless), ZIVPN, Hysteria 2, Web Panel
>
> All-in-one automated VPN installer supporting SSH/WS, UDP Custom, Xray (Vmess/Vless), ZIVPN, Hysteria 2, and Web Dashboard.

---

## 📋 Supported OS / ระบบปฏิบัติการที่รองรับ

| Distribution | Versions          |
|-------------|-------------------|
| Ubuntu      | 20.04 / 22.04 / 24.04 LTS |
| Debian      | 10 / 11 / 12      |

---

## ✨ Features / ฟีเจอร์

- **SSH-WS** — OpenSSH + Dropbear + WebSocket Tunnel (HTTP & SSL/TLS)
- **UDP Custom** — UDP Custom proxy with internal port 7200
- **Xray Vmess/Vless** — Full Xray Core with Vmess & Vless over WS + TLS
- **ZIVPN UDP** — ZIVPN UDP tunnel (port 5667 & 6000-19999)
- **Hysteria 2 QUIC** — High-speed QUIC-based tunnel (port 8443 & 20000-50000)
- **Web Dashboard** — Admin web panel on port 8081
- **API for toeyvpn.com** — RESTful API integration for automated VPN sales
- **Backup / Restore** — Full system backup and restore
- **Anti-Torrent** — Block torrent traffic with iptables
- **TCP BBR** — Google BBR congestion control for faster throughput
- **Fail2Ban** — Brute-force protection for SSH
- **Auto-Kill Multi-Login** — Automatically kill duplicate user sessions
- **Speedtest** — Built-in server speed test

---

## 🔌 Port Table / ตารางพอร์ต

| Service             | Protocol | Port(s)                     |
|---------------------|----------|-----------------------------|
| OpenSSH             | TCP      | 22                          |
| Dropbear            | TCP      | 109, 143                    |
| SSH WebSocket       | TCP      | 80 (HTTP), 443 (SSL/TLS)    |
| UDP Custom          | UDP      | 1-65535 (Internal: 7200)     |
| BadVPN UDPGW        | UDP      | 7100, 7300                   |
| Xray Vmess/Vless    | TCP      | 80 (HTTP), 443 (SSL/TLS)    |
| ZIVPN UDP           | UDP      | 5667, 6000-19999             |
| Hysteria 2 QUIC     | UDP      | 8443, 20000-50000            |
| Web Panel           | TCP      | 8081                         |

---

## 🚀 Quick Install / ติดตั้งด่วน

SSH เข้าเซิร์ฟเวอร์ด้วยสิทธิ์ root แล้วรันคำสั่ง:

```bash
apt update && apt install -y wget curl && bash <(wget -qO- https://raw.githubusercontent.com/jannarong01/toeyvpnv2/main/setup.sh)
```

> [!IMPORTANT]
> ต้องรันด้วยสิทธิ์ **root** เท่านั้น และเซิร์ฟเวอร์ต้องเป็น Ubuntu 20.04+ หรือ Debian 10+

---

## 🏗️ Architecture / สถาปัตยกรรมระบบ

```
┌──────────────────────────────────────────────────────────┐
│                      Client Device                       │
│          (HTTP Injector / ZIVPN / Hysteria 2)            │
└────────────┬──────────────┬──────────────┬───────────────┘
             │ TCP 80/443   │ UDP 5667+    │ UDP 8443+
             ▼              ▼              ▼
┌────────────────────────────────────────────────────────────┐
│                     VPS Server (Root)                      │
│                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  Nginx       │  │  ZIVPN       │  │  Hysteria 2     │  │
│  │  :80 / :443  │  │  :5667       │  │  :8443          │  │
│  │  (SSL Term)  │  │  :6000-19999 │  │  :20000-50000   │  │
│  └──────┬───────┘  └──────────────┘  └─────────────────┘  │
│         │                                                  │
│         ├──► WebSocket Proxy (:10015) ──► SSH (:22)        │
│         ├──► Xray Core (Vmess/Vless)                       │
│         └──► Web Panel (:8081) ──► API (toeyvpn.com)       │
│                                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  Dropbear    │  │  UDP Custom  │  │  BadVPN UDPGW   │  │
│  │  :109 / :143 │  │  :7200 int   │  │  :7100 / :7300  │  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  System: TCP BBR • Fail2Ban • Anti-Torrent • Cron   │   │
│  └─────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

---

## 📝 Changelog v2 (จาก v1) / What's New

### 🐛 Bug Fixes
- แก้ไขบั๊ก 23 จุดจาก v1
- แก้ไข race condition ของ `fuser` lock ตอนติดตั้ง
- แก้ไข Xray config ที่ fallback path ชนกัน
- แก้ไข Hysteria 2 cert path ที่ไม่ตรงกับ ACME
- แก้ไข WebSocket proxy ที่ timeout เร็วเกินไป
- แก้ไข cron job auto-kill ที่ทำงานผิดพลาดกับ user session

### 🔒 Security Hardening
- เพิ่ม `psmisc` dependency สำหรับ `fuser` command
- ปรับปรุง Fail2Ban rules ให้เข้มงวดขึ้น
- เพิ่ม proper file locking ป้องกัน concurrent access
- ลบ hardcoded credentials ออกจาก script

### 🏗️ Architecture Improvements
- รวม `ins-xray.sh` เข้ากับ `ssh-vpn.sh` — ลดขั้นตอนการติดตั้ง
- แยก Web Dashboard เป็น component อิสระ
- ลบ duplicate code ออกทั้งหมด
- ปรับปรุง WebSocket proxy (buffer 16KB, timeout 120s)
- ใช้ LF line endings ทั้งโปรเจกต์ (ไม่มี CRLF)

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

## 👨‍💻 Credits

- **Developer:** [jannarong01](https://github.com/jannarong01)
- **Website:** [toeyvpn.com](https://toeyvpn.com)

---

> พิมพ์คำสั่ง `menu` หลังติดตั้งเสร็จเพื่อเข้าสู่หน้าจัดการระบบ VPN
