#!/bin/bash
# Complete UKI + Secure Boot setup for NVIDIA 580
# This script orchestrates all setup steps
# Run with: sudo /home/daen/Projects/sbh/bin/setup-complete-uki.sh

set -e

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must run as root (sudo)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  NVIDIA 580 + Secure Boot + UKI Complete Setup                 ║"
echo "║  For CachyOS with GTX 1050 Ti (Pascal 6.1)                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 0: Verify prerequisites
echo "Step 0: Verifying prerequisites..."
echo "  Checking UKI tools..."
pacman -Q mkinitcpio-uki-hook systemd-ukify sbctl efitools > /dev/null || {
  echo "ERROR: Required packages not installed"
  exit 1
}
echo "  ✓ All UKI tools present"
echo ""

# Step 1: MOK Key Generation
echo "Step 1: Generating MOK (Machine Owner Key)..."
if [ -f /root/MOK.key ] && [ -f /root/MOK.crt ]; then
  echo "  ✓ MOK keys already exist"
else
  echo "  Generating new keys (10-20 seconds)..."
  bash "$SCRIPT_DIR/setup-mok-keys.sh"
fi
echo ""

# Step 2: DKMS Automatic Module Signing
echo "Step 2: Configuring DKMS automatic module signing..."
bash "$SCRIPT_DIR/setup-dkms-signing.sh"
echo ""

# Step 3: UKI Generation Pacman Hook
echo "Step 3: Setting up automatic UKI generation..."
bash "$SCRIPT_DIR/setup-uki-hook.sh"
echo ""

# Step 4: Configure systemd-boot entry
echo "Step 4: Configuring systemd-boot entry..."
BOOT_CONF="/efi/loader/entries/cachyos.conf"

if [ ! -d /efi/loader/entries ]; then
  mkdir -p /efi/loader/entries
fi

cat > "$BOOT_CONF" << 'EOF'
title   CachyOS Linux (UKI + NVIDIA 580)
efi     /EFI/Linux/cachyos-linux.efi
EOF

echo "  ✓ systemd-boot entry created: $BOOT_CONF"
cat "$BOOT_CONF"
echo ""

# Step 5: Enroll MOK in Secure Boot
echo "Step 5: MOK Enrollment (requires reboot)..."
echo ""
echo "  To enroll the MOK key in Secure Boot:"
echo "    sudo mokutil --import /root/MOK.der"
echo ""
echo "  This will prompt you to set a MOK password on next reboot"
echo "  You'll see a blue shim screen - follow the enrollment steps"
echo ""

read -p "  Do you want to enroll MOK now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  bash "$SCRIPT_DIR/enroll-mok.sh"
  echo ""
  echo "⚠ Reboot required to complete MOK enrollment"
  read -p "  Reboot now? (y/n) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl reboot
  fi
else
  echo "  Skipping MOK enrollment for now"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Setup Complete!                                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "What's been configured:"
echo "  ✓ MOK keys generated and installed"
echo "  ✓ DKMS automatic module signing enabled"
echo "  ✓ Pacman hook for automatic UKI regeneration"
echo "  ✓ systemd-boot entry configured"
echo ""
echo "Next steps:"
echo "  1. Enroll MOK in Secure Boot (if not done above)"
echo "  2. Verify setup with: /home/daen/Projects/sbh/bin/verify-uki-setup.sh"
echo "  3. Reboot and test driver lock with: pacman -Syu --print"
echo ""
echo "Workflow on kernel/driver update:"
echo "  1. Update: sudo pacman -Syu"
echo "  2. DKMS rebuilds (auto)"
echo "  3. Modules signed (auto)"
echo "  4. UKI regenerated (auto via pacman hook)"
echo "  5. Reboot: sudo systemctl reboot"
echo ""
echo "Verification commands:"
echo "  nvidia-smi                    # Check driver version"
echo "  cat /proc/cmdline             # Check kernel parameters"
echo "  mokutil --list-enrolled       # Check MOK enrollment"
echo "  mokutil --sb-state            # Check Secure Boot status"
