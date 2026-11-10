#!/usr/bin/env bash
#
# Integrity and audit-report monitoring for Omarchy.
#
#   - AIDE file-integrity baseline (/etc, /usr/bin, /usr/lib, /boot, ...)
#   - Daily check (capabilities, SUID/SGID inventory, audit log, disk)
#   - Desktop notification when the daily check finds something
#   - Weekly Lynis audit
#
# Usage: sudo bash integrity_monitoring.sh

set -Eeuo pipefail

readonly CHECKER="/usr/local/sbin/omarchy-security-check"
readonly AIDE_CONFIG="/etc/aide/omarchy-aide.conf"
readonly LOG_DIR="/var/log/omarchy-security"
readonly STATE_DIR="/var/lib/omarchy-security"
readonly SERVICE="/etc/systemd/system/omarchy-security-check.service"
readonly TIMER="/etc/systemd/system/omarchy-security-check.timer"
readonly LYNIS_SERVICE="/etc/systemd/system/omarchy-lynis.service"
readonly LYNIS_TIMER="/etc/systemd/system/omarchy-lynis.timer"

if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run with sudo."
    exit 1
fi


# --------------------------------------------------
# 1. Install packages
# --------------------------------------------------

echo "[1/8] Installing packages..."

# Install packages available in official repositories.
pacman -S --needed --noconfirm lynis libnotify

# Install AIDE from the AUR if it is not already installed.
if ! pacman -Qq aide >/dev/null 2>&1; then
    echo "AIDE is not installed in the official repositories."
    echo "Checking for an AUR helper..."

    AUR_USER="${SUDO_USER:-}"

    if [[ -z "$AUR_USER" ]]; then
        echo "ERROR: No invoking user found."
        echo
        echo "Then install AIDE manually with yay or paru."
        exit 1
    fi

    AUR_HELPER="$(
        runuser -u "$AUR_USER" -- bash -lc \
            'command -v yay || command -v paru' 2>/dev/null \
            | head -n1
    )"

    if [[ -z "$AUR_HELPER" ]]; then
        echo "ERROR: Neither yay nor paru is installed."
        echo
        echo "Install an AUR helper first, then rerun this script."
        exit 1
    fi

    echo "Found AUR helper: $AUR_HELPER"
    echo "Installing AIDE as user: $AUR_USER"

    runuser -u "$AUR_USER" -- \
        "$AUR_HELPER" -S --needed aide

    if ! pacman -Qq aide >/dev/null 2>&1; then
        echo "ERROR: AIDE installation could not be verified."
        exit 1
    fi
fi

echo "Checking required commands..."

for cmd in aide lynis notify-send auditctl systemctl loginctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Missing required command: $cmd"
        exit 1
    fi
done

echo "All required packages and commands are available."



# --------------------------------------------------
# Configure persistent security notifications
# --------------------------------------------------

echo "Configuring security notifications..."

TARGET_USER="${SUDO_USER:-}"

if [[ -n "$TARGET_USER" ]] && id "$TARGET_USER" >/dev/null 2>&1; then
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

    if command -v mako >/dev/null 2>&1; then
        MAKO_CONFIG="$TARGET_HOME/.config/mako/config"

        install -d -o "$TARGET_USER" \
            -g "$(id -gn "$TARGET_USER")" \
            -m 0750 "$TARGET_HOME/.config/mako"

        if [[ -f "$MAKO_CONFIG" ]]; then
            cp -a "$MAKO_CONFIG" \
                "$MAKO_CONFIG.backup.$(date +%Y%m%d-%H%M%S)"
        fi

        # Replace only our previously managed configuration block.
        if [[ -f "$MAKO_CONFIG" ]]; then
            sed -i \
                '/^# BEGIN OMARCHY SECURITY NOTIFICATIONS$/,/^# END OMARCHY SECURITY NOTIFICATIONS$/d' \
                "$MAKO_CONFIG"
        fi

        cat >> "$MAKO_CONFIG" <<'EOF'

