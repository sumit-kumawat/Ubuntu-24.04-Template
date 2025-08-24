#!/bin/bash
# ============================================
# Ubuntu 24.04 Production Template Setup Script
# Clean Progressbar + Auto Disk Extension + Full Logs
# ============================================

LOG_FILE="/var/log/template-setup.log"
USER="rdsroot"
SUDOERS_FILE="/etc/sudoers.d/${USER}"
NETPLAN_FILE="/etc/netplan/00-installer-config.yaml"
TOTAL_STEPS=12
CURRENT_STEP=0

# --- Ensure log file exists ---
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
    ("$@" &>> $LOG_FILE) &
    pid=$!
    spinner $pid
    wait $pid
    echo "✅ $message completed."
}

# --- 1. Create superuser if not exists ---
if ! id -u $USER >/dev/null 2>&1; then
    run_step "Creating superuser $USER..." adduser --disabled-password --gecos "" $USER
    echo "$USER:1Rs50U\$D" | chpasswd &>> $LOG_FILE
else
    echo "$USER already exists, skipping..."
fi
run_step "Adding $USER to sudo group..." usermod -aG sudo $USER || true
echo "$USER ALL=(ALL) NOPASSWD:ALL" | tee $SUDOERS_FILE >/dev/null
chmod 440 $SUDOERS_FILE
echo "root:Adm1n@123" | chpasswd &>> $LOG_FILE

# --- 2. Install and configure SSH ---
run_step "Updating package cache..." apt update -y &>> $LOG_FILE
run_step "Installing openssh-server..." apt install -y openssh-server &>> $LOG_FILE
run_step "Enabling SSH service..." systemctl enable ssh &>> $LOG_FILE || true
run_step "Starting SSH service..." systemctl restart ssh &>> $LOG_FILE || true

# --- 3. Install VMware Tools ---
run_step "Installing VMware Tools..." apt install -y open-vm-tools open-vm-tools-desktop &>> $LOG_FILE
if systemctl list-unit-files | grep -q "open-vm-tools.service"; then
    run_step "Enabling open-vm-tools..." systemctl enable open-vm-tools &>> $LOG_FILE || true
    run_step "Starting open-vm-tools..." systemctl start open-vm-tools &>> $LOG_FILE || true
fi

# --- 4. Update system & install essentials ---
run_step "Upgrading system..." apt upgrade -y &>> $LOG_FILE
run_step "Installing essential packages..." apt install -y \
    curl wget git unzip zip htop net-tools \
    software-properties-common build-essential \
    apt-transport-https ca-certificates \
    gnupg lsb-release iftop nmap tcpdump ufw unattended-upgrades lvm2 &>> $LOG_FILE

# --- 5. Configure automatic updates ---
run_step "Configuring unattended-upgrades..." dpkg-reconfigure --priority=low unattended-upgrades &>> $LOG_FILE

# --- 6. Firewall & DHCP ---
ufw allow ssh &>> $LOG_FILE || true
ufw --force enable &>> $LOG_FILE || true
if [ -f $NETPLAN_FILE ]; then
    run_step "Configuring DHCP on ens33..." bash -c "cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    ens33:
      dhcp4: true
EOF
netplan apply" &>> $LOG_FILE
fi

# --- 7. Timezone ---
run_step "Setting timezone to UTC..." timedatectl set-timezone UTC &>> $LOG_FILE

# --- 8. Disable IPv6 ---
run_step "Disabling IPv6..." bash -c "cat <<EOF > /etc/sysctl.d/99-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl --system &>> $LOG_FILE"
if ! grep -q "ipv6.disable=1" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="ipv6.disable=1 /' /etc/default/grub
    update-grub &>> $LOG_FILE
fi

# --- 9. Cleanup system ---
run_step "Cleaning system..." bash -c "apt autoremove --purge -y && apt clean -y && rm -rf /var/lib/apt/lists/*" &>> $LOG_FILE
run_step "Purging Snap (optional)..." bash -c "apt purge -y snapd || true; rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd" &>> $LOG_FILE
run_step "Truncating logs..." bash -c "find /var/log -type f -exec truncate -s 0 {} \;" &>> $LOG_FILE
run_step "Clearing old journals..." journalctl --vacuum-time=1d &>> $LOG_FILE
run_step "Clearing bash histories..." bash -c "unset HISTFILE; rm -f /root/.bash_history /home/$USER/.bash_history" &>> $LOG_FILE

# --- 10. Disk extension if unallocated space exists ---
ROOT_DISK=$(lsblk -dpno NAME,SIZE | grep -w "/dev/sda" | awk '{print $1}')
PARTITION=$(lsblk -dpno NAME,MOUNTPOINT | grep "/" | awk '{print $1}')
AVAIL_SPACE=$(lsblk -b $ROOT_DISK | awk 'NR==2{print $4}') # unallocated space in bytes

if [ $AVAIL_SPACE -gt 104857600 ]; then
    progress "Extending root partition automatically..."
    run_step "Resizing partition $PARTITION..." growpart $ROOT_DISK 2 &>> $LOG_FILE || true
    run_step "Resizing filesystem..." resize2fs $PARTITION &>> $LOG_FILE || true
    echo "✅ Root partition extended automatically."
else
    echo "⚠️ No unallocated space available to extend root."
fi

# --- 11. Completion & reboot ---
progress "Setup completed! 🚀"
echo ""
echo "✅ Full setup finished. Logs saved at $LOG_FILE"
echo "Rebooting in 5 seconds..."
sleep 5
reboot
