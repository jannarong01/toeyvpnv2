toeyvpnv2/
├── modules/
│   ├── 00-base.sh        <-- ติดตั้งแพ็กเกจพื้นฐาน, BBR, sysctl, Timezone
│   ├── 10-cert.sh        <-- จัดการ SSL acme.sh โหมด Webroot + Reload hook
│   ├── 20-xray.sh        <-- ติดตั้ง Xray, Nginx WS, บล็อก BitTorrent, Logrotate
│   ├── 30-ssh.sh         <-- OpenSSH Hardening, Dropbear, Fail2ban
│   ├── 40-ws.sh          <-- ติดตั้ง Python WebSocket Proxy Service
│   └── 50-udp.sh         <-- ZIVPN, Hysteria 2, UDP Custom, BadVPN, Iptables
└── websocket/
    └── websocket.py      <-- ไพธอนพร็อกซี แก้ปัญหาตัดทุก 60 วิ และข้อมูลตกหล่น