# BEGIN OMARCHY SECURITY NOTIFICATIONS
[app-name="Omarchy Security"]
default-timeout=0
background-color=#191b24
text-color=#f5f5f5
border-color=#ff5555
border-size=2
border-radius=10
padding=16
width=440
height=160
font=Sans 11
format=<b>%s</b>\n%b
# END OMARCHY SECURITY NOTIFICATIONS
EOF

        chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$MAKO_CONFIG"
        chmod 0640 "$MAKO_CONFIG"

        echo "Persistent Mako security notifications configured."
    else
        echo "Mako not detected."
        echo "Using the existing Omarchy notification system."
    fi
fi


# --------------------------------------------------
# 2. Create directories
# --------------------------------------------------

echo "[2/8] Creating monitoring directories..."

install -d -m 0750 "$LOG_DIR"
install -d -m 0700 "$STATE_DIR"
install -d -m 0755 /etc/aide

# --------------------------------------------------
# 3. Configure AIDE
# --------------------------------------------------

echo "[3/8] Configuring AIDE..."

if [[ -e "$AIDE_CONFIG" ]]; then
    cp -a "$AIDE_CONFIG" \
        "${AIDE_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"
fi

cat > "$AIDE_CONFIG" <<'EOF'
# Omarchy workstation integrity baseline

database_in=file:/var/lib/aide/omarchy-aide.db
database_out=file:/var/lib/aide/omarchy-aide.db.new

# Attributes to monitor:
# permissions, inode, ownership, size, timestamps,
# file type, and SHA-256 content hash.
OMARCHY = p+i+n+u+g+s+m+c+sha256

# Critical system configuration
/etc OMARCHY

# Executables and system libraries
/usr/bin OMARCHY
/usr/sbin OMARCHY
/usr/lib OMARCHY

# Locally installed executables
/usr/local/bin OMARCHY
/usr/local/sbin OMARCHY

# Boot files and boot configuration
/boot OMARCHY

# Exclude volatile or frequently changing locations.
!/etc/mtab
!/etc/resolv.conf
EOF

chmod 0640 "$AIDE_CONFIG"

if ! aide --config="$AIDE_CONFIG" --config-check; then
    echo "AIDE configuration validation failed."
    echo "Inspect $AIDE_CONFIG before continuing."
    exit 1
fi

# Initialize a baseline only if one does not already exist.
if [[ ! -f /var/lib/aide/omarchy-aide.db ]]; then
    echo
    echo "Creating the initial AIDE baseline."
    echo "This may take several minutes..."

    aide --config="$AIDE_CONFIG" --init

    if [[ ! -f /var/lib/aide/omarchy-aide.db.new ]]; then
        echo "AIDE did not produce its expected database."
        echo "Inspect the AIDE output before continuing."
        exit 1
    fi

    mv /var/lib/aide/omarchy-aide.db.new \
       /var/lib/aide/omarchy-aide.db

    chmod 0600 /var/lib/aide/omarchy-aide.db

    echo "AIDE baseline created."
else
    echo "Existing AIDE baseline found; preserving it."
fi

# --------------------------------------------------
# 4. Create monitoring script
# --------------------------------------------------

echo "[4/8] Installing monitoring script..."

cat > "$CHECKER" <<'SCRIPT'
#!/usr/bin/env bash

set -uo pipefail

readonly LOG_DIR="/var/log/omarchy-security"
readonly STATE_DIR="/var/lib/omarchy-security"
readonly AIDE_CONFIG="/etc/aide/omarchy-aide.conf"

mkdir -p "$LOG_DIR" "$STATE_DIR"

TODAY="$(date +%F)"
REPORT="$LOG_DIR/check-$TODAY.log"
ISSUES=""

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" \
        | tee -a "$REPORT"
}

problem() {
    ISSUES+=$'\n'"$1"
    log "WARNING: $1"
}

# --------------------------------------------------
# Desktop notification
# --------------------------------------------------


