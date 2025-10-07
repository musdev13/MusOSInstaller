#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Error handling
set -e
trap 'echo -e "${RED}Error: Installation failed at line $LINENO${NC}"; exit 1' ERR

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

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

validate_arguments() {
    if [ "$#" -lt 3 ]; then
        echo "Usage: $0 TARGET_PARTITION EFI_PARTITION --root-pass ROOT_PASSWORD --user-pass USER_PASSWORD [--username USERNAME]"
        exit 1
    fi
}

# Main installation function
install_arch() {
    local target_partition="$1"
    local efi_partition="$2"
    local root_password="$3"
    local user_password="$4"
    local username="${5:-idk}"  # Default username if not provided

    # Validate inputs
    if [ ! -b "$target_partition" ]; then
        echo -e "${RED}Error: Target partition $target_partition does not exist${NC}"
        exit 1
    fi

    if [ ! -b "$efi_partition" ]; then
        echo -e "${RED}Error: EFI partition $efi_partition does not exist${NC}"
        exit 1
    fi

    # Format and mount partitions
    print_step "Formatting partitions..."
    mkfs.btrfs -f "$target_partition"
    
    # Ask about EFI partition formatting
    read -p "Would you like to format the EFI partition? (y/N): " format_efi
    if [[ "$format_efi" =~ ^[Yy]$ ]]; then
        mkfs.fat -F32 "$efi_partition"
    fi

    # Mount partitions
    print_step "Mounting partitions..."
    mount "$target_partition" /mnt
    mkdir -p /mnt/boot/efi
    mount "$efi_partition" /mnt/boot/efi

    # Install base system
    print_step "Installing base system..."
    pacstrap /mnt $(grep -v '^#' "$SCRIPT_DIR/pkgs.list" | tr '\n' ' ')

    # Generate fstab
    print_step "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab

    # Copy configuration scripts
    print_step "Preparing configuration scripts..."
    cp "$SCRIPT_DIR/chroot-setup.sh" /mnt/
    cp "$SCRIPT_DIR/user-setup.sh" /mnt/
    chmod +x /mnt/chroot-setup.sh /mnt/user-setup.sh
    cp "$SCRIPT_DIR/aur-pkgs.list" /mnt/

    # Configure system
    print_step "Configuring system..."
    arch-chroot /mnt ./chroot-setup.sh "$root_password" "$user_password" "$username"

    # Execute user setup script as the new user
    print_step "Setting up user environment..."
    cp /mnt/user-setup.sh "/mnt/home/$username/"
    chmod +x "/mnt/home/$username/user-setup.sh"
    arch-chroot /mnt /bin/bash -c "su - $username -c './user-setup.sh'"
    rm "/mnt/home/$username/user-setup.sh"

    # Copy rootfs files
    if [ -d "$SCRIPT_DIR/../rootfs" ]; then
        print_step "Copying rootfs files..."

        rsync -a --exclude 'home' "$SCRIPT_DIR/../rootfs/" /mnt/

        if [ -d "$SCRIPT_DIR/../rootfs/home/user" ]; then
            mkdir -p "/mnt/home/$username"
            rsync -a "$SCRIPT_DIR/../rootfs/home/user/" "/mnt/home/$username/"
        fi

	arch-chroot /mnt /bin/bash -c "chown -R $username:$username /home/$username"

        print_step "Changing plymouth theme..."
        arch-chroot /mnt /bin/bash -c "plymouth-set-default-theme spinner"

        print_step "Regenerating initramfs..."
        set +e
        print_step "Running mkinitcpio..."
        timeout 60 arch-chroot /mnt /bin/bash -c "mkinitcpio -P -v" || {
            local status=$?
            if [ $status -eq 124 ]; then
                print_warning "mkinitcpio timed out after 60 seconds, attempting to continue..."
            else
                print_warning "mkinitcpio exited with status $status, attempting to continue..."
            fi
        }

        sync
        set -e
    fi


    # Install GRUB
    print_step "Installing GRUB..."
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory="/boot/efi" --boot-directory="/boot" --bootloader-id=MusOSTest --recheck
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

    # Cleanup
    print_step "Cleaning up..."
    rm /mnt/chroot-setup.sh /mnt/user-setup.sh
    rm -rf /mnt/home/$username/.cache/yay/*
    # rm /mnt/etc/sudoers.d/wheel_nopasswd
    echo '%wheel ALL=(ALL:ALL) ALL' > /mnt/etc/sudoers.d/wheel_password
    chmod 440 /mnt/etc/sudoers.d/wheel_password
    print_success "Installation completed successfully!"
}

# Parse arguments
check_root
validate_arguments "$@"

TARGET_PARTITION="$1"
EFI_PARTITION="$2"
shift 2

while [[ $# -gt 0 ]]; do
    case $1 in
        --root-pass)
            ROOT_PASSWORD="$2"
            shift 2
            ;;
        --user-pass)
            USER_PASSWORD="$2"
            shift 2
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Start installation
install_arch "$TARGET_PARTITION" "$EFI_PARTITION" "$ROOT_PASSWORD" "$USER_PASSWORD" "$USERNAME"
