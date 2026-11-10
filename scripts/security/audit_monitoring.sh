#!/usr/bin/env bash
#
# Linux Audit rules, desktop alerts and a daily audit report for Omarchy.
#
#   - Persistent Linux Audit rules (identity, sudo, SSH, PAM, modules,
#     containers, ptrace, privileged executables)
#   - Per-minute checker that sends a desktop notification for new events
#   - Daily audit report (30 days kept)
#
# Usage: sudo bash audit_monitoring.sh


set -Eeuo pipefail
umask 077

RULE_DIR="/etc/audit/rules.d"
REPORT_DIR="/var/log/audit/reports"
STATE_DIR="/var/lib/audit-alerts"

ALERT_SCRIPT="/usr/local/sbin/audit-alert-check"
REPORT_SCRIPT="/usr/local/sbin/audit-daily-report"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
TMP_DIR="$(mktemp -d)"
BACKUP_DIR="/root/audit-rules-backup-${TIMESTAMP}"

trap 'rm -rf "$TMP_DIR"' EXIT

RULE_FILES=(
    10-base-config.rules
    11-loginuid.rules
    30-identity.rules
    31-privileged.rules
    32-security.rules
    40-kernel.rules
    41-containers.rules
    42-injection.rules
)

KEYS=(
    privileged
    identity
    scope
    ssh
    apparmor
    audit
    pam
    polkit
    sysctl
    modprobe
    systemd
    crypto
    mounts
    module-load
    module-unload
    container-create
    container-config
    process-tracing
)

# --------------------------------------------------
# 1. Preconditions
# --------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run with sudo."
    exit 1
fi

if [[ ! -x /usr/bin/pacman ]]; then
    echo "ERROR: This installer requires Arch Linux or Omarchy."
    exit 1
fi

echo "===== CHECKING SYSTEM ====="

pacman -S --needed audit libnotify

for cmd in auditctl augenrules ausearch aureport \
           systemctl loginctl runuser getcap notify-send; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Missing command: $cmd"
        exit 1
    fi
done

if auditctl -s | awk '$1 == "enabled" && $2 == "2" {
    found=1
} END { exit !found }'; then
    echo "ERROR: Audit rules are immutable (enabled=2)."
    echo "Reboot before changing the audit configuration."
    exit 1
fi

# Detect native audit architecture and optional 32-bit compatibility.
ARCHES=()

case "$(uname -m)" in
    x86_64)
        ARCHES+=(b64)
        if pacman -Qq lib32-glibc >/dev/null 2>&1; then
            ARCHES+=(b32)
        fi
        ;;
    aarch64)
        ARCHES+=(b64)
        ;;
    i?86)
        ARCHES+=(b32)
        ;;
    *)
        echo "ERROR: Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

echo "Audit architectures: ${ARCHES[*]}"

mkdir -p "$RULE_DIR" "$REPORT_DIR" "$STATE_DIR"
chmod 0700 "$REPORT_DIR" "$STATE_DIR"

# --------------------------------------------------
# 2. Back up files managed by this installer
# --------------------------------------------------

echo
echo "===== BACKING UP EXISTING RULES ====="

BACKUP_CREATED=0
mkdir -p "$BACKUP_DIR"

for file in "${RULE_FILES[@]}"; do
    if [[ -f "$RULE_DIR/$file" ]]; then
        cp -a "$RULE_DIR/$file" "$BACKUP_DIR/"
        BACKUP_CREATED=1
        echo "Backed up $file"
    fi
done

if [[ "$BACKUP_CREATED" -eq 0 ]]; then
    rmdir "$BACKUP_DIR"
    BACKUP_DIR="none"
fi

# --------------------------------------------------
# 3. Base audit configuration
# --------------------------------------------------

cat > "$TMP_DIR/10-base-config.rules" <<'EOF'
## Base Linux Audit configuration.
## Intentionally does not delete unrelated existing rules.

-b 8192
--backlog_wait_time 60000
-f 1
EOF

# --------------------------------------------------
# 4. Login identity protection (opt-in)
# --------------------------------------------------

cat > "$TMP_DIR/11-loginuid.rules" <<'EOF'
## Optional hardening.
## Test container and service compatibility before enabling.
## Uncomment to make loginuid immutable:
# --loginuid-immutable
EOF

# --------------------------------------------------
# 5. Account and authentication monitoring
# --------------------------------------------------

cat > "$TMP_DIR/30-identity.rules" <<'EOF'
## Account and authentication database changes.
EOF

add_watch() {
    local path="$1"
    local key="$2"

    if [[ -e "$path" ]]; then
        printf -- '-w %s -p wa -k %s\n' "$path" "$key" \
            >> "$TMP_DIR/30-identity.rules"
    fi
}