notify_desktop() {
    local message="$1"
    local session uid type active runtime username display

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

        username="$(getent passwd "$uid" | cut -d: -f1)"
        [[ -n "$username" ]] || continue

        runtime="/run/user/$uid"
        display="$(loginctl show-session "$session" \
            -p Display --value 2>/dev/null || true)"

        if [[ -S "$runtime/bus" ]]; then
            runuser -u "$username" -- \
                env \
                XDG_RUNTIME_DIR="$runtime" \
                DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
                DISPLAY="$display" \
                notify-send \
                    --urgency=critical \
                    --icon=security-high \
                    --app-name="Omarchy Security" \
                    "⚠ SECURITY ALERT" \
                    "$message" \
                    >/dev/null 2>&1 || true

            return
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
}


# --------------------------------------------------
# 1. Audit daemon health
# --------------------------------------------------

log "Checking auditd..."

if ! systemctl is-active --quiet auditd; then
    problem "auditd is not running."
else
    AUDIT_STATUS="$(auditctl -s 2>/dev/null || true)"

    ENABLED="$(awk '$1=="enabled" {print $2}' <<< "$AUDIT_STATUS")"
    LOST="$(awk '$1=="lost" {print $2}' <<< "$AUDIT_STATUS")"
    BACKLOG="$(awk '$1=="backlog" {print $2}' <<< "$AUDIT_STATUS")"
    LIMIT="$(awk '$1=="backlog_limit" {print $2}' <<< "$AUDIT_STATUS")"

    if [[ "$ENABLED" != "1" ]]; then
        problem "Kernel audit subsystem is not enabled (enabled=$ENABLED)."
    fi

    if [[ "$LOST" =~ ^[0-9]+$ ]] && (( LOST > 0 )); then
        problem "Auditd has lost $LOST events."
    fi

    if [[ "$BACKLOG" =~ ^[0-9]+$ && "$LIMIT" =~ ^[0-9]+$ ]] \
       && (( LIMIT > 0 && BACKLOG * 100 / LIMIT >= 80 )); then
        problem "Audit backlog is at least 80% full ($BACKLOG/$LIMIT)."
    fi
fi

# --------------------------------------------------
# 2. Failed systemd services
# --------------------------------------------------

log "Checking failed systemd units..."

FAILED="$(systemctl --failed --no-legend --plain 2>/dev/null || true)"

if [[ -n "$FAILED" ]]; then
    problem "Failed systemd units detected: $FAILED"
fi

# --------------------------------------------------
# 3. AIDE file integrity check
# --------------------------------------------------

log "Checking file integrity with AIDE..."

AIDE_OUTPUT="$LOG_DIR/aide-$TODAY.log"

if aide --config="$AIDE_CONFIG" --check >"$AIDE_OUTPUT" 2>&1; then
    log "AIDE reports no file-integrity changes."
else
    problem "AIDE detected changes or an error. Inspect $AIDE_OUTPUT"
fi

# --------------------------------------------------
# 4. Check privileged file capabilities
# --------------------------------------------------

log "Checking privileged file capabilities..."

CAP_OUTPUT="$LOG_DIR/capabilities-$TODAY.txt"

if command -v getcap >/dev/null; then
    getcap -r /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin \
        >"$CAP_OUTPUT" 2>/dev/null || true

    if [[ -f "$STATE_DIR/capabilities.baseline" ]]; then
        if ! diff -u "$STATE_DIR/capabilities.baseline" "$CAP_OUTPUT" \
            >"$LOG_DIR/capabilities-diff-$TODAY.txt"; then
            problem "File capabilities changed. Inspect $LOG_DIR/capabilities-diff-$TODAY.txt"
        fi
    else
        cp "$CAP_OUTPUT" "$STATE_DIR/capabilities.baseline"
        log "Initial capabilities baseline created."
    fi
else
    log "getcap unavailable; skipping capability check."
fi

# --------------------------------------------------
# 5. Check for unexpected SUID/SGID files
# --------------------------------------------------

log "Checking SUID/SGID inventory..."

SUID_OUTPUT="$LOG_DIR/suid-$TODAY.txt"

find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin \
    -xdev -type f -perm /6000 -print 2>/dev/null \
    | sort > "$SUID_OUTPUT"

