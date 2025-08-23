#!/bin/bash
# ============================================
# Ubuntu 24.04 Production Template Setup Script
# With Progress Tracing
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
progress 10 "Creating superuser..."
if ! id -u $USER >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" $USER
fi
usermod -aG sudo $USER
echo "$USER ALL=(ALL) NOPASSWD:ALL" | tee $SUDOERS_FILE >/dev/null
chmod 440 $SUDOERS_FILE

# --- 2. Install and enable SSH server ---
progress 20 "Installing SSH server..."
apt update -y >/dev/null 2>&1
apt install -y openssh-server >/dev/null 2>&1
systemctl enable ssh
systemctl start ssh

# --- 3. Install VMware Tools ---
progress 40 "Installing VMware Tools..."
apt install -y open-vm-tools open-vm-tools-desktop >/dev/null 2>&1
systemctl enable vmtoolsd
systemctl start vmtoolsd

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

# --- 6. Configure firewall ---
progress 75 "Configuring firewall & DHCP network..."
ufw allow ssh >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

# Configure DHCP
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
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf >/dev/null 2>&1

sed -i 's/GRUB_CMDLINE_LINUX="[^"]*/& ipv6.disable=1/' /etc/default/grub
update-grub >/dev/null 2>&1

# --- 9. Cleanup ---
progress 95 "Cleaning up..."
apt autoremove -y >/dev/null 2>&1
apt clean >/dev/null 2>&1

# --- 10. Completion ---
progress 100 "Ubuntu 24.04 production template setup completed! 🚀"
echo "Reboot recommended: sudo reboot"

# --- Show VGS if available ---
if command -v vgs >/dev/null 2>&1; then
    echo ""
    echo "📊 LVM Volume Groups:"
    vgs || echo "No volume groups found."
fi