add_watch /etc/passwd identity
add_watch /etc/group identity
add_watch /etc/shadow identity
add_watch /etc/gshadow identity
add_watch /etc/security/opasswd identity
add_watch /etc/sudoers scope
add_watch /etc/sudoers.d scope

# --------------------------------------------------
# 6. Discover privileged executables
# --------------------------------------------------

echo
echo "===== DISCOVERING PRIVILEGED EXECUTABLES ====="

declare -A SEEN_DIRS=()
SCAN_DIRS=()

for dir in /bin /sbin /usr/bin /usr/sbin \
           /usr/local/bin /usr/local/sbin; do

    if [[ -d "$dir" ]]; then
        resolved="$(readlink -f "$dir")"

        if [[ -z "${SEEN_DIRS[$resolved]+x}" ]]; then
            SEEN_DIRS["$resolved"]=1
            SCAN_DIRS+=("$resolved")
        fi
    fi
done

: > "$TMP_DIR/privileged-paths.nul"

# SUID and SGID programs.
find "${SCAN_DIRS[@]}" -xdev -type f -perm /6000 \
    -print0 >> "$TMP_DIR/privileged-paths.nul"

# File-capability programs.
while IFS= read -r path; do
    [[ -n "$path" ]] && printf '%s\0' "$path"
done < <(
    getcap -r "${SCAN_DIRS[@]}" 2>/dev/null |
    awk '{ print $1 }'
) >> "$TMP_DIR/privileged-paths.nul"

sort -zu "$TMP_DIR/privileged-paths.nul" \
    > "$TMP_DIR/privileged-paths.sorted"

{
    echo "## Automatically generated privileged executable rules."
    echo "## Generated: $TIMESTAMP"

    while IFS= read -r -d '' path; do

        if [[ "$path" =~ [[:space:]] ]]; then
            echo "Skipping path containing whitespace: $path" >&2
            continue
        fi

        for arch in "${ARCHES[@]}"; do
            printf -- \
                '-a always,exit -F arch=%s -F path=%s -F perm=x -F auid>=1000 -F auid!=unset -k privileged\n' \
                "$arch" "$path"
        done

    done < "$TMP_DIR/privileged-paths.sorted"

} > "$TMP_DIR/31-privileged.rules"

PRIV_COUNT="$(grep -c -- '-k privileged' \
    "$TMP_DIR/31-privileged.rules" || true)"

echo "Generated $PRIV_COUNT privileged executable rules."

# --------------------------------------------------
# 7. Security configuration monitoring
# --------------------------------------------------

cat > "$TMP_DIR/32-security.rules" <<'EOF'
## Security-sensitive configuration changes.
EOF

add_security_watch() {
    local path="$1"
    local key="$2"

    if [[ -e "$path" ]]; then
        printf -- '-w %s -p wa -k %s\n' "$path" "$key" \
            >> "$TMP_DIR/32-security.rules"
    fi
}

add_security_watch /etc/ssh ssh
add_security_watch /etc/apparmor.d apparmor
add_security_watch /etc/audit audit
add_security_watch /etc/audit/rules.d audit
add_security_watch /etc/pam.d pam
add_security_watch /etc/polkit-1/rules.d polkit
add_security_watch /etc/sysctl.d sysctl
add_security_watch /etc/modprobe.d modprobe
add_security_watch /etc/systemd/system systemd
add_security_watch /etc/crypttab crypto
add_security_watch /etc/fstab mounts

# --------------------------------------------------
# 8. Kernel module monitoring
# --------------------------------------------------

: > "$TMP_DIR/40-kernel.rules"

for arch in "${ARCHES[@]}"; do
    cat >> "$TMP_DIR/40-kernel.rules" <<EOF
## Kernel module insertion and removal.
-a always,exit -F arch=$arch -S init_module,finit_module -k module-load
-a always,exit -F arch=$arch -S delete_module -k module-unload

EOF
done

# --------------------------------------------------
# 9. Container namespace monitoring
# --------------------------------------------------

: > "$TMP_DIR/41-containers.rules"

for arch in "${ARCHES[@]}"; do
    cat >> "$TMP_DIR/41-containers.rules" <<EOF
## Container namespace operations.
-a always,exit -F arch=$arch -S clone -F a0&0x7C020000 -k container-create
-a always,exit -F arch=$arch -S unshare,setns -k container-config

EOF
done

# --------------------------------------------------
# 10. Process tracing monitoring
# --------------------------------------------------

: > "$TMP_DIR/42-injection.rules"

