#!/usr/bin/env bash
# TOEYVPN_SAFE_UPDATE_V1
set -Eeuo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

RELEASE="TOEYVPN_SAFE_UPDATE_V1"
REPO="jannarong01/toeyvpnv2"
MODE="--check"
COMMIT=""

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  bash setup.sh --check
  bash setup.sh --apply
  bash setup.sh --check --commit <40-character-commit>
  bash setup.sh --apply --commit <40-character-commit>

Default: --check

This release:
- Supports maintenance of an existing installation only.
- Does not install a fresh server.
- Does not issue or renew certificates.
- Does not upgrade service binaries.
EOF
}

while (($#)); do
    case "$1" in
        --check|--apply)
            MODE="$1"
            shift
            ;;
        --commit)
            [[ $# -ge 2 ]] || die "Missing value for --commit"
            COMMIT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Run as root."
[[ -d /run/systemd/system ]] || die "systemd is required."

for cmd in bash curl jq flock mktemp grep systemctl tee; do
    command -v "$cmd" >/dev/null ||
        die "Missing dependency: $cmd. No packages were installed automatically."
done

if [[ -n "$COMMIT" ]]; then
    [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
        die "--commit must be a complete lowercase 40-character Git commit."
fi

fetch() {
    curl \
        --proto '=https' \
        --tlsv1.2 \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time 90 \
        --retry 2 \
        "$1" \
        --output "$2"
}

# Bootstrap a consistent package, including setup.sh itself.
# No installed configuration is modified in this phase.
if [[ "${TOEYVPN_STAGED:-}" != "$RELEASE" ]]; then
    STAGE=$(mktemp -d /root/.toeyvpn-package.XXXXXXXX)
    trap 'rm -rf -- "$STAGE"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [[ -z "$COMMIT" ]]; then
        fetch \
            "https://api.github.com/repos/${REPO}/commits/main" \
            "$STAGE/commit.json"

        COMMIT=$(jq -er '.sha' "$STAGE/commit.json")

        [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
            die "Could not resolve a valid repository commit."
    fi

    printf '[DOWNLOAD] Commit: %s\n' "$COMMIT"

    mkdir -p "$STAGE/xray" "$STAGE/ssh"

    for file in setup.sh xray/ins-xray.sh ssh/ssh-vpn.sh; do
        fetch \
            "https://raw.githubusercontent.com/${REPO}/${COMMIT}/${file}" \
            "$STAGE/$file"

        [[ -s "$STAGE/$file" ]] ||
            die "Downloaded file is empty: $file"

        # Normalize CRLF without changing any other script content.
        sed -i 's/\r$//' "$STAGE/$file"

        bash -n "$STAGE/$file"

        grep -Fqx '# TOEYVPN_SAFE_UPDATE_V1' "$STAGE/$file" ||
            die "Safety marker missing in $file. Update all three GitHub files first."
    done

    TOEYVPN_STAGED="$RELEASE" \
        bash "$STAGE/setup.sh" "$MODE" --commit "$COMMIT"

    exit 0
fi

[[ -n "$COMMIT" ]] || die "Staged package has no commit identifier."

BASE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for file in xray/ins-xray.sh ssh/ssh-vpn.sh; do
    [[ -s "$BASE_DIR/$file" ]] ||
        die "Package file missing: $file"

    bash -n "$BASE_DIR/$file"

    grep -Fqx '# TOEYVPN_SAFE_UPDATE_V1' "$BASE_DIR/$file" ||
        die "Incompatible package file: $file"
done

# Prevent concurrent updater instances.
exec 9>/run/lock/toeyvpn-update.lock
flock -n 9 || die "Another updater is already running."

# Cooperate with the existing panel's Xray write lock.
# This does not replace a maintenance window:
# do not edit users/configuration manually during the update.
exec 8>/var/lock/vpn-panel.lock
flock -w 15 8 ||
    die "The panel is modifying Xray data. Try again after that operation completes."

install -d -m 700 -o root -g root /var/log/toeyvpn-update
LOG=$(mktemp /var/log/toeyvpn-update/run.XXXXXXXX.log)

exec > >(tee -a "$LOG") 2>&1

finish() {
    local rc=$?

    if ((rc != 0)); then
        printf '\n[FAILED] Operation stopped. Do not assume the update completed.\n'
        printf 'Log: %s\n' "$LOG"
    fi
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '\n=== ToeyVPN maintenance update ===\n'
printf 'Mode: %s\n' "$MODE"
printf 'Commit: %s\n' "$COMMIT"
printf 'Log: %s\n\n' "$LOG"

if [[ ! -e /etc/xray/config.json &&
      ! -e /usr/local/etc/xray/config.json &&
      ! -d /home/vps/public_html ]]; then
    die "FRESH installation detected. Fresh installation is intentionally disabled in this maintenance release."
fi

if [[ ! -s /etc/xray/config.json ||
      ! -x /usr/local/bin/xray ||
      ! -s /home/vps/public_html/api_ssh.php ]]; then
    die "Incomplete installation detected. Manual repair is required; the legacy installer will not be run."
fi

export TOEYVPN_MANAGED_UPDATE="$RELEASE"

printf '[1/3] Checking SSH, web configuration, and existing services...\n'
bash "$BASE_DIR/ssh/ssh-vpn.sh" --check

printf '\n[2/3] Checking Xray and planning configuration-path maintenance...\n'
bash "$BASE_DIR/xray/ins-xray.sh" --check

if [[ "$MODE" == "--check" ]]; then
    printf '\n[CHECK COMPLETE]\n'
    printf 'No service was restarted and no installed configuration was overwritten.\n'
    printf 'Certificates, users, SSH settings, and firewall rules were not changed.\n'
    printf 'This is not an end-to-end VPN connectivity or security certification.\n'
    printf '\nAfter reviewing the output and taking a VPS snapshot, use:\n'
    printf 'bash /root/setup.sh --apply --commit %s\n' "$COMMIT"
    exit 0
fi

printf '\n[3/3] Applying the bounded Xray maintenance change...\n'
bash "$BASE_DIR/xray/ins-xray.sh" --apply

printf '\n[MAINTENANCE COMPLETE]\n'
printf 'Xray configuration-path maintenance completed or no change was needed.\n'
printf 'SSH/UDP/Hysteria/API application code was not upgraded.\n'
printf 'Certificates, domains, accounts, and firewall rules were preserved.\n'
printf 'Existing security warnings still require separate remediation.\n'
printf 'Commit: %s\n' "$COMMIT"
printf 'Log: %s\n' "$LOG"
