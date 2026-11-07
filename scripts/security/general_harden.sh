#!/usr/bin/env bash
#
# Every changed file is backed up to /root/hardening-backup-<timestamp>/.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this with sudo: sudo bash $0" >&2
  exit 1
fi

AUTO=no
[[ "${1:-}" == "--yes" ]] && AUTO=yes

BACKUP="/root/hardening-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

ask() {
  [[ $AUTO == yes ]] && return 0
  local reply
  read -r -p $'\n'"$1 [y/N] " reply
  [[ $reply =~ ^[Yy]$ ]]
}

backup() {
  for f in "$@"; do
    [[ -e $f ]] && cp -a --parents "$f" "$BACKUP/"
  done
  return 0
}

msg() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Kernel sysctl hardening  [KRNL-6000]
#    Creates: /etc/sysctl.d/99-hardening.conf
#    kernel.modules_disabled=1 is deliberately NOT set: it would stop Wi-Fi,
#    USB and other drivers from loading after boot on a laptop.
# ---------------------------------------------------------------------------
if ask "1) Apply kernel sysctl hardening (tty ldisc, fifos, suid dumps, sysrq, BPF JIT, martian logging)?"; then
  backup /etc/sysctl.d/99-hardening.conf
  cat > /etc/sysctl.d/99-hardening.conf <<'EOF'
# Lynis KRNL-6000 recommendations
dev.tty.ldisc_autoload = 0
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
# Disables the Magic SysRq key. If you rely on Alt+SysRq+REISUB to recover
# a frozen machine, change this to 176 (allows sync, remount-ro, reboot only).
kernel.sysrq = 0
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
EOF
  sysctl --system >/dev/null
  msg "sysctl settings applied"
fi

# ---------------------------------------------------------------------------
# 2. Disable core dumps  [KRNL-5820]
#    Creates: /etc/systemd/coredump.conf.d/99-disable.conf
#    Appends one line to /etc/security/limits.conf
#    Skip this if you debug crashing programs and want their core dumps.
# ---------------------------------------------------------------------------
if ask "2) Disable core dumps (they can leak passwords/keys from memory to disk)?"; then
  backup /etc/security/limits.conf
  mkdir -p /etc/systemd/coredump.conf.d
  cat > /etc/systemd/coredump.conf.d/99-disable.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
  grep -qE '^\*\s+hard\s+core\s+0' /etc/security/limits.conf \
    || echo '*    hard    core    0' >> /etc/security/limits.conf
  systemctl daemon-reload
  msg "core dumps disabled"
fi

# ---------------------------------------------------------------------------
# 3. Block unused network protocols and FireWire  [NETW-3200, STRG-1846]
#    Creates: /etc/modprobe.d/99-hardening.conf
#    FireWire DMA is a classic physical attack vector; almost no modern
#    laptop needs it.
# ---------------------------------------------------------------------------
if ask "3) Block rarely used kernel modules (dccp, sctp, rds, tipc, firewire)?"; then
  backup /etc/modprobe.d/99-hardening.conf
  {
    echo "# Lynis NETW-3200 / STRG-1846"
    for m in dccp sctp rds tipc firewire-core firewire-ohci firewire-sbp2; do
      echo "blacklist $m"
      echo "install $m /bin/false"
    done
  } > /etc/modprobe.d/99-hardening.conf
  msg "modules blocked (takes full effect after reboot)"
fi

# ---------------------------------------------------------------------------
# 4. USBGuard rule file  [USB-3000 — "RuleFile NOT FOUND"]
#    USBGuard is running but has no rule file, so it is not really protecting
#    you. This writes a policy that allows ONLY the USB devices plugged in
#    right now. Plug in your usual keyboard, mouse, dock, YubiKey, etc. FIRST.
#    New devices later need:  sudo usbguard list-devices
#                             sudo usbguard allow-device <id> -p   (permanent)
# ---------------------------------------------------------------------------
if ask "4) Generate a USBGuard allow-list from currently connected USB devices? (plug in your usual devices first)"; then
  if ! command -v usbguard >/dev/null; then
    warn "usbguard not installed, skipping"
  else
    CONF=/etc/usbguard/usbguard-daemon.conf
    RULEFILE=$(grep -E '^RuleFile=' "$CONF" 2>/dev/null | cut -d= -f2 || true)
    RULEFILE=${RULEFILE:-/etc/usbguard/rules.conf}
    if [[ -s $RULEFILE ]]; then
      warn "$RULEFILE already exists and is not empty; leaving it alone"
    else
      backup "$CONF"
      grep -qE '^RuleFile=' "$CONF" || echo "RuleFile=$RULEFILE" >> "$CONF"
      usbguard generate-policy > "$RULEFILE"
      chmod 0600 "$RULEFILE"
      chown root:root "$RULEFILE"
      systemctl restart usbguard
      msg "USBGuard policy written to $RULEFILE ($(wc -l < "$RULEFILE") devices allowed)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 5. Package vulnerability auditing  [PKGS-7398]
#    Installs arch-audit, which checks installed packages against the
#    Arch Linux security tracker. Run it any time with:  arch-audit
# ---------------------------------------------------------------------------
if ask "5) Install arch-audit (checks your packages for known vulnerabilities)?"; then
  pacman -S --needed --noconfirm arch-audit
  msg "arch-audit installed — current results:"
  arch-audit || true
fi

# ---------------------------------------------------------------------------
# 6. Stricter default umask  [AUTH-9328]
#    New files become unreadable by other users (022 -> 027).
# ---------------------------------------------------------------------------
if ask "6) Set default umask to 027 in /etc/login.defs?"; then
  backup /etc/login.defs
  if grep -qE '^UMASK' /etc/login.defs; then
    sed -i -E 's/^UMASK\s+.*/UMASK\t\t027/' /etc/login.defs
  else
    printf 'UMASK\t\t027\n' >> /etc/login.defs
  fi
  msg "umask set (applies at next login)"
fi

# ---------------------------------------------------------------------------
# 7. Small fixes: file permissions + /etc/hosts  [FILE-7524, NAME-4404]
# ---------------------------------------------------------------------------
if ask "7) Tighten sshd_config / cron.hourly permissions and add hostname to /etc/hosts?"; then
  [[ -f /etc/ssh/sshd_config ]] && chmod 600 /etc/ssh/sshd_config
  [[ -d /etc/cron.hourly ]] && chmod 700 /etc/cron.hourly
  HN=$(cat /etc/hostname 2>/dev/null || hostname)
  if ! grep -qwE "$HN" /etc/hosts; then
    backup /etc/hosts
    printf '127.0.1.1\t%s.localdomain\t%s\n' "$HN" "$HN" >> /etc/hosts
  fi
  msg "permissions and /etc/hosts updated"
fi

echo
msg "Done. Backups are in $BACKUP"
msg "Reboot, then re-run:  sudo lynis audit system"
