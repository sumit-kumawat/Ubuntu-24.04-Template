# Ubuntu 24.04 LTS Production Template Setup

This repository provides an **automated setup script** to prepare an Ubuntu 24.04 LTS virtual machine for production use as a VPS template. The script installs essential packages, configures SSH, sets up VMware Tools, applies security best practices, and prepares the system for cloning.

---

## Features

- Creates a superuser (`rdsroot`) with **root privileges** (no need for `sudo`).
- Installs and enables **OpenSSH Server**.
- Installs **Open VMware Tools** for VMware integration.
- Updates the system and installs **essential packages**:
  - curl, wget, git, unzip, zip, htop, net-tools
  - build-essential, software-properties-common, gnupg, lsb-release
  - Networking and monitoring tools: iftop, nmap, tcpdump
- Configures **automatic updates** for security patches.
- Enables **UFW firewall** and allows SSH.
- Configures **DHCP network** using Netplan.
- Sets **timezone to UTC**.
- Cleans up the system for **template creation**.

---

## Prerequisites

- Ubuntu 24.04 LTS VM installed (Desktop or Server).
- Access to the VM with a user having sudo privileges.
- VMware environment (optional, for VMware Tools).

---

## Installation & Usage

1. **Clone or download this repository**:

```bash
git clone https://github.com/sumit-kumawat/ubuntu-24-template.git
cd ubuntu-24-template
