#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Error handling
set -e
trap 'echo -e "${RED}Error: User setup failed at line $LINENO${NC}"; cleanup; exit 1' ERR

# Helper functions
print_step() {
    echo -e "${BLUE}==> $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

print_success() {
    echo -e "${GREEN}==> $1${NC}"
}

cleanup() {
    if [ -d "/tmp/yay" ]; then
        rm -rf /tmp/yay
    fi
}

check_dependencies() {
    local deps=(git base-devel curl go)
    local missing=()

    for dep in "${deps[@]}"; do
        if ! pacman -Q "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        print_warning "Missing dependencies: ${missing[*]}"
        print_step "Installing missing dependencies..."
        # Use NOPASSWD sudo that should be configured in chroot-setup.sh
        if ! sudo -n true 2>/dev/null; then
            echo -e "${RED}Error: sudo is not configured with NOPASSWD for wheel group${NC}"
            echo "Please ensure /etc/sudoers contains: '%wheel ALL=(ALL:ALL) NOPASSWD: ALL'"
            exit 1
        fi
        sudo pacman -Sy --noconfirm "${missing[@]}"
    fi
}

install_yay() {
    print_step "Installing yay..."
    if command -v yay >/dev/null 2>&1; then
        print_warning "yay is already installed, skipping..."
        return 0
    fi

    cd /tmp
    rm -rf yay
    pwd
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
}

install_end4_dots() {
    print_step "Installing end4-dots..."
    if [ -f ~/.config/hypr/hyprland.conf ]; then
        print_warning "end4-dots configuration found, skipping..."
        return 0
    fi

    # Create temporary script file
    local tmp_script="/tmp/end4-dots-setup.sh"
    curl -s "https://ii.clsty.link/setup" -o "$tmp_script"
    
    if [ ! -f "$tmp_script" ]; then
        echo -e "${RED}Error: Failed to download end4-dots setup script${NC}"
        exit 1
    fi

    chmod +x "$tmp_script"
    bash "$tmp_script"
    rm -f "$tmp_script"
}

install_aur_packages() {
    local list_path="/aur-pkgs.list"

    if [ ! -f "$list_path" ]; then
        print_warning "aur-pkgs.list not found, skipping AUR package installation."
        return 0
    fi

    print_step "Installing AUR packages from aur-pkgs.list..."
    
    local packages
    packages=$(grep -v '^#' "$list_path" | tr '\n' ' ' | xargs)

    if [ -z "$packages" ]; then
        print_warning "aur-pkgs.list is empty."
        return 0
    fi

    yay -S --noconfirm --needed $packages
}


main() {
    print_step "Starting user environment setup..."
    
    # Ensure we're not running as root
    if [ "$(id -u)" -eq 0 ]; then
        echo -e "${RED}Error: This script should not be run as root${NC}"
        exit 1
    fi

    # Check and install dependencies
    check_dependencies

    # Install yay
    install_yay

    # Install end4-dots
    install_end4_dots

    # Install aur-pkgs
    install_aur_packages

    print_success "User setup completed successfully!"
}

# Run main function
main
exit 0
