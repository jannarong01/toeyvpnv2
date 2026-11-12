<?php
/**
 * ToeyVPN v2 - Web API Integration (api_ssh.php)
 * Used for automated account provisioning (e.g., from toeyvpn.com)
 * Supports both daily accounts and hourly trial accounts (hours=1 / is_trial=1)
 */
date_default_timezone_set('Asia/Bangkok');
header('Content-Type: application/json; charset=utf-8');

$secret_key = "__SECRET_KEY__";

$raw = file_get_contents('php://input');
$json = json_decode($raw, true);
$req = array_merge($_GET, $_POST, is_array($json) ? $json : []);

$req_key = $req['key'] ?? ($req['secret'] ?? ($req['secret_key'] ?? ($req['token'] ?? '')));
if (!hash_equals($secret_key, (string)$req_key)) {
    die(json_encode(['success' => false, 'msg' => 'Invalid Key']));
}

$action = $req['action'] ?? ($req['act'] ?? 'add');
if (in_array($action, ['add_zivpn', 'zivpn', 'create', 'add_ssh', 'trial', 'add_trial'])) {
    $action = 'add';
}

$user = preg_replace('/[^a-zA-Z0-9_-]/', '', $req['user'] ?? ($req['username'] ?? ''));
$pass = preg_replace('/[^a-zA-Z0-9_@#.-]/', '', $req['pass'] ?? ($req['password'] ?? ($req['zpass'] ?? '')));
$hours = intval($req['hours'] ?? ($req['hour'] ?? 0));
$days = intval($req['days'] ?? ($req['day'] ?? 0));

if (!empty($req['is_trial']) || !empty($req['trial'])) {
    if ($hours < 1) {
        $hours = 1;
    }
}

if (empty($user) && !empty($pass)) {
    $user = 'zi_' . preg_replace('/[^a-zA-Z0-9]/', '', $pass);
} elseif (!empty($user) && empty($pass)) {
    $pass = $user;
}

if (empty($user)) {
    die(json_encode(['success' => false, 'msg' => 'User empty']));
}

$esc_user = escapeshellarg($user);
$esc_pass = escapeshellarg($pass);

if ($action === 'add') {
    if ($hours > 0) {
        $exp_ts = time() + ($hours * 3600);
        $exp_str = date('Y-m-d H:i', $exp_ts);
        $esc_exp_ts = escapeshellarg((string)$exp_ts);
        exec("sudo /usr/bin/api-vpn add_trial {$esc_user} {$esc_pass} {$esc_exp_ts} 2>&1", $out, $ret);
        exec("id -u {$esc_user} 2>/dev/null", $id_out, $id_ret);
        if ($id_ret === 0) {
            echo json_encode(['success' => true, 'exp' => $exp_str, 'expire_ts' => $exp_ts, 'user' => $user, 'pass' => $pass]);
        } else {
            echo json_encode(['success' => false, 'msg' => 'Create trial user failed']);
        }
    } else {
        if ($days < 1) {
            $days = 1;
        }
        $exp = date('Y-m-d', strtotime("+{$days} days"));
        $esc_exp = escapeshellarg($exp);
        exec("sudo /usr/bin/api-vpn add {$esc_user} {$esc_pass} {$esc_exp} 2>&1", $out, $ret);
        exec("id -u {$esc_user} 2>/dev/null", $id_out, $id_ret);
        if ($id_ret === 0) {
            echo json_encode(['success' => true, 'exp' => $exp, 'user' => $user, 'pass' => $pass]);
        } else {
            echo json_encode(['success' => false, 'msg' => 'Create user failed']);
        }
    }
} elseif ($action === 'renew') {
    if ($days < 1) {
        $days = 1;
    }
    $exp = date('Y-m-d', strtotime("+{$days} days"));
    $esc_exp = escapeshellarg($exp);
    exec("sudo /usr/bin/api-vpn renew {$esc_user} {$esc_pass} {$esc_exp} 2>&1", $out, $ret);
    exec("id -u {$esc_user} 2>/dev/null", $id_out, $id_ret);
    if ($id_ret === 0) {
        echo json_encode(['success' => true, 'exp' => $exp]);
    } else {
        echo json_encode(['success' => false, 'msg' => 'Renew user failed']);
    }
} elseif ($action === 'delete' || $action === 'del') {
    exec("sudo /usr/bin/api-vpn delete {$esc_user} '' '' 2>&1", $out, $ret);
    echo json_encode(['success' => true]);
} else {
    echo json_encode(['success' => false, 'msg' => 'Unknown action']);
}
