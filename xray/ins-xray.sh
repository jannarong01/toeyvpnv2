#!/usr/bin/env bash
# TOEYVPN_SAFE_UPDATE_V1
set -Eeuo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077

MODE="${1:---check}"

BIN="/usr/local/bin/xray"
CANONICAL="/etc/xray/config.json"
OFFICIAL="/usr/local/etc/xray/config.json"

DROPIN_DIR="/etc/systemd/system/xray.service.d"
DROPIN="$DROPIN_DIR/99-toeyvpn-config-path.conf"

WORK=""
BACKUP=""
CHANGED=0
COMMITTED=0
OLD_DROPIN=0
CREATED_DIR=0
CURRENT_CONFIG=""

die() {
    printf '[XRAY ERROR] %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die "Run as root."

[[ "${TOEYVPN_MANAGED_UPDATE:-}" == "TOEYVPN_SAFE_UPDATE_V1" ]] ||
    die "Run this module through setup.sh, not directly."

case "$MODE" in
    --check|--apply) ;;
    *) die "Unsupported mode: $MODE" ;;
esac

for cmd in systemctl jq cmp runuser getent mktemp cp install; do
    command -v "$cmd" >/dev/null ||
        die "Missing dependency: $cmd"
done

cleanup() {
    local rc=$?
    local restored=1

    trap - EXIT INT TERM
    set +e

    if ((rc != 0 && CHANGED == 1 && COMMITTED == 0)); then
        printf '\n[ROLLBACK] Restoring the previous Xray service override...\n'

        if ((OLD_DROPIN == 1)); then
            if ! cp -a -- "$BACKUP/dropin.before" "$DROPIN"; then
                restored=0
            fi
        else
            if ! rm -f -- "$DROPIN"; then
                restored=0
            fi
        fi

        if ((restored == 1)); then
            if ! systemctl daemon-reload; then
                restored=0
            fi
        fi

        if ((restored == 1)); then
            if ! systemctl restart xray.service; then
                restored=0
            fi
        fi

        if ((restored == 1)); then
            sleep 2

            if ! systemctl is-active --quiet xray.service; then
                restored=0
            fi
        fi

        if ((CREATED_DIR == 1)); then
            rmdir -- "$DROPIN_DIR" 2>/dev/null
        fi

        if ((restored == 1)); then
            printf '[ROLLBACK OK] Previous override restored; Xray is active.\n'
        else
            printf '[ROLLBACK FAILED] Manual recovery is required.\n' >&2
            printf 'Backup directory: %s\n' "$BACKUP" >&2
            printf 'Inspect: systemctl status xray --no-pager -l\n' >&2
            printf 'Inspect: journalctl -u xray -n 80 --no-pager\n' >&2
        fi
    fi

    if [[ -n "$WORK" && -d "$WORK" ]]; then
        rm -rf -- "$WORK"
    fi

    exit "$rc"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

WORK=$(mktemp -d /root/.toeyvpn-xray.XXXXXXXX)

[[ -x "$BIN" ]] || die "Xray binary is missing or not executable."
[[ -s "$CANONICAL" ]] || die "Canonical configuration is missing or empty."

[[ "$(systemctl show xray.service -p LoadState --value)" == "loaded" ]] ||
    die "xray.service is not loaded. This requires repair, not an automatic fresh install."

[[ "$(systemctl show xray.service -p NeedDaemonReload --value)" != "yes" ]] ||
    die "systemd has pending unit changes. Review those changes before running this update."

systemctl is-active --quiet xray.service ||
    die "Xray is not active. Diagnose the existing failure before applying this maintenance change."

read_effective_config() {
    local exec_start

    exec_start=$(systemctl show xray.service -p ExecStart --value)

    case "$exec_start" in
        *"argv[]=$BIN run -config $CANONICAL ;"*)
            CURRENT_CONFIG="$CANONICAL"
            ;;
        *"argv[]=$BIN run -config $OFFICIAL ;"*)
            CURRENT_CONFIG="$OFFICIAL"
            ;;
        *)
            die "Unrecognized/custom ExecStart. Refusing to replace service arguments automatically."
            ;;
    esac
}

read_effective_config

# Strict JSON validation is deliberate:
# this legacy panel edits the file using jq.
jq -e 'type == "object"' "$CANONICAL" >/dev/null ||
    die "The panel configuration is not a valid JSON object."

if [[ "$CURRENT_CONFIG" == "$OFFICIAL" ]]; then
    [[ -s "$OFFICIAL" ]] ||
        die "The effective official-path configuration is missing or empty."

    jq -e 'type == "object"' "$OFFICIAL" >/dev/null ||
        die "The official-path configuration is not a valid JSON object."

    jq -S . "$CANONICAL" > "$WORK/canonical.normalized.json"
    jq -S . "$OFFICIAL" > "$WORK/official.normalized.json"

    if ! cmp -s "$WORK/canonical.normalized.json" \
                   "$WORK/official.normalized.json"; then
        die "The two Xray configurations differ. No file was overwritten. Review and merge them before migration."
    fi
