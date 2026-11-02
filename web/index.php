<?php
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");

$sess_dir = "/tmp/vpn_panel_sessions";
if (!is_dir($sess_dir)) {
    @mkdir($sess_dir, 0700, true);
}
@chmod($sess_dir, 0700);
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

$salt_file = '/etc/xray/.panel_salt';
if (!file_exists($salt_file)) {
    if (!is_dir('/etc/xray')) {
        @mkdir('/etc/xray', 0755, true);
    }
    @file_put_contents($salt_file, bin2hex(random_bytes(16)));
    @chmod($salt_file, 0600);
}
$salt = file_exists($salt_file) ? trim(file_get_contents($salt_file)) : 'toeyvpn_salt_fallback_key';

$auth_token = hash_hmac('sha256', $admin_pass . $salt, 'toeyvpn_node_auth_v2');

if (isset($_COOKIE['toeyvpn_node_token']) && hash_equals($auth_token, $_COOKIE['toeyvpn_node_token'])) {
    $_SESSION['vpn_admin_logged'] = true;
}

if (isset($_GET['logout'])) {
    $_SESSION = [];
    session_destroy();
    setcookie('toeyvpn_node_token', '', [
        'expires' => time() - 3600,
        'path' => '/',
        'httponly' => true,
        'samesite' => 'Lax'
    ]);
    header("Location: index.php?t=" . time());
    exit;
}

$login_error = "";
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['login_pass'])) {
    if (hash_equals($admin_pass, trim($_POST['login_pass']))) {
        $_SESSION['vpn_admin_logged'] = true;
        setcookie('toeyvpn_node_token', $auth_token, [
            'expires' => time() + (86400 * 30),
            'path' => '/',
            'httponly' => true,
            'samesite' => 'Lax'
        ]);
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
    <title>ToeyVPN v2 • Node Management Panel</title>
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
                    TOEYVPN v2 NODE PANEL
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
                        <span class="font-bold text-base tracking-wide text-white">TOEYVPN</span>
                        <span class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-cyan-500/20 text-cyan-300 border border-cyan-500/30">v2 NODE</span>
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
                    'stunnel4': 'Stunnel4 (444/777/10443)',
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
• Stunnel4 SSL  : 444, 777 (พอร์ตภายใน 10443)
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
