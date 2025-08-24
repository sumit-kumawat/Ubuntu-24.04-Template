#!/bin/bash
# ============================================
# Ubuntu 24.04 Production Template Setup Script
# With Progress Tracing & Deep Cleanup
# ============================================

set -e

# --- VARIABLES ---
USER="rdsroot"
SUDOERS_FILE="/etc/sudoers.d/${USER}"
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"

# --- FUNCTION for progress ---
progress() {
    PERCENT=$1
    MESSAGE=$2
    echo "[ ${PERCENT}% ] ${MESSAGE}"
}

# --- 1. Create superuser with root privileges ---
progress 10 "Checking superuser..."
if [ "$USER" != "root" ]; then
    if ! id -u $USER >/dev/null 2>&1; then
        adduser --disabled-password --gecos "" $USER
    fi
    usermod -aG sudo $USER || true
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | tee $SUDOERS_FILE >/dev/null
    chmod 440 $SUDOERS_FILE
else
    echo "Already running as root user, skipping user creation..."
fi

# --- 2. Install and enable SSH server ---
progress 20 "Installing SSH server..."
apt update -y >/dev/null 2>&1
apt install -y openssh-server >/dev/null 2>&1
systemctl enable ssh
systemctl start ssh

# --- 3. Install VMware Tools ---
progress 40 "Installing VMware Tools..."
apt install -y open-vm-tools open-vm-tools-desktop >/dev/null 2>&1

# Correct systemd unit (vmtoolsd is an alias in 24.04)
systemctl enable open-vm-tools
systemctl start open-vm-tools

# --- 4. Update system and install essential packages ---
progress 60 "Updating system & installing essential packages..."
apt update -y >/dev/null 2>&1 && apt upgrade -y >/dev/null 2>&1
apt install -y \
    curl wget git unzip zip htop net-tools \
    software-properties-common build-essential \
    apt-transport-https ca-certificates \
    gnupg lsb-release \
    iftop nmap tcpdump ufw unattended-upgrades \
    lvm2 >/dev/null 2>&1

# --- 5. Configure automatic updates ---
dpkg-reconfigure --priority=low unattended-upgrades >/dev/null 2>&1

# --- 6. Configure firewall & DHCP ---
progress 75 "Configuring firewall & DHCP network..."
ufw allow ssh >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

if [ -f $NETPLAN_FILE ]; then
    cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: true
EOF
    netplan apply >/dev/null 2>&1
fi

# --- 7. Set timezone ---
timedatectl set-timezone UTC >/dev/null 2>&1

# --- 8. Disable IPv6 ---
progress 85 "Disabling IPv6..."
cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl --system >/dev/null 2>&1

# Prevent duplicate entries in GRUB
if ! grep -q "ipv6.disable=1" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    update-grub >/dev/null 2>&1
fi

# --- 9. Cleanup: packages, logs, history ---
progress 95 "Cleaning up system..."

# Remove unused packages
apt autoremove --purge -y >/dev/null 2>&1
apt clean >/dev/null 2>&1

# Remove Snap (saves 5–7 GB if not needed)
apt purge -y snapd >/dev/null 2>&1 || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

# Truncate logs
find /var/log -type f -exec truncate -s 0 {} \;

# Clear journal logs (keep 1 day max)
journalctl --vacuum-time=1d >/dev/null 2>&1

# Clear bash history
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/$USER/.bash_history

# Clear apt lists
rm -rf /var/lib/apt/lists/*

# --- 10. Completion ---
progress 100 "Ubuntu 24.04 production template setup completed! 🚀"
echo "Reboot recommended: sudo reboot"

# --- Show VGS if available ---
if command -v vgs >/dev/null 2>&1; then
    echo ""
    echo "📊 LVM Volume Groups:"
    vgs || echo "No volume groups found."
fi