for arch in "${ARCHES[@]}"; do
    printf -- \
        '-a always,exit -F arch=%s -S ptrace -k process-tracing\n' \
        "$arch" >> "$TMP_DIR/42-injection.rules"
done

# --------------------------------------------------
# 11. Install audit rules
# --------------------------------------------------

echo
echo "===== INSTALLING AUDIT RULES ====="

for file in "${RULE_FILES[@]}"; do
    install -m 0640 "$TMP_DIR/$file" "$RULE_DIR/$file"
    echo "Installed $file"
done

# --------------------------------------------------
# 12. Install notification checker
# --------------------------------------------------

echo
echo "===== INSTALLING NOTIFICATION CHECKER ====="

cat > "$ALERT_SCRIPT" <<'ALERT_EOF'
#!/usr/bin/env bash

set -u

STATE_DIR="/var/lib/audit-alerts"

KEYS=(
    privileged
    identity
    scope
    ssh
    apparmor
    audit
    pam
    polkit
    sysctl
    modprobe
    systemd
    crypto
    mounts
    module-load
    module-unload
    container-create
    container-config
    process-tracing
)

# Compare audit event IDs: epoch:serial.
event_is_newer() {
    local current="$1"
    local previous="$2"

    awk -v a="$current" -v b="$previous" '
        BEGIN {
            split(a, A, ":")
            split(b, B, ":")

            if ((A[1] + 0) > (B[1] + 0))
                exit 0

            if ((A[1] + 0) == (B[1] + 0) &&
                (A[2] + 0) > (B[2] + 0))
                exit 0

            exit 1
        }
    '
}


# Send a persistent security notification to the active desktop session.
send_notification() {
    local title="$1"
    local body="$2"

    local session active type uid username runtime

    while read -r session _; do

        [[ -n "$session" ]] || continue

        active="$(loginctl show-session "$session" \
            -p Active --value 2>/dev/null || true)"

        [[ "$active" == "yes" ]] || continue

        type="$(loginctl show-session "$session" \
            -p Type --value 2>/dev/null || true)"

        [[ "$type" == "wayland" || "$type" == "x11" ]] || continue

        uid="$(loginctl show-session "$session" \
            -p User --value 2>/dev/null || true)"

        [[ "$uid" =~ ^[0-9]+$ ]] || continue

        runtime="/run/user/$uid"

        [[ -S "$runtime/bus" ]] || continue

        username="$(getent passwd "$uid" | cut -d: -f1)"
        [[ -n "$username" ]] || continue

        if runuser -u "$username" -- \
            env \
            XDG_RUNTIME_DIR="$runtime" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
            /usr/bin/notify-send \
                --app-name="Omarchy Security" \
                --urgency=critical \
                --icon=security-high \
                "$title" \
                "$body" 2>/dev/null; then
            return 0
        fi

    done < <(loginctl list-sessions --no-legend 2>/dev/null)

    return 1
}


# Examine events recorded today and compare with the last processed ID.
for key in "${KEYS[@]}"; do

    state_file="$STATE_DIR/$key.last"

    if [[ ! -f "$state_file" ]]; then
        date +%s:0 > "$state_file"
    fi

    previous="$(cat "$state_file")"

    raw="$(ausearch -k "$key" -ts today --raw 2>/dev/null || true)"

    [[ -n "$raw" ]] || continue

    ids="$(
        printf '%s\n' "$raw" |
        grep -oE 'audit\([0-9]+(\.[0-9]+)?:[0-9]+\)' |
        sed -E 's/^audit\((.*)\)$/\1/' |
        sort -u -t: -k1,1n -k2,2n
    )"

    [[ -n "$ids" ]] || continue

    latest="$previous"
    count=0

    while IFS= read -r id; do
        [[ -n "$id" ]] || continue

        if event_is_newer "$id" "$previous"; then
            count=$((count + 1))
            latest="$id"
        fi
    done <<< "$ids"

    (( count > 0 )) || continue

    title="Linux Security Alert: $key"
    body="$count new audit event(s) detected.

Review with:
sudo ausearch -k $key -ts today -i"

    # Do not advance the checkpoint if no desktop session is available.
    # This allows the notification to appear after a user logs in.
    if send_notification "$title" "$body"; then
        printf '%s\n' "$latest" > "$state_file"
        logger -t audit-alert \
            "Notification sent: key=$key events=$count"
    else
        logger -t audit-alert \
            "No active desktop notification session: key=$key events=$count"
    fi

done
ALERT_EOF

chmod 0750 "$ALERT_SCRIPT"

# --------------------------------------------------
# 13. Install daily report generator
# --------------------------------------------------

