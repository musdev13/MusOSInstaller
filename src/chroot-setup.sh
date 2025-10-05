#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Error handling
set -e
trap 'echo -e "${RED}Error: Configuration failed at line $LINENO${NC}"; exit 1' ERR

# Helper functions
print_step() {
    echo -e "${BLUE}==> $1${NC}"
}

# Check arguments
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 ROOT_PASSWORD USER_PASSWORD USERNAME"
    exit 1
fi

ROOT_PASSWORD="$1"
USER_PASSWORD="$2"
USERNAME="$3"

# Set hostname
print_step "Setting hostname..."
echo "musmaid" > /etc/hostname

# Set root password
print_step "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
print_step "Creating user..."
useradd -m -G wheel,video,audio,storage,optical,input "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure sudo
print_step "Configuring sudo..."
# Allow wheel group to use sudo without password during setup
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel_nopasswd
chmod 440 /etc/sudoers.d/wheel_nopasswd

# Configure network
print_step "Configuring network..."
systemctl enable NetworkManager
systemctl enable bluetooth

# Configure system
print_step "Configuring system..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Initialize pacman keyring
print_step "Initializing pacman keyring..."
pacman-key --init
pacman-key --populate archlinux

print_step "Chroot configuration completed successfully!"
exit 0