fi

# Do not change the service's execution identity.
XRAY_USER=$(systemctl show xray.service -p User --value)
XRAY_GROUP=$(systemctl show xray.service -p Group --value)
DYNAMIC_USER=$(systemctl show xray.service -p DynamicUser --value)

[[ "$DYNAMIC_USER" != "yes" ]] ||
    die "DynamicUser configuration requires a separate review."

[[ -n "$XRAY_USER" ]] || XRAY_USER="root"

getent passwd "$XRAY_USER" >/dev/null ||
    die "The configured Xray service user does not exist."

RUN_AS=(runuser -u "$XRAY_USER")

if [[ -n "$XRAY_GROUP" ]]; then
    getent group "$XRAY_GROUP" >/dev/null ||
        die "The configured Xray service group does not exist."
    RUN_AS+=(-g "$XRAY_GROUP")
fi

printf '[XRAY] Service user: %s\n' "$XRAY_USER"
printf '[XRAY] Current configuration: %s\n' "$CURRENT_CONFIG"
printf '[XRAY] Intended configuration: %s\n' "$CANONICAL"

# Test using the configured user, not just root.
# This is a configuration test, not an end-to-end traffic test.
"${RUN_AS[@]}" -- "$BIN" run -test -config "$CANONICAL"

if [[ "$CURRENT_CONFIG" == "$CANONICAL" ]]; then
    printf '[NO CHANGE] Xray already reads the same configuration path as the panel.\n'
    printf '[NO RESTART] No service change is necessary.\n'
    exit 0
fi

cat > "$WORK/dropin.new" <<'EOF'
# TOEYVPN_SAFE_UPDATE_V1
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
EOF

if [[ -e "$DROPIN" || -L "$DROPIN" ]]; then
    [[ -f "$DROPIN" && ! -L "$DROPIN" ]] ||
        die "The target override is not a regular file."

    grep -Fqx '# TOEYVPN_SAFE_UPDATE_V1' "$DROPIN" ||
        die "The target override is not managed by this updater. Refusing to overwrite it."

    OLD_DROPIN=1
fi

printf '[PLAN] Add/update: %s\n' "$DROPIN"
printf '[PLAN] Keep both configuration files unchanged.\n'
printf '[PLAN] Reload systemd, then restart Xray only.\n'
printf '[NOTICE] Existing Xray connections may briefly disconnect during restart.\n'

if [[ "$MODE" == "--check" ]]; then
    printf '[CHECK OK] Configuration-path maintenance can be attempted.\n'
    exit 0
fi

# These backups cover this bounded change, not the entire VPS.
install -d -m 700 -o root -g root /var/backups/toeyvpn
BACKUP=$(mktemp -d /var/backups/toeyvpn/xray.XXXXXXXX)

cp -L --preserve=mode,ownership,timestamps \
    "$CANONICAL" "$BACKUP/canonical.before.json"

cp -L --preserve=mode,ownership,timestamps \
    "$OFFICIAL" "$BACKUP/official.before.json"

systemctl cat xray.service > "$BACKUP/xray-service.before.txt"

if ((OLD_DROPIN == 1)); then
    cp -a -- "$DROPIN" "$BACKUP/dropin.before"
fi

printf '[BACKUP] %s\n' "$BACKUP"

if [[ ! -d "$DROPIN_DIR" ]]; then
    CREATED_DIR=1
fi

# From here onward, a failure triggers a rollback attempt.
CHANGED=1

install -d -m 755 -o root -g root "$DROPIN_DIR"

# Stage the file in the destination directory for an atomic rename.
TEMP_DROPIN=$(mktemp "$DROPIN_DIR/.toeyvpn.XXXXXXXX")

if ! install -m 644 -o root -g root \
        "$WORK/dropin.new" "$TEMP_DROPIN"; then
    rm -f -- "$TEMP_DROPIN"
    die "Could not stage the service override."
fi

if ! mv -fT -- "$TEMP_DROPIN" "$DROPIN"; then
    rm -f -- "$TEMP_DROPIN"
    die "Could not install the service override."
fi

systemctl daemon-reload

read_effective_config

[[ "$CURRENT_CONFIG" == "$CANONICAL" ]] ||
    die "Another unit override takes precedence. The intended ExecStart was not applied."

systemctl restart xray.service

# Basic stability check after restart.
for attempt in 1 2 3; do
    sleep 1

    systemctl is-active --quiet xray.service ||
        die "Xray did not remain active after restart."
done

COMMITTED=1

printf '[APPLIED] Xray now reads %s\n' "$CANONICAL"
printf '[HEALTH] Xray remained active during the basic post-restart check.\n'
printf '[PRESERVED] Users, UUIDs, certificates, and configuration contents were not changed.\n'
printf '[BACKUP] %s\n' "$BACKUP"
printf '[NEXT] Test a real client connection; active service status alone is not sufficient.\n'
