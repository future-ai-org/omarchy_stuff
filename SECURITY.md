# 🔒 Security Considerations

<br>

---

### Running Services

<br>

Check:

```
systemctl list-units --type=service -–state=running
```

<br>

Check enabled services:

```
systemctl list-unit-files -–state=enabled
```

<br>

Check failed services:

```
systemctl -–failed
```

<br>

Disable unused services:

```
sudo systemctl disable --now cups.service
sudo systemctl disable --now bolt.service // sudo systemctl mask bolt.service
sudo systemctl disable --now docker.socket
sudo systemctl disable --now docker.service

systemctl is-enabled cups.service bolt.service
```

<br>

If you don’t use docker, remove:

```
sudo systemctl stop docker.service
sudo systemctl disable docker.service
sudo pacman -Rns docker docker-buildx docker-compose containerd runc ufw-docker lazydocker
sudo rm -rf /var/lib/docker
```

<br>

---

### Ports and Processes

<br>

Check listening ports:

```
sudo pacman -S lsof
sudo ss -tulpn

# All listening sockets, including process ownership
sudo ss -tulpne

# Listening TCP ports
sudo ss -lntp

# Listening UDP ports
sudo ss -lnup

# Processes listening on network interfaces
sudo lsof -i -P -n | grep LISTEN
```

<br>

Check unusual processes:

```
ps aux --sort=-%cpu | head -20
```

<br>

---

### Forensics (for the above)

<br>

Inspect network interfaces, routes, and listening sockets:

```
ip -brief address
ip route
ss -tulpn
sudo ss -tulpn
sudo ss -ulpn
sudo ss -ulpne
sudo ss -tunap
```

<br>

Inspect the firewall:

```
sudo ufw status verbose
sudo ufw status numbered
```

<br>

Inspect active services and enabled units:

```
systemctl --failed
systemctl list-units --type=service --state=running
systemctl list-unit-files --state=enabled --no-pager
systemctl status rsyslog --no-pager
systemctl status docker docker.socket containerd --no-pager
```

<br>

Check remote logging configuration:

```
grep -RniE '(@@?|omfwd|Target=)' /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null
```

<br>

Check whether the modules are loaded and inspect their metadata:

```
for module in dccp sctp rds tipc; do
    echo
    echo "--- $module ---"

    if lsmod | grep -q "^${module}"; then
        echo "LOADED"
    else
        echo "NOT LOADED"
    fi

    modinfo "$module" 2>/dev/null |
        grep -E '^(filename|description|depends):' ||
        echo "MODULE NOT AVAILABLE"
done
```

<br>

Check for active sockets and existing module configuration:

```
ss -A dccp -a 2>/dev/null
ss -A sctp -a 2>/dev/null

grep -RniE 'dccp|sctp|rds|tipc' \
    /etc/modprobe.d/ /etc/modules-load.d/ 2>/dev/null || true

lsmod | grep -E '^(dccp|sctp|rds|tipc)' ||
    echo "All four protocols are unloaded."
```

<br>

Inspect kernel security settings:

```
sysctl kernel.randomize_va_space
sysctl kernel.kptr_restrict
sysctl kernel.dmesg_restrict
sysctl kernel.unprivileged_bpf_disabled
```

<br>

Inspect system and network configuration:

```
cat /etc/os-release
uname -r
hostnamectl

ip -brief address
ip route
ss -tulpn

lsmod | grep -E 'firewire|dccp|sctp|rds|tipc' || true
```

<br>

Check which process owns the port:

```
sudo lsof -i :PORT-NUMBER-HERE
sudo ss -ulpn | grep PORT-NUMBER-HERE
sudo ss -lunp 'sport = :PORT-NUMBER-HERE'
sudo ss -ulpne 'sport = :PORT-NUMBER-HERE'
sudo fuser -v PORT-NUMBER-HERE/udp
```

<br>

Inspect NetworkManager and DNS configuration:

```
NetworkManager --print-config
NetworkManager --version
resolvectl status
nmcli connection show
nmcli connection show --active
pacman -Qi networkmanager
sudo pacman -Qo /usr/bin/NetworkManager
```

<br>

If your VPN dont support ipv6, disable it to prevent leaks:

```
sudo nvim /etc/sysctl.d/70-disable-ipv6.conf
```

with

```
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
```