if [[ -f "$STATE_DIR/suid.baseline" ]]; then
    if ! diff -u "$STATE_DIR/suid.baseline" "$SUID_OUTPUT" \
        >"$LOG_DIR/suid-diff-$TODAY.txt"; then
        problem "SUID/SGID executable inventory changed. Inspect $LOG_DIR/suid-diff-$TODAY.txt"
    fi
else
    cp "$SUID_OUTPUT" "$STATE_DIR/suid.baseline"
    log "Initial SUID/SGID baseline created."
fi

# --------------------------------------------------
# 6. Check audit log and disk space
# --------------------------------------------------

log "Checking audit log and disk space..."

if [[ ! -s /var/log/audit/audit.log ]]; then
    problem "Audit log is missing or empty."
fi

DISK_USE="$(df -P /var/log | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

if [[ "$DISK_USE" =~ ^[0-9]+$ ]] && (( DISK_USE >= 90 )); then
    problem "Filesystem containing /var/log is ${DISK_USE}% full."
fi

# --------------------------------------------------
# 7. Report and notification
# --------------------------------------------------

if [[ -n "$ISSUES" ]]; then
    log "Security check completed with warnings."
    notify_desktop "Omarchy detected security issues. Review $REPORT"
else
    log "Security check completed. No monitored problems detected."
fi

# Keep 30 days of reports.
find "$LOG_DIR" -type f -mtime +30 -delete 2>/dev/null || true

SCRIPT

chmod 0750 "$CHECKER"

# --------------------------------------------------
# 5. Create daily systemd service and timer
# --------------------------------------------------

echo "[5/8] Configuring daily monitoring..."

cat > "$SERVICE" <<EOF
[Unit]
Description=Omarchy Security Monitoring
After=auditd.service

[Service]
Type=oneshot
ExecStart=$CHECKER
Nice=10
IOSchedulingClass=idle
EOF

cat > "$TIMER" <<'EOF'
[Unit]
Description=Daily Omarchy Security Monitoring

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
EOF

# --------------------------------------------------
# 6. Configure weekly Lynis audit
# --------------------------------------------------

echo "[6/8] Configuring weekly Lynis audit..."

cat > "$LYNIS_SERVICE" <<'EOF'
[Unit]
Description=Weekly Lynis Security Audit

[Service]
Type=oneshot
ExecStart=/usr/bin/lynis audit system --quick --no-colors
StandardOutput=append:/var/log/omarchy-security/lynis.log
StandardError=append:/var/log/omarchy-security/lynis.log
EOF

cat > "$LYNIS_TIMER" <<'EOF'
[Unit]
Description=Weekly Omarchy Lynis Audit

[Timer]
OnCalendar=Sun *-*-* 08:00:00
Persistent=true
RandomizedDelaySec=15min

[Install]
WantedBy=timers.target
EOF

# --------------------------------------------------
# 7. Enable timers
# --------------------------------------------------

echo "[7/8] Enabling monitoring timers..."

systemctl daemon-reload

systemctl enable --now omarchy-security-check.timer
systemctl enable --now omarchy-lynis.timer

# Run the first system check now.
systemctl start omarchy-security-check.service

# --------------------------------------------------
# 8. Finish
# --------------------------------------------------

echo
echo "============================================"
echo " Monitoring installation complete"
echo "============================================"

echo
echo "Daily monitoring:"
systemctl list-timers omarchy-security-check.timer --no-pager

echo
echo "Weekly Lynis audit:"
systemctl list-timers omarchy-lynis.timer --no-pager

echo
echo "AIDE baseline:"
ls -lh /var/lib/aide/omarchy-aide.db

echo
echo "Reports:"
echo "$LOG_DIR"

echo
echo "Manual commands:"
echo "  sudo omarchy-security-check"
echo "  sudo lynis audit system"
echo "  sudo aide --config=$AIDE_CONFIG --check"
echo "  sudo journalctl -u omarchy-security-check.service"
echo "  sudo systemctl list-timers"
echo
echo "IMPORTANT:"
echo "AIDE reports file changes; do not automatically update its baseline."
echo "Investigate changes before accepting a new baseline."
