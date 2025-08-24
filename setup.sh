#!/bin/bash
# ============================================
# Ubuntu 24.04 Production Template Setup Script
# With Live Progress Bar & Deep Cleanup
# ============================================

set -e

# --- VARIABLES ---
USER="rdsroot"
USER_PASS="1Rs50U\$D"
ROOT_PASS="Adm1n@123"
SUDOERS_FILE="/etc/sudoers.d/${USER}"
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"

# --- FUNCTION: Progress bar ---
progress() {
    local percent=$1
    local message=$2
    local bar_len=50
    local filled=$((percent * bar_len / 100))
    local empty=$((bar_len - filled))
    printf "\r[%-${bar_len}s] %3d%%  %s" $(printf '#%.0s' $(seq 1 $filled)) $percent "$message"
    if [ $percent -eq 100 ]; then
        echo ""
    fi
}

# --- 1. Superuser setup ---
progress 10 "Checking superuser..."
if [ "$USER" != "root" ]; then
    if ! id -u $USER >/dev/null 2>&1; then
        adduser --disabled-password --gecos "" $USER
        echo "${USER}:${USER_PASS}" | chpasswd
    fi
    usermod -aG sudo $USER || true
    if [ ! -f "$SUDOERS_FILE" ]; then
        echo "$USER ALL=(ALL) NOPASSWD:ALL" | tee $SUDOERS_FILE >/dev/null
        chmod 440 $SUDOERS_FILE
    fi
else
    echo "Already running as root user, skipping user creation..."
fi

# --- Root password ---
echo "root:${ROOT_PASS}" | chpasswd

# --- 2. SSH server ---
progress 20 "Installing SSH server..."
if ! dpkg -l | grep -q openssh-server; then
    apt update -y >/dev/null 2>&1
    apt install -y openssh-server >/dev/null 2>&1
fi
systemctl enable ssh >/dev/null 2>&1
systemctl start ssh >/dev/null 2>&1

# --- 3. VMware Tools ---
progress 40 "Installing VMware Tools..."
if ! dpkg -l | grep -q open-vm-tools; then
    apt install -y open-vm-tools open-vm-tools-desktop >/dev/null 2>&1
fi
if systemctl list-unit-files | grep -q "open-vm-tools.service"; then
    systemctl enable open-vm-tools >/dev/null 2>&1
    systemctl start open-vm-tools >/dev/null 2>&1
fi

# --- 4. Essentials ---
progress 60 "Updating system & installing essentials..."
apt update -y >/dev/null 2>&1 && apt upgrade -y >/dev/null 2>&1
apt install -y \
    curl wget git unzip zip htop net-tools \
    software-properties-common build-essential \
    apt-transport-https ca-certificates \
    gnupg lsb-release \
    iftop nmap tcpdump ufw unattended-upgrades \
    lvm2 >/dev/null 2>&1

# --- 5. Auto-updates ---
dpkg-reconfigure --priority=low unattended-upgrades >/dev/null 2>&1 || true

# --- 6. Firewall & DHCP ---
progress 75 "Configuring firewall & network..."
ufw allow ssh >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

if [ -f $NETPLAN_FILE ]; then
    cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: true
EOF
    netplan apply >/dev/null 2>&1 || true
fi

# --- 7. Timezone ---
timedatectl set-timezone UTC >/dev/null 2>&1

# --- 8. Disable IPv6 ---
progress 85 "Disabling IPv6..."
cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl --system >/dev/null 2>&1
if ! grep -q "ipv6.disable=1" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    update-grub >/dev/null 2>&1
fi

# --- 9. Cleanup ---
progress 95 "Cleaning up..."
apt autoremove --purge -y >/dev/null 2>&1
apt clean >/dev/null 2>&1
apt purge -y snapd >/dev/null 2>&1 || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
find /var/log -type f -exec truncate -s 0 {} \;
journalctl --vacuum-time=1d >/dev/null 2>&1
unset HISTFILE
rm -f /root/.bash_history /home/$USER/.bash_history
rm -rf /var/lib/apt/lists/*

# --- 10. Done ---
progress 100 "Setup completed! 🚀"
echo "Reboot recommended: sudo reboot"

if command -v vgs >/dev/null 2>&1; then
    echo -e "\n📊 LVM Volume Groups:"
    vgs || echo "No volume groups found."
fi
