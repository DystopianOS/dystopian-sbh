#!/bin/bash
# Verify UKI + Secure Boot setup for NVIDIA 580
# Run with: /home/daen/Projects/sbh/bin/verify-uki-setup.sh

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  UKI & Secure Boot Setup Verification                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check 1: MOK Keys
echo "Check 1: MOK Keys"
if [ -f /root/MOK.key ] && [ -f /root/MOK.crt ] && [ -f /root/MOK.der ]; then
  echo "  ✓ MOK keys present in /root/"
  ls -lh /root/MOK.* | awk '{print "    " $9 " (" $5 ")"}'
else
  echo "  ✗ MOK keys NOT found"
fi
echo ""

# Check 2: DKMS Post-Install Hook
echo "Check 2: DKMS Automatic Module Signing"
if [ -f /etc/dkms/post-install.sh ]; then
  echo "  ✓ DKMS post-install hook installed"
  if grep -q "nvidia" /etc/dkms/post-install.sh; then
    echo "    Configures NVIDIA module signing"
  fi
else
  echo "  ✗ DKMS post-install hook NOT found"
fi
echo ""

# Check 3: Pacman Hook
echo "Check 3: Pacman Hook for UKI Regeneration"
if [ -f /etc/pacman.d/hooks/99-ukify-cachyos.hook ]; then
  echo "  ✓ Pacman UKI hook installed"
  grep "Target =" /etc/pacman.d/hooks/99-ukify-cachyos.hook | sed 's/^/    /'
else
  echo "  ✗ Pacman UKI hook NOT found"
fi
echo ""

# Check 4: UKI Generation Script
echo "Check 4: UKI Generation Script"
if [ -f /usr/local/bin/generate-uki.sh ]; then
  echo "  ✓ UKI generation script installed"
  if [ -x /usr/local/bin/generate-uki.sh ]; then
    echo "    Script is executable"
  fi
else
  echo "  ✗ UKI generation script NOT found"
fi
echo ""

# Check 5: systemd-boot Entry
echo "Check 5: systemd-boot Boot Entry"
if [ -f /efi/loader/entries/cachyos.conf ]; then
  echo "  ✓ systemd-boot entry configured"
  cat /efi/loader/entries/cachyos.conf | sed 's/^/    /'
else
  echo "  ✗ systemd-boot entry NOT found at /efi/loader/entries/cachyos.conf"
fi
echo ""

# Check 6: NVIDIA Driver Status
echo "Check 6: NVIDIA Driver Status"
if command -v nvidia-smi &> /dev/null; then
  DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)
  echo "  ✓ NVIDIA driver installed: $DRIVER_VER"
  
  if [[ "$DRIVER_VER" == "580"* ]]; then
    echo "    ✓ Driver 580 (correct for Pascal)"
  elif [[ "$DRIVER_VER" == "590"* ]] || [[ "$DRIVER_VER" == "59"* ]]; then
    echo "    ✗ Driver 590+ detected (NOT compatible with Pascal 6.1!)"
  fi
else
  echo "  ✗ NVIDIA driver not installed"
fi
echo ""

# Check 7: CUDA Status
echo "Check 7: CUDA Toolkit Status"
if command -v nvcc &> /dev/null; then
  CUDA_VER=$(nvcc --version | grep "release" | awk '{print $5}')
  echo "  ✓ CUDA installed: $CUDA_VER"
  
  if [[ "$CUDA_VER" == "12"* ]]; then
    echo "    ✓ CUDA 12.x (correct for Pascal)"
  elif [[ "$CUDA_VER" == "13"* ]]; then
    echo "    ✗ CUDA 13.x detected (NOT compatible with Pascal)"
  fi
else
  echo "  ✗ CUDA not installed"
fi
echo ""

# Check 8: Kernel Command Line
echo "Check 8: Kernel Command Line"
if grep -q "nvidia_drm.modeset=1" /proc/cmdline; then
  echo "  ✓ NVIDIA DRM modeset enabled"
else
  echo "  ⚠ NVIDIA DRM modeset not found (optional)"
fi
echo ""

# Check 9: Secure Boot Status
echo "Check 9: Secure Boot & MOK Status"
if command -v mokutil &> /dev/null; then
  SB_STATE=$(mokutil --sb-state 2>/dev/null || echo "unknown")
  echo "  Secure Boot: $SB_STATE"
  
  ENROLLED=$(mokutil --list-enrolled 2>/dev/null | grep -c "CachyOS" || echo "0")
  if [ "$ENROLLED" -gt 0 ]; then
    echo "  ✓ MOK enrolled in Secure Boot"
  else
    echo "  ⚠ MOK not yet enrolled (optional for now)"
  fi
else
  echo "  ✗ mokutil not available"
fi
echo ""

# Check 10: IgnorePkg Configuration
echo "Check 10: Package Lock (IgnorePkg)"
if grep -q "IgnorePkg.*nvidia-580xx" /etc/pacman.conf; then
  echo "  ✓ nvidia-580xx packages locked in pacman.conf"
  grep "IgnorePkg" /etc/pacman.conf | sed 's/^/    /'
else
  echo "  ✗ IgnorePkg NOT configured"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Verification Summary                                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "To complete setup if not done:"
echo "  1. Generate MOK keys and configure DKMS/UKI:"
echo "     sudo /home/daen/Projects/sbh/bin/setup-complete-uki.sh"
echo ""
echo "  2. After reboot, verify everything:"
echo "     /home/daen/Projects/sbh/bin/verify-uki-setup.sh"
echo ""
echo "  3. Test driver lock is working:"
echo "     pacman -Syu --print | grep nvidia"
echo "     (Should show nothing - driver is locked)"