<br>

Search NetworkManager configuration and logs for the port:

```
sudo grep -R "PORT-NUMBER-HERE" /etc/NetworkManager /usr/lib/NetworkManager 2>/dev/null

sudo journalctl -u NetworkManager -b --no-pager |
    grep -iE 'dns|dhcp|connectivity|PORT-NUMBER-HERE'
```
    
<br>

Inspect the UDP tables and socket ownership:

```
sudo cat /proc/net/udp
sudo cat /proc/net/udp6

sudo grep -R "PORT-NUMBER-HERE" /proc/*/net/udp /proc/*/net/udp6 2>/dev/null

sudo ls -l /proc/$(pidof NetworkManager)/fd

sudo find /proc/[0-9]*/fd \
    -lname 'socket:[31068]' -o -lname 'socket:[31069]' 2>/dev/null

sudo find /proc/[0-9]*/fd \
    -lname 'socket:[31068]' 2>/dev/null

sudo find /proc/[0-9]*/fd \
    -lname 'socket:[31069]' 2>/dev/null
```

<br>

Inspect network namespaces and NetworkManager service restrictions:

```
sudo lsns -t net
sudo readlink /proc/$(pidof NetworkManager)/ns/net
sudo readlink /proc/1/ns/net

systemctl show NetworkManager \
    -p MainPID \
    -p ControlGroup \
    -p PrivateNetwork \
    -p NetworkNamespacePath \
    -p RestrictAddressFamilies
```

<br>

Block inbound traffic to suspicious port:

```
sudo ufw deny in PORT-NUMBER-HERE/udp
```

<br>

Disable unused network protocol modules (modprobe file):

```
sudo tee /etc/modprobe.d/disable-unused-protocols.conf <<'EOF'
# Disable unused network protocols (Lynis NETW-3200)
install sctp /usr/bin/false
install rds /usr/bin/false
install tipc /usr/bin/false
blacklist sctp
blacklist rds
blacklist tipc
EOF
```

<br>

Verify the resulting configuration and module behavior:

```
cat /etc/modprobe.d/disable-unused-protocols.conf
modprobe -n -v sctp
modprobe -n -v rds
modprobe -n -v tipc
```

<br>

Remove obsolete UFW rules by rule number:
```
sudo ufw status numbered
sudo ufw delete RULE_NUMBER
```

<br>

---

### Firewall and Network

<br>

Check firewall:

```
sudo ufw status verbose
```

to have:

```
Status: active
Default: deny (incoming), allow (outgoing)
```

<br>

Check active network process:

```
ss -tunap
```

<br>

Disable unecessary network discovery (should return inattive):

```
systemctl is-active avahi-daemon.service
systemctl is-active avahi-daemon.socket
```

<br>

Check active connections:

```
nmcli connection show –active
```

<br>

---

### System

<br>

> Set a bios/uefi password and enable secure boot.

<br>

Keep the system updated:

```
omarchy-update
```

<br>

Check package verification: 

```
pacman -Qkk
```

<br>

Also, updates and audit packages:

```
sudo pacman -Syu
arch-audit -u
```

<br>

Uset  `flatpak` for unstrsuted desktop applications:

```
sudo pacman -S flatpak
flatpak list
```

<br>

Verify full-disk encryption (`crypto_luks`):

```
lsblk -f
```

<br>


Make sure

```
chmod 700 "$HOME"
```

<br>

---

### Malware Rootkit Detection

<br>

Clam:

```
sudo pacman -S clamav
sudo freshclam
clamscan -r -i "$HOME"
sudo clamscan -r -i / \
  --exclude-dir="^/sys" \
  --exclude-dir="^/proc" \
  --exclude-dir="^/dev" \
--log="/var/log/clamscan_full.log"
```

<br>

Lynis:

```
sudo pacman -S lynis
sudo lynis audit system
```

<br>

Rkhunter:

```
sudo pacman -S rkhunter
sudo rkhunter –update
sudo rkhunter –check
```

<br>

if you get some legitimate service:

```
sudo nvim /etc/rkhunter.conf
```

add:

```
SCRIPTWHITELIST="/usr/bin/egrep"
SCRIPTWHITELIST="/usr/bin/fgrep"
SCRIPTWHITELIST="/usr/bin/ldd"
```

<br>


Avoid bad USB:

