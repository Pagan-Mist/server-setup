#!/bin/bash
# setup-server.sh
# Run this as root or with sudo privileges

set -e

# === CONFIGURATION ===
USERNAME="pagan"
HOSTNAME="derpy"
# ======================

echo "Starting server setup..."

# Prompt for password securely
read -s -p "Enter password for user '$USERNAME': " PASSWORD
echo
read -s -p "Confirm password: " PASSWORD_CONFIRM
echo

# Verify the two match
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Error: passwords do not match. Exiting."
    exit 1
fi

# 1. Create user if not exists
if id "$USERNAME" &>/dev/null; then
    echo "User '$USERNAME' already exists."
else
    echo "Creating user '$USERNAME'..."
    adduser --gecos "" --disabled-password "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
fi

# 2. Add user to sudo group
echo "Adding '$USERNAME' to sudo group..."
usermod -aG sudo "$USERNAME"

# 3. Update and install packages
echo "Updating packages..."
apt update -y

echo "Installing Cockpit, btop, Fail2Ban, and UFW..."
apt install -y cockpit btop fail2ban ufw

# 4. Enable Cockpit service
echo "Enabling Cockpit service..."
systemctl enable --now cockpit.socket

# 5. Set hostname
echo "Setting hostname to '$HOSTNAME'..."
hostnamectl set-hostname "$HOSTNAME"

# 6. Configure UFW firewall
echo "Configuring UFW firewall..."

# Allow essential services
ufw allow OpenSSH
ufw allow 9090/tcp comment 'Cockpit Web UI'

# Enable firewall
ufw --force enable

echo "UFW configuration complete."
echo "Allowed ports:"
ufw status numbered

# 7. Enable Fail2Ban
echo "Enabling Fail2Ban service..."
systemctl enable --now fail2ban

# 8. Final summary
echo
echo "==============================="
echo "Setup complete!"
echo "User: $USERNAME"
echo "Hostname: $HOSTNAME"
echo "Cockpit Web UI: https://$(hostname -I | awk '{print $1}'):9090"
echo "==============================="
echo
echo "Rebooting in 5 seconds..."
sleep 5
reboot
