#!/bin/bash
# ============================================
# Ubuntu 24.04 Production Template Setup Script
# Live Progressbar + Full Logs + Safe Execution
# ============================================

LOG_FILE="/var/log/template-setup.log"
USER="rdsroot"
SUDOERS_FILE="/etc/sudoers.d/${USER}"
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
TOTAL_STEPS=11
CURRENT_STEP=0

# Ensure log file exists
touch $LOG_FILE
chmod 644 $LOG_FILE

# --- Spinner Function ---
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid >/dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
}

# --- Progress Bar Function ---
progress() {
    CURRENT_STEP=$((CURRENT_STEP+1))
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    printf "\r[%3d%%] [%-*s%s] %s\n" "$percent" "$filled" "####################" "$(printf '%*s' "$empty")" "$1"
}

# --- Run Command with Spinner & Logging ---
run_step() {
    local message="$1"
    shift
    progress "$message"
    # Run command in background, log output
    ("$@" 2>&1 | tee -a $LOG_FILE) &
    pid=$!
    spinner $pid
    if wait $pid; then
        echo "✅ $message completed."
    else
        echo "⚠️ $message failed or skipped. Check $LOG_FILE"
    fi
}

# --- 1. Create superuser ---
if [ "$USER" != "root" ]; then
    if ! id -u $USER >/dev/null 2>&1; then
        run_step "Creating superuser $USER..." adduser --disabled-password --gecos "" $USER
        echo "$USER:1Rs50U\$D" | chpasswd | tee -a $LOG_FILE
    else
        echo "$USER already exists, skipping..."
    fi
    run_step "Adding $USER to sudo group..." usermod -aG sudo $USER || true
    echo "$USER ALL=(ALL) NOPASSWD:ALL" | tee $SUDOERS_FILE >/dev/null
    chmod 440 $SUDOERS_FILE
else
    echo "Already running as root, skipping user creation..."
fi

# Set root password
echo "root:Adm1n@123" | chpasswd | tee -a $LOG_FILE || true

# --- 2. Install SSH server ---
run_step "Updating package cache..." apt update -y
run_step "Installing openssh-server..." apt install -y openssh-server
run_step "Enabling SSH service..." systemctl enable ssh || true
run_step "Starting SSH service..." systemctl restart ssh || true

# --- 3. VMware Tools ---
run_step "Installing VMware Tools..." apt install -y open-vm-tools open-vm-tools-desktop
if systemctl list-unit-files | grep -q "open-vm-tools.service"; then
    run_step "Enabling open-vm-tools..." systemctl enable open-vm-tools || true
    run_step "Starting open-vm-tools..." systemctl start open-vm-tools || true
else
    echo "⚠️ open-vm-tools.service not found, skipping."
fi

# --- 4. Update & essentials ---
run_step "Upgrading system..." apt upgrade -y
run_step "Installing essential packages..." apt install -y \
    curl wget git unzip zip htop net-tools \
    software-properties-common build-essential \
    apt-transport-https ca-certificates \
    gnupg lsb-release iftop nmap tcpdump ufw unattended-upgrades lvm2

# --- 5. Automatic updates ---
run_step "Configuring unattended-upgrades..." dpkg-reconfigure --priority=low unattended-upgrades

# --- 6. Firewall & DHCP ---
ufw allow ssh >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true
if [ -f $NETPLAN_FILE ]; then
    run_step "Configuring DHCP on ens33..." bash -c "cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: true
EOF
netplan apply"
fi

# --- 7. Timezone ---
run_step "Setting timezone to UTC..." timedatectl set-timezone UTC

# --- 8. Disable IPv6 ---
run_step "Disabling IPv6..." bash -c "cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl --system"
if ! grep -q "ipv6.disable=1" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    update-grub
fi

# --- 9. Cleanup ---
run_step "Cleaning system..." bash -c "apt autoremove --purge -y && apt clean -y && rm -rf /var/lib/apt/lists/*"
run_step "Purging Snap (optional)..." bash -c "apt purge -y snapd || true; rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd"
run_step "Truncating logs..." bash -c "find /var/log -type f -exec truncate -s 0 {} \;"
run_step "Clearing old journals..." journalctl --vacuum-time=1d
run_step "Clearing bash histories..." bash -c "unset HISTFILE; rm -f /root/.bash_history /home/$USER/.bash_history"

# --- 10. Disk usage info (extension skipped) ---
progress "Checking root filesystem..."
ROOT_DISK=$(df -h / | awk 'NR==2 {print $1}')
USED=$(df -h / | awk 'NR==2 {print $3}')
AVAIL=$(df -h / | awk 'NR==2 {print $4}')
SIZE=$(df -h / | awk 'NR==2 {print $2}')

echo ""
echo "📊 Root Filesystem: $ROOT_DISK"
echo "   Total Size: $SIZE"
echo "   Used: $USED"
echo "   Available: $AVAIL"
echo ""
echo "⚠️ Disk extension task skipped. Continuing setup..."

# --- 11. Completion & Reboot ---
progress "Setup completed! 🚀"
echo ""
echo "✅ Full setup finished. Logs saved at $LOG_FILE"
echo "Rebooting in 5 seconds..."
sleep 5
reboot
