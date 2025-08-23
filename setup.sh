#!/bin/bash
# ============================================
# Ubuntu 24.04 Production Template Setup Script
# ============================================

set -e

# --- VARIABLES ---
USER="rdsroot"
SUDOERS_FILE="/etc/sudoers.d/${USER}"
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"

# --- 1. Create superuser with root privileges ---
if ! id -u $USER >/dev/null 2>&1; then
    echo "Creating user $USER..."
    adduser --disabled-password --gecos "" $USER
fi

usermod -aG sudo $USER
echo "$USER ALL=(ALL) NOPASSWD:ALL" | tee $SUDOERS_FILE
chmod 440 $SUDOERS_FILE
echo "User $USER now has root privileges without password prompt."

# --- 2. Install and enable SSH server ---
echo "Installing OpenSSH server..."
apt update -y
apt install -y openssh-server
systemctl enable ssh
systemctl start ssh
echo "SSH server is installed and running."

# --- 3. Install VMware Tools ---
echo "Installing Open VM Tools..."
apt install -y open-vm-tools open-vm-tools-desktop
systemctl enable vmtoolsd
systemctl start vmtoolsd
echo "VMware tools installed."

# --- 4. Update system and install essential packages ---
echo "Updating system and installing essential packages..."
apt update -y && apt upgrade -y
apt install -y \
    curl wget git unzip zip htop net-tools \
    software-properties-common build-essential \
    apt-transport-https ca-certificates \
    gnupg lsb-release \
    iftop nmap tcpdump ufw unattended-upgrades

# --- 5. Configure automatic updates ---
dpkg-reconfigure --priority=low unattended-upgrades

# --- 6. Configure firewall ---
ufw allow ssh
ufw --force enable
echo "Firewall configured to allow SSH."

# --- 7. Configure DHCP network ---
if [ -f $NETPLAN_FILE ]; then
    echo "Configuring DHCP for network..."
    cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: true
EOF
    netplan apply
    echo "DHCP network applied."
fi

# --- 8. Set timezone to UTC ---
timedatectl set-timezone UTC
echo "Timezone set to UTC."

# --- 9. Cleanup for template ---
apt autoremove -y
apt clean

echo "Ubuntu 24.04 production template setup completed!"
echo "Reboot recommended: sudo reboot"