cat > "$REPORT_SCRIPT" <<'REPORT_EOF'
#!/usr/bin/env bash

set -u

REPORT_DIR="/var/log/audit/reports"
REPORT="$REPORT_DIR/audit-$(date +%F).txt"

mkdir -p "$REPORT_DIR"
chmod 0700 "$REPORT_DIR"

exec > "$REPORT" 2>&1

echo "=========================================="
echo "       DAILY SECURITY AUDIT REPORT"
echo "=========================================="
echo "Generated: $(date)"
echo "Period: yesterday"
echo

echo "===== AUDIT HEALTH ====="
auditctl -s

echo
echo "===== AUDIT SUMMARY ====="
aureport --summary -ts yesterday -te today -i || true

KEYS=(
    privileged
    identity
    scope
    ssh
    apparmor
    audit
    pam
    polkit
    sysctl
    modprobe
    systemd
    crypto
    mounts
    module-load
    module-unload
    container-create
    container-config
    process-tracing
)

for key in "${KEYS[@]}"; do
    echo
    echo "===== $key ====="
    ausearch -k "$key" -ts yesterday -te today -i || true
done

echo
echo "===== END OF REPORT ====="

find "$REPORT_DIR" -type f -name 'audit-*.txt' \
    -mtime +30 -delete
REPORT_EOF

chmod 0750 "$REPORT_SCRIPT"

# --------------------------------------------------
# 14. Initialize notification checkpoints
# --------------------------------------------------

echo
echo "===== INITIALIZING ALERT CHECKPOINTS ====="

# Do not notify about events that occurred before installation.
INITIAL_ID="$(date +%s):0"

for key in "${KEYS[@]}"; do
    if [[ ! -f "$STATE_DIR/$key.last" ]]; then
        printf '%s\n' "$INITIAL_ID" > "$STATE_DIR/$key.last"
    fi
done

# --------------------------------------------------
# 15. Create systemd services and timers
# --------------------------------------------------

echo
echo "===== CONFIGURING SYSTEMD ====="

cat > /etc/systemd/system/audit-alert-check.service <<'EOF'
[Unit]
Description=Check Linux Audit Events and Send Desktop Notifications
After=auditd.service
Requires=auditd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/audit-alert-check
EOF

cat > /etc/systemd/system/audit-alert-check.timer <<'EOF'
[Unit]
Description=Check Security Audit Events Every Minute

[Timer]
OnCalendar=minutely
AccuracySec=1s
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/audit-daily-report.service <<'EOF'
[Unit]
Description=Daily Linux Security Audit Report
After=auditd.service
Requires=auditd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/audit-daily-report
EOF

cat > /etc/systemd/system/audit-daily-report.timer <<'EOF'
[Unit]
Description=Daily Linux Security Audit Report

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
EOF

# --------------------------------------------------
# 16. Enable auditd and load rules
# --------------------------------------------------

echo
echo "===== ENABLING AUDITD ====="

systemctl enable --now auditd

echo
echo "===== LOADING AUDIT RULES ====="

augenrules --load

# --------------------------------------------------
# 17. Enable timers
# --------------------------------------------------

echo
echo "===== ENABLING TIMERS ====="

systemctl daemon-reload

systemctl enable --now audit-alert-check.timer
systemctl enable --now audit-daily-report.timer

# --------------------------------------------------
# 18. Final status
# --------------------------------------------------

echo
echo "=========================================="
echo "       INSTALLATION COMPLETE"
echo "=========================================="

echo
echo "===== AUDIT STATUS ====="
auditctl -s

echo
echo "===== ACTIVE TIMERS ====="
systemctl list-timers \
    audit-alert-check.timer \
    audit-daily-report.timer --no-pager

echo
echo "===== INSTALLED RULE FILES ====="
ls -lh "$RULE_DIR"

echo
echo "===== BACKUP ====="
echo "$BACKUP_DIR"

echo
echo "===== NEXT STEPS ====="
echo
echo "1. Test notifications:"
echo "   sudo systemctl start audit-alert-check.service"
echo
echo "2. Test daily report:"
echo "   sudo systemctl start audit-daily-report.service"
echo
echo "3. Read the report:"
echo "   sudo less $REPORT_DIR/audit-$(date +%F).txt"
echo
echo "4. Check audit health:"
echo "   sudo auditctl -s"
echo
echo "5. Check notification service:"
echo "   journalctl -u audit-alert-check.service"
echo
echo "NOTE: Desktop notifications require an active graphical session."
echo "NOTE: Early-boot auditing (audit=1) is not configured."
echo "NOTE: Immutable audit mode is intentionally not enabled."
