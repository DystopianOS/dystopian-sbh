#!/usr/bin/env bash
# Create pacman hook for automatic UKI regeneration on kernel update
# Run with: sudo /home/daen/Projects/sbh/bin/setup-uki-hook.sh

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must run as root (sudo)"
  exit 1
fi

echo "=== Setting up UKI generation pacman hook ==="

GENERATE_UKI_DIR="/usr/lib/dystopian-sbh"
GENERATE_UKI_SCRIPT="${GENERATE_UKI_DIR}/generate-uki.sh"
REPAIR_UKI_SCRIPT="${GENERATE_UKI_DIR}/repair-kernel-toolchain-sonames.sh"
REPAIR_HOOK="/etc/pacman.d/hooks/98-dystopian-kernel-toolchain-sonames.hook"

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
Exec = ${GENERATE_UKI_SCRIPT}
EOF

echo "✓ Pacman hook created: /etc/pacman.d/hooks/99-ukify-cachyos.hook"

if [ ! -f /usr/share/libalpm/hooks/98-dystopian-kernel-toolchain-sonames.hook ]; then
  echo "Creating kernel toolchain SONAME repair hook..."
  cat > "$REPAIR_HOOK" << 'EOF'
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = binutils
Target = linux-*-headers

[Action]
Description = Repair kernel build-tool SONAME compatibility links
When = PostTransaction
Exec = /usr/lib/dystopian-sbh/repair-kernel-toolchain-sonames.sh
EOF
  echo "✓ Repair hook created: $REPAIR_HOOK"
else
  echo "✓ Package-owned SONAME repair hook already installed"
fi

# Create the UKI generation script
echo "Creating UKI generation script..."
mkdir -p "$GENERATE_UKI_DIR"

cat > "$GENERATE_UKI_SCRIPT" << 'EOF'
#!/usr/bin/env bash
# CachyOS UKI generation script with NVIDIA 580

set -euo pipefail

resolve_root_uuid() {
  local root_uuid root_source

  root_uuid="$(findmnt -no UUID / 2>/dev/null || true)"
  if [ -n "${root_uuid:-}" ]; then
    printf '%s\n' "$root_uuid"
    return 0
  fi

  root_source="$(findmnt -no SOURCE / 2>/dev/null || true)"
  [ -n "${root_source:-}" ] || return 1
  root_source="$(readlink -f "$root_source" 2>/dev/null || printf '%s' "$root_source")"
  blkid -s UUID -o value "$root_source" 2>/dev/null || return 1
}

KERNEL_VERSION="$(ls -1 /usr/lib/modules 2>/dev/null | sort -V | tail -1)"

if [ -z "$KERNEL_VERSION" ]; then
  echo "ERROR: No CachyOS kernel found in /usr/lib/modules"
  exit 1
fi

PKGBASE="$(cat "/usr/lib/modules/${KERNEL_VERSION}/pkgbase" 2>/dev/null || echo linux-cachyos)"
KERNEL_IMAGE="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"
INITRD="/boot/initramfs-${PKGBASE}.img"

# Detect microcode
if [ -f "/boot/intel-ucode.img" ]; then
  MICROCODE="/boot/intel-ucode.img"
elif [ -f "/boot/amd-ucode.img" ]; then
  MICROCODE="/boot/amd-ucode.img"
else
  MICROCODE=""
fi

OUTPUT="/efi/EFI/Linux/cachyos-linux.efi"
CMDLINE_FILE="/etc/kernel/cmdline.d/99-bootchain.conf"
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

mkdir -p "$(dirname "$CMDLINE_FILE")"
if [ ! -s "$CMDLINE_FILE" ] || ! grep -q '^root=' "$CMDLINE_FILE"; then
  ROOT_UUID="$(resolve_root_uuid)"
  if [ -z "${ROOT_UUID:-}" ]; then
    echo "ERROR: Unable to determine root UUID"
    exit 1
  fi
  cat > "$CMDLINE_FILE" <<EOF_CMDLINE
root=UUID=${ROOT_UUID} rw quiet nvidia_drm.modeset=1 loglevel=3
EOF_CMDLINE
fi

# Create EFI directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT")"

