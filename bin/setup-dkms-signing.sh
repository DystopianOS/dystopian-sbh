#!/bin/bash
# Configure automatic DKMS module signing for NVIDIA 580
# Run with: sudo /home/daen/Projects/sbh/bin/setup-dkms-signing.sh

set -e

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must run as root (sudo)"
  exit 1
fi

echo "=== Setting up automatic DKMS module signing ==="

# Check if MOK keys exist
if [ ! -f /root/MOK.key ] || [ ! -f /root/MOK.crt ]; then
  echo "ERROR: MOK keys not found in /root/"
  echo "Run: sudo /home/daen/Projects/sbh/bin/setup-mok-keys.sh"
  exit 1
fi

# Create DKMS post-install signing script
echo "Creating DKMS post-install hook..."
mkdir -p /etc/dkms

cat > /etc/dkms/post-install.sh << 'DKMS_SCRIPT'
#!/bin/bash
# Automatic NVIDIA module signing for Secure Boot

KERNEL_VERSION=$1
MOK_KEY="/root/MOK.key"
MOK_CRT="/root/MOK.crt"

if [ ! -f "$MOK_KEY" ] || [ ! -f "$MOK_CRT" ]; then
  echo "WARNING: MOK keys not found, skipping module signing"
  exit 0
fi

SIGN_SCRIPT="/usr/src/linux-headers-${KERNEL_VERSION}/scripts/sign-file"

if [ ! -f "$SIGN_SCRIPT" ]; then
  echo "WARNING: sign-file script not found for kernel $KERNEL_VERSION"
  exit 0
fi

echo "Signing NVIDIA modules for kernel $KERNEL_VERSION..."

# Sign all NVIDIA kernel modules
for module in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  MODULE_PATH="/lib/modules/${KERNEL_VERSION}/kernel/drivers/gpu/drm/${module}.ko"
  
  if [ -f "$MODULE_PATH" ]; then
    echo "  Signing: $MODULE_PATH"
    "$SIGN_SCRIPT" sha256 "$MOK_KEY" "$MOK_CRT" "$MODULE_PATH"
  fi
done

echo "✓ NVIDIA modules signed for $KERNEL_VERSION"
DKMS_SCRIPT

chmod +x /etc/dkms/post-install.sh

echo "✓ DKMS post-install hook installed: /etc/dkms/post-install.sh"

# Verify it's executable
ls -lh /etc/dkms/post-install.sh

echo ""
echo "This hook will run automatically on DKMS module builds"
echo "✓ Setup complete"
