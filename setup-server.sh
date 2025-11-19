#!/bin/bash
# setup-server.sh
# Run this as root or with sudo privileges

set -e

echo "===== VPS Setup Script ====="

# === USERNAME INPUT ===
read -rp "Enter the username to create: " USERNAME
if [ -z "$USERNAME" ]; then
    echo "Error: username cannot be empty."
    exit 1
fi

# === HOSTNAME INPUT ===
read -rp "Enter the hostname for this server: " HOSTNAME
if [ -z "$HOSTNAME" ]; then
    echo "Error: hostname cannot be empty."
    exit 1
fi

# === PASSWORD PROMPT ===
read -s -p "Enter password for user '$USERNAME': " PASSWORD
echo
read -s -p "Confirm password: " PASSWORD_CONFIRM
echo

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Error: passwords do not match. Exiting."
    exit 1
fi

echo "Creating and configuring user..."

# 1. Create user if not exists
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists."
else
    echo "Creating user '$USERNAME'..."
    adduser --gecos "" --disabled-password "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
fi

# 2. Add to sudoers
echo "Adding '$USERNAME' to sudo group..."
usermod -aG sudo "$USERNAME"

# ------------------------------
# PACKAGE INSTALLATION
# ------------------------------

echo "Updating system packages..."
apt update -y

echo "Installing required packages..."
apt install -y cockpit btop fail2ban nginx ufw curl unattended-upgrades cmatrix

# ------------------------------
# ENABLE CORE SERVICES
# ------------------------------

echo "Enabling Cockpit..."
systemctl enable --now cockpit.socket

echo "Enabling NGINX..."
systemctl enable --now nginx

# ------------------------------
# SECURITY: UNATTENDED UPGRADES
# ------------------------------

echo "Enabling unattended security upgrades..."
dpkg-reconfigure -plow unattended-upgrades

# ------------------------------
# HOSTNAME CONFIG
# ------------------------------

echo "Setting hostname to '$HOSTNAME'..."
hostnamectl set-hostname "$HOSTNAME"

# ------------------------------
# FIREWALL SETUP
# ------------------------------

echo "Configuring UFW firewall..."
ufw --force reset
ufw allow OpenSSH
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 9090/tcp comment 'Cockpit'
ufw --force enable

# ------------------------------
# FAIL2BAN HARDENING
# ------------------------------

echo "Applying Fail2Ban hardening..."

cat >/etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 4
backend = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 4

[nginx-http-auth]
enabled = true

[nginx-badbots]
enabled = true

[nginx-noscript]
enabled = true

[nginx-nohome]
enabled = true

[nginx-noproxy]
enabled = true
EOF

systemctl restart fail2ban
echo "Fail2Ban hardening applied."

# ------------------------------
# SSH HARDENING
# ------------------------------

echo "Hardening SSH configuration..."

# sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config

cat >> /etc/ssh/sshd_config << 'EOF'

# Hardened SSH Crypto Settings
KexAlgorithms curve25519-sha256@libssh.org
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com
EOF

systemctl restart sshd
echo "SSH hardening applied."

# ------------------------------
# SYSCTL HARDENING
# ------------------------------

echo "Applying system-level hardening (sysctl)..."

cat >/etc/sysctl.d/99-hardening.conf << 'EOF'
# Disable IP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Reverse path filtering (anti IP-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Kernel pointer protections
kernel.kptr_restrict = 2

# Restrict dmesg
kernel.dmesg_restrict = 1
EOF

sysctl --system
echo "Sysctl hardening applied."

# ------------------------------
# SUMMARY
# ------------------------------

SERVER_IP=$(hostname -I | awk '{print $1}')

echo
echo "==============================="
echo "Setup complete!"
echo "User: $USERNAME"
echo "Hostname: $HOSTNAME"
echo "Cockpit:  https://$SERVER_IP:9090"
echo "Website:  http://$SERVER_IP/"
echo "Web root: /var/www/html"
echo "==============================="
echo

echo "Rebooting in 5 seconds..."
sleep 5
reboot