# Build UKI with ukify
echo "Building UKI..."
if [ -n "$MICROCODE" ]; then
  ukify build \
    --linux "$KERNEL_IMAGE" \
    --initrd "$MICROCODE" \
    --initrd "$INITRD" \
    --cmdline "@$CMDLINE_FILE" \
    --output "$OUTPUT"
else
  ukify build \
    --linux "$KERNEL_IMAGE" \
    --initrd "$INITRD" \
    --cmdline "@$CMDLINE_FILE" \
    --output "$OUTPUT"
fi

echo "✓ UKI generated: $OUTPUT"

# Sign UKI if keys present
if [ -f "$MOK_KEY" ] && [ -f "$MOK_CRT" ]; then
  echo "Signing UKI with Secure Boot key..."
  sbsign --key "$MOK_KEY" --cert "$MOK_CRT" \
    --output "$OUTPUT" "$OUTPUT"
  echo "✓ UKI signed"
fi

echo "✓ UKI ready for boot"
EOF

chmod +x "$GENERATE_UKI_SCRIPT"

echo "✓ UKI generation script created: $GENERATE_UKI_SCRIPT"

echo "Creating kernel toolchain SONAME repair script..."
cat > "$REPAIR_UKI_SCRIPT" << 'EOF'
#!/usr/bin/env bash
# Repair stale SONAME links for kernel build tools after toolchain upgrades.
# This keeps objtool and similar kernel helper binaries usable when a shared
# library SONAME changes but the underlying ABI-compatible library is present.

set -euo pipefail
umask 077

log() {
  printf '[repair-soname] %s\n' "$*"
}

warn() {
  printf '[repair-soname] %s\n' "$*" >&2
}

die() {
  warn "$*"
  exit 1
}

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "Run as root"
  fi
}

discover_kernel_tools() {
  find /usr/lib/modules -path '*/build/tools/*' -type f -perm -111 2>/dev/null | sort -u
}

missing_sonames_for() {
  local binary="$1"
  ldd "$binary" 2>/dev/null \
    | awk '/=> not found$/ {print $1}' \
    | sort -u
}

pick_compat_target() {
  local missing="$1"
  local stem candidates=()

  stem="${missing%.so.*}.so."

  shopt -s nullglob
  candidates=(/usr/lib/"${stem}"*)
  shopt -u nullglob

  if [[ ${#candidates[@]} -eq 0 ]]; then
    return 1
  fi

  mapfile -t candidates < <(printf '%s\n' "${candidates[@]}" | sort -V)
  printf '%s\n' "${candidates[${#candidates[@]}-1]}"
}

repair_missing_soname() {
  local missing="$1"
  local compat="/usr/lib/$missing"
  local target

  if [[ -e "$compat" && ! -L "$compat" ]]; then
    return 0
  fi

  if [[ -L "$compat" ]]; then
    rm -f -- "$compat"
  fi

  target="$(pick_compat_target "$missing")" || return 1
  ln -s -- "$(basename "$target")" "$compat"
  log "Linked $compat -> $(basename "$target")"
}

verify_tools() {
  local binary missing
  local unresolved=0

  while IFS= read -r binary; do
    [[ -n "$binary" ]] || continue
    while IFS= read -r missing; do
      [[ -n "$missing" ]] || continue
      unresolved=1
      if repair_missing_soname "$missing"; then
        continue
      fi
      warn "No compat target found for $missing (reported by $binary)"
    done < <(missing_sonames_for "$binary")
  done < <(discover_kernel_tools)

  if [[ $unresolved -eq 0 ]]; then
    log "No missing kernel tool SONAMEs detected"
  fi
}

main() {
  require_root

  if ! command -v ldd >/dev/null 2>&1; then
    die "ldd not found"
  fi

  verify_tools

  if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
  fi
}

main "$@"
EOF
chmod +x "$REPAIR_UKI_SCRIPT"
echo "✓ Repair script created: $REPAIR_UKI_SCRIPT"

# Verify
ls -lh /etc/pacman.d/hooks/99-ukify-cachyos.hook
ls -lh "$GENERATE_UKI_SCRIPT"
ls -lh "$REPAIR_UKI_SCRIPT"

echo ""
echo "✓ Setup complete"
echo "This hook will run automatically on kernel or NVIDIA driver updates"
