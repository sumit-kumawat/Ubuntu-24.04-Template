#!/bin/bash
# ============================================
# Ubuntu 24.04 Production Template Setup Script
# Clean progress display with hidden backend output
# ============================================

set -e

# --- VARIABLES ---
USER="rdsroot"

# --- SPINNER ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

# --- FUNCTION for progress ---
progress() {
    PERCENT=$1
    MESSAGE=$2
    printf "\r[ %3s%% ] %-60s" "$PERCENT" "$MESSAGE"
}

# --- ROOT CHECK ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root!"
    exit 1
fi

# --- 1. Create superuser ---
progress 10 "Checking/creating rdsroot user..."
if id "$USER" &>/dev/null; then
    sleep 1
else
    adduser --disabled-password --gecos "" $USER &>/dev/null &
    spinner $!
fi
usermod -aG sudo $USER &>/dev/null || true
echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER
chmod 440 /etc/sudoers.d/$USER

echo "rdsroot:1Rs50U\$D" | chpasswd &>/dev/null
echo "root:Adm1n@123" | chpasswd &>/dev/null

# --- 2. Install SSH server ---
progress 20 "Installing SSH server..."
apt update -y &>/dev/null &
spinner $!
apt install -y openssh-server &>/dev/null &
spinner $!
systemctl enable ssh &>/dev/null &
spinner $!
systemctl start ssh &>/dev/null &
spinner $!

# --- 3. Install VMware Tools ---
progress 30 "Installing VMware Tools..."
apt install -y open-vm-tools open-vm-tools-desktop &>/dev/null &
spinner $!
systemctl enable open-vm-tools &>/dev/null &
spinner $!
systemctl start open-vm-tools &>/dev/null &
spinner $!

# --- 4. Update system & essentials ---
progress 40 "Updating system..."
apt update -y &>/dev/null &
spinner $!
apt upgrade -y &>/dev/null &
spinner $!

progress 50 "Installing essential packages..."
apt install -y curl wget git unzip zip htop net-tools \
software-properties-common build-essential \
apt-transport-https ca-certificates \
gnupg lsb-release \
iftop nmap tcpdump ufw unattended-upgrades \
lvm2 &>/dev/null &
spinner $!

# --- 5. Configure unattended-upgrades ---
progress 60 "Configuring unattended-upgrades..."
dpkg-reconfigure --priority=low unattended-upgrades &>/dev/null &
spinner $!

# --- 6. Configure firewall & DHCP ---
progress 70 "Configuring firewall & DHCP..."
ufw allow ssh &>/dev/null &
spinner $!
ufw --force enable &>/dev/null &
spinner $!

NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
if [ -f $NETPLAN_FILE ]; then
    cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: true
EOF
    netplan apply &>/dev/null &
    spinner $!
fi

# --- 7. Set timezone ---
progress 80 "Setting timezone to UTC..."
timedatectl set-timezone UTC &>/dev/null &
spinner $!

# --- 8. Disable IPv6 ---
progress 85 "Disabling IPv6..."
cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl --system &>/dev/null &
spinner $!

# --- 9. Cleanup ---
progress 90 "Cleaning system..."
apt autoremove --purge -y &>/dev/null &
spinner $!
apt clean &>/dev/null &
spinner $!

# --- Purge Snap ---
progress 95 "Purging Snap (optional)..."
apt purge -y snapd &>/dev/null || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

# --- 10. Clear logs & history ---
progress 97 "Clearing logs and bash history..."
find /var/log -type f -exec truncate -s 0 {} \; &>/dev/null || true
journalctl --vacuum-time=1d &>/dev/null || true
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/$USER/.bash_history

# --- 11. Check root filesystem & extend disk ---
progress 99 "Checking root filesystem..."
ROOT_DEV=$(df / | tail -1 | awk '{print $1}')
ROOT_TOTAL=$(df -h / | tail -1 | awk '{print $2}')
ROOT_USED=$(df -h / | tail -1 | awk '{print $3}')
ROOT_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
echo -e "\n📊 Root Filesystem: $ROOT_DEV\n   Total Size: $ROOT_TOTAL\n   Used: $ROOT_USED\n   Available: $ROOT_AVAIL"

if [ $(echo $ROOT_AVAIL | sed 's/G//') -gt 1 ]; then
    read -p "⚠️ Additional disk space available. Extend root filesystem? (y/n): " extend_disk
    if [[ "$extend_disk" == "y" ]]; then
        lvextend -r -l +100%FREE $(lvdisplay | grep 'LV Path' | awk '{print $3}') &>/dev/null &
        spinner $!
    fi
fi

# --- 12. Completion ---
progress 100 "Setup completed! Rebooting in 5 seconds..."
sleep 5
reboot
