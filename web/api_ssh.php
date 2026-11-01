<?php
/**
 * ToeyVPN v2 - Web API Integration (api_ssh.php)
 * Used for automated account provisioning (e.g., from toeyvpn.com)
 */
header('Content-Type: application/json; charset=utf-8');

$secret_key = "__SECRET_KEY__";

$req_key = $_POST['key'] ?? '';
if ($req_key !== $secret_key) {
    die(json_encode(['success' => false, 'msg' => 'Invalid Key']));
}

$action = $_POST['action'] ?? '';
$user = preg_replace('/[^a-zA-Z0-9_-]/', '', $_POST['user'] ?? '');
$pass = preg_replace('/[^a-zA-Z0-9_@#.-]/', '', $_POST['pass'] ?? '');
$days = intval($_POST['days'] ?? 0);

if (empty($user)) {
    die(json_encode(['success' => false, 'msg' => 'User empty']));
}

if ($days < 1) {
    $days = 1;
}

$esc_user = escapeshellarg($user);
$esc_pass = escapeshellarg($pass);

if ($action === 'add') {
    $exp = date('Y-m-d', strtotime("+{$days} days"));
    $esc_exp = escapeshellarg($exp);
    exec("sudo /usr/bin/api-vpn add {$esc_user} {$esc_pass} {$esc_exp} 2>&1", $out, $ret);
    exec("id -u {$esc_user} 2>/dev/null", $id_out, $id_ret);
    if ($id_ret === 0) {
        echo json_encode(['success' => true, 'exp' => $exp]);
    } else {
        echo json_encode(['success' => false, 'msg' => 'Create user failed']);
    }
} elseif ($action === 'renew') {
    $exp = date('Y-m-d', strtotime("+{$days} days"));
    $esc_exp = escapeshellarg($exp);
    exec("sudo /usr/bin/api-vpn renew {$esc_user} {$esc_pass} {$esc_exp} 2>&1", $out, $ret);
    exec("id -u {$esc_user} 2>/dev/null", $id_out, $id_ret);
    if ($id_ret === 0) {
        echo json_encode(['success' => true, 'exp' => $exp]);
    } else {
        echo json_encode(['success' => false, 'msg' => 'Renew user failed']);
    }
} elseif ($action === 'delete') {
    exec("sudo /usr/bin/api-vpn delete {$esc_user} '' '' 2>&1", $out, $ret);
    echo json_encode(['success' => true]);
} else {
    echo json_encode(['success' => false, 'msg' => 'Unknown action']);
}
