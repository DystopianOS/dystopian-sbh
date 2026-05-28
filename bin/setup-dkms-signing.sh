#!/usr/bin/env bash
# Configure automatic DKMS module signing for NVIDIA 580
# Run with: sudo /home/daen/Projects/sbh/bin/setup-dkms-signing.sh

set -euo pipefail

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
#!/usr/bin/env bash
# Automatic NVIDIA module signing for Secure Boot

set -euo pipefail

KERNEL_VERSION="${1:-}"
if [ -z "$KERNEL_VERSION" ]; then
  echo "ERROR: Missing kernel version"
  exit 1
fi

MOK_KEY="/root/MOK.key"
MOK_CRT="/root/MOK.crt"

if [ ! -f "$MOK_KEY" ] || [ ! -f "$MOK_CRT" ]; then
  echo "ERROR: MOK keys not found"
  exit 1
fi

SIGN_SCRIPT="/lib/modules/${KERNEL_VERSION}/build/scripts/sign-file"
if [ ! -x "$SIGN_SCRIPT" ]; then
  SIGN_SCRIPT="/usr/src/linux-headers-${KERNEL_VERSION}/scripts/sign-file"
fi

if [ ! -x "$SIGN_SCRIPT" ]; then
  echo "ERROR: sign-file script not found for kernel $KERNEL_VERSION"
  exit 1
fi

echo "Signing NVIDIA modules for kernel $KERNEL_VERSION..."

find_module() {
  local module="$1" path

  if command -v modinfo >/dev/null 2>&1; then
    path="$(modinfo -n "$module" 2>/dev/null || true)"
    if [ -n "${path:-}" ] && [ -f "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  fi

  find "/lib/modules/${KERNEL_VERSION}" -type f \
    \( -name "${module}.ko" -o -name "${module}.ko.xz" -o -name "${module}.ko.zst" \) \
    | sort | head -n 1
}

# Sign all NVIDIA kernel modules
for module in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  MODULE_PATH="$(find_module "$module")"

  if [ -n "${MODULE_PATH:-}" ] && [ -f "$MODULE_PATH" ]; then
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
