#!/usr/bin/env bash
# harden.sh - repeats the hardening steps from the README on a fresh Ubuntu Server.
# Tested on Ubuntu Server 26.04.1 LTS in VirtualBox.
#
# Run it on the VM as a normal sudo user:
#   sudo bash scripts/harden.sh <admin-username>
#
# Before you run it:
#   1. Copy your SSH public key to the server (see README, step 6).
#   2. Test that key login works.
# The script stops if it finds no authorized key, so it cannot lock you out.

set -euo pipefail

ADMIN_USER="${1:-}"

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ -z "$ADMIN_USER" ]]; then
  echo "Usage: sudo bash $0 <admin-username>" >&2
  exit 1
fi

if ! id "$ADMIN_USER" &>/dev/null; then
  echo "User $ADMIN_USER does not exist. Create it first with: sudo adduser $ADMIN_USER" >&2
  exit 1
fi

KEY_FILE="/home/$ADMIN_USER/.ssh/authorized_keys"
if [[ ! -s "$KEY_FILE" ]]; then
  echo "No SSH key found in $KEY_FILE." >&2
  echo "Add your public key first, or this script would lock you out." >&2
  exit 1
fi

echo "[1/7] Updating the system"
apt-get update
apt-get upgrade -y

echo "[2/7] Enabling automatic security updates"
apt-get install -y unattended-upgrades
dpkg-reconfigure -plow unattended-upgrades

echo "[3/7] Adding $ADMIN_USER to the sudo group"
usermod -aG sudo "$ADMIN_USER"

echo "[4/7] Installing Fail2ban"
apt-get install -y fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

echo "[5/7] Hardening SSH"
# A drop-in file in sshd_config.d is read first, and the first value wins.
# This keeps my settings in force even if another file sets different values.
install -d -m 755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/00-hardening.conf << 'SSHCONF'
AddressFamily inet
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries 3
SSHCONF

# Check the config before restarting, so a typo cannot break SSH.
sshd -t
systemctl restart ssh

echo "[6/7] Configuring the firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable
ufw reload

echo "[7/7] Checking the result"
echo "--- SSH settings in effect ---"
sshd -T | grep -E '^(addressfamily|permitrootlogin|passwordauthentication|maxauthtries) '
echo "--- Fail2ban ---"
fail2ban-client status sshd
echo "--- Firewall ---"
ufw status verbose

echo
echo "Done. Open a second terminal and test your SSH login before you close this session."
echo "Then run: sudo lynis audit system"