```
sudo pacman -S usbguard
sudo usbguard generate-policy | sudo tee /etc/usbguard/usbguard-daemon.conf > /dev/null
sudo usbguard generate-policy > /etc/usbguard/usbguard-conf.conf
sudo systemctl status usbguard.service
sudo systemctl enable --now usbguard.service
```

<br>

---

### Logs

<br>

Look at system logs:

```
sudo journalctl -u sshd
````

<br>

Check recent login sessions:

```
last -a
````

<br>

and recent authentication records:

```
sudo journalctl -u sshd
sudo journalctl -b | grep -Ei 'authentication failure|failed password|sudo:'
````

<br>

---

### Hyperland Permissions

<br>

```
pacman -Q hyprland hyprland-guiutils
sudo nvim ~/.config/hypr/hyprland.lua
```

<br>

add:

```
-- Screen capture: require approval
hl.permission({
    binary = ".*",
    type = "screencopy",
    mode = "deny"
})

-- Keyboard and mouse input capture: require approval
hl.permission({
    binary = ".*",
    type = "input-capture",
    mode = "deny"
})

-- Plugin loading: require approval
hl.permission({
    binary = ".*",
    type = "plugin",
    mode = "ask"
})

-- Cursor tracking: require approval
hl.permission({
    binary = ".*",
    type = "cursorpos",
    mode = "deny"
})
```

<br>

---

### Access Control and Secure Boot

<br>

```
# Install and enable AppArmor
sudo pacman -S apparmor
sudo systemctl enable --now apparmor

# Verify kernel support
zgrep CONFIG_SECURITY_APPARMOR /proc/config.gz

# Inspect bootloader and kernel parameters
bootctl status
cat /proc/cmdline

# Verify active Linux Security Modules
cat /sys/kernel/security/lsm

# Verify AppArmor profiles and enforcement
sudo aa-status

# Update Limine configuration
sudo limine-update
```
<br>

Check bootchain integrity:

```
sudo pacman -S sbctl
sudo sbctl status

# Verify EFI binaries
sudo sbctl verify
```

<br>

---

### SSH

<br>

```
sudo nvim /etc/ssh/sshd_config
```

with:

```
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
AllowAgentForwarding no
AllowUsers yourusername
```

or disable it:

```
sudo systemctl stop sshd
sudo systemctl disable sshd
sudo systemctl stop sshd.socket sshd.service
sudo systemctl disable sshd.socket sshd.service
```

<br>


---

### No Remote Logging

<br>

```
grep -RniE '(@@?|omfwd|Target=)' /etc/rsyslog.conf /etc/rsyslog.d/ 2>/dev/null
systemctl status rsyslog –no-pager
```

<br>

---

### Disable Unused Protocols

<br>

```
sudo tee /etc/modprobe.d/disable-unused-protocols.conf <<'EOF'
install sctp /usr/bin/false
install rds /usr/bin/false
install tipc /usr/bin/false

blacklist sctp
blacklist rds
blacklist tipc
EOF
```

verify config:

```
cat /etc/modprobe.d/disable-unused-protocols.conf

modprobe -n -v sctp
modprobe -n -v rds
modprobe -n -v tipc
```

<br>

verify nothing is loaded:

```
lsmod | grep -E '^(dccp|sctp|rds|tipc)' || echo "All four protocols are unloaded."
```

<br>

---

### Hardening Kernel 

<br>

```
sudo nvim /etc/sysctl.d/99-hardening.conf
```

with

```
# Restrict TTY line discipline autoloading
dev.tty.ldisc_autoload = 0
# Protect FIFOs and regular files in world-writable sticky directories
fs.protected_fifos = 2
fs.protected_regular = 2
# Prevent suid processes from dumping core
fs.suid_dumpable = 0
# Disable kernel module loading after boot (uncomment only if you do not load modules post-boot)
# kernel.modules_disabled = 1
# Restrict Magic SysRq key functions
kernel.sysrq = 0
# Harden BPF Just-In-Time compiler
net.core.bpf_jit_harden = 2
# Log martian packets (packets with impossible routing addresses) on all interfaces
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
```

<br>

---

### Check unexpected kernel modules

<br>

```
lsmod
```

<br>

---

### Security Hardening Scripts

<br>

#### Check [`scripts/security/`](scripts/security/).

<br>
