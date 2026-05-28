#!/bin/bash
# Create pacman hook for automatic UKI regeneration on kernel update
# Run with: sudo /home/daen/Projects/sbh/bin/setup-uki-hook.sh

set -e

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must run as root (sudo)"
  exit 1
fi

echo "=== Setting up UKI generation pacman hook ==="

# Create pacman.d/hooks directory
mkdir -p /etc/pacman.d/hooks

# Create the hook that triggers on kernel/driver update
echo "Creating pacman hook for automatic UKI regeneration..."
cat > /etc/pacman.d/hooks/99-ukify-cachyos.hook << 'EOF'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = linux-cachyos*
Target = nvidia-580xx-dkms

[Action]
Description = Generating Unified Kernel Image for NVIDIA 580...
When = PostTransaction
Exec = /usr/local/bin/generate-uki.sh
EOF

echo "✓ Pacman hook created: /etc/pacman.d/hooks/99-ukify-cachyos.hook"

# Create the UKI generation script
echo "Creating UKI generation script..."
mkdir -p /usr/local/bin

cat > /usr/local/bin/generate-uki.sh << 'EOF'
#!/bin/bash
# CachyOS UKI generation script with NVIDIA 580

set -e

KERNEL_VERSION=$(ls -t /usr/lib/modules 2>/dev/null | grep -E "cachyos|zen|bore" | head -1)

if [ -z "$KERNEL_VERSION" ]; then
  echo "ERROR: No CachyOS kernel found in /usr/lib/modules"
  exit 1
fi

KERNEL_IMAGE="/boot/vmlinuz-linux-cachyos"
INITRD="/boot/initramfs-linux-cachyos.img"

# Detect microcode
if [ -f "/boot/intel-ucode.img" ]; then
  MICROCODE="/boot/intel-ucode.img"
elif [ -f "/boot/amd-ucode.img" ]; then
  MICROCODE="/boot/amd-ucode.img"
else
  MICROCODE=""
fi

OUTPUT="/efi/EFI/Linux/cachyos-linux.efi"
MOK_KEY="/root/MOK.key"
MOK_CRT="/root/MOK.crt"

echo "=== Generating UKI for kernel $KERNEL_VERSION ==="

# Ensure files exist
if [ ! -f "$KERNEL_IMAGE" ]; then
  echo "ERROR: Kernel image not found: $KERNEL_IMAGE"
  exit 1
fi

if [ ! -f "$INITRD" ]; then
  echo "ERROR: Initramfs not found: $INITRD"
  exit 1
fi

# Create EFI directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT")"

# Build UKI with ukify
echo "Building UKI..."
CMDLINE="root=PARTUUID=$(blkid -s PARTUUID -o value /dev/disk/by-path/pci-*-part*) rw quiet nvidia_drm.modeset=1 quiet loglevel=3"

if [ -n "$MICROCODE" ]; then
  ukify build \
    --linux "$KERNEL_IMAGE" \
    --initrd "$MICROCODE" \
    --initrd "$INITRD" \
    --cmdline "$CMDLINE" \
    --output "$OUTPUT" || true
else
  ukify build \
    --linux "$KERNEL_IMAGE" \
    --initrd "$INITRD" \
    --cmdline "$CMDLINE" \
    --output "$OUTPUT" || true
fi

echo "✓ UKI generated: $OUTPUT"

# Sign UKI if keys present
if [ -f "$MOK_KEY" ] && [ -f "$MOK_CRT" ]; then
  echo "Signing UKI with Secure Boot key..."
  sbsign --key "$MOK_KEY" --cert "$MOK_CRT" \
    --output "$OUTPUT" "$OUTPUT" || echo "WARNING: Signing failed (Secure Boot may be disabled)"
  echo "✓ UKI signed"
fi

echo "✓ UKI ready for boot"
EOF

chmod +x /usr/local/bin/generate-uki.sh

echo "✓ UKI generation script created: /usr/local/bin/generate-uki.sh"

# Verify
ls -lh /etc/pacman.d/hooks/99-ukify-cachyos.hook
ls -lh /usr/local/bin/generate-uki.sh

echo ""
echo "✓ Setup complete"
echo "This hook will run automatically on kernel or NVIDIA driver updates"
