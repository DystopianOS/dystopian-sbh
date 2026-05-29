# NVIDIA Pascal GPU: Driver 580 Hard Lock

## Critical: GTX 1050 Ti on Driver 580 LTSB

**Status:** Driver 580 = FINAL release for Pascal (6.1) architecture  
**GPU:** GeForce GTX 1050 Ti (Compute Capability 6.1)  
**Last CUDA:** CUDA 12.x  
**Active Support:** Until August 4, 2026  
**Security Updates:** Until August 4, 2028  

---

## ⚠️ The Hard Cutoff

```
Driver 580.159.03    ✓ Full Pascal support, CUDA 12.x works
Driver 590+          ✗ Pascal architecture completely dropped
                     ✗ CUDA stops working on GTX 1050 Ti
                     ✗ No fallback possible
```

**DO NOT upgrade past driver 580 on this hardware.**

---

## Why This Happened

NVIDIA officially ended Pascal support after R580 (released mid-2026):

1. **Architecture Age** — Pascal (2016) received 8+ years of support
2. **Product Focus** — Resources redirected to Turing (7.5+), Ampere, Ada
3. **Hardware Limits** — Pascal cannot support new driver features
4. **CUDA Cutoff** — CUDA 13.0+ requires Turing (7.5+) minimum

### Timeline
```
August 2026     → R580 reaches end of active support
                  (last Game Ready, CUDA 12.x updates)

August 2026–2028 → R580 LTSB receives security patches only
                   (no new features, optimizations)

August 2028     → Complete EOL
                  (no more updates, including security)
```

---

## Current Setup: Garuda + CachyOS Mixed Repos

### Your Repository Configuration

```
/etc/pacman.conf Priority:
1. cachyos-v3        ← CachyOS (serves 590+, no 580)
2. garuda            ← Garuda (maintains 580xx packages)
3. chaotic-aur       ← Chaotic-AUR (backup, 580xx available)
4. core/extra        ← Arch official
```

### The Problem

```
CachyOS repos:              590, 595 drivers (Pascal NOT supported)
Garuda/Chaotic-AUR repos:   580.159.03 (Pascal supported) ✓
```

If you accidentally upgrade to CachyOS driver (590+):
- CUDA stops working immediately
- GPU compute fails
- Must rollback to 580 or lose CUDA entirely

**Solution:** Pin driver to 580, prevent accidental upgrades.

---

## Installation: Keep Driver 580 Stable

### Step 1: Verify Current Driver

```bash
nvidia-smi
# Should show: Driver Version: 580.159.03

# Verify compute capability
nvidia-smi --query-gpu=name,compute_cap --format=csv
# Should show: GeForce GTX 1050 Ti, 6.1
```

### Step 2: Pin NVIDIA Packages (Prevent Auto-Upgrade)

Add to `/etc/pacman.conf` under `[options]`:

```bash
# Prevent automatic driver upgrade past 580
IgnorePkg = nvidia-580xx-dkms nvidia-580xx-utils \
            lib32-nvidia-580xx-utils opencl-nvidia-580xx \
            nvidia-settings
```

**Verification:**

```bash
sudo pacman -Syu --print  # Shows what WOULD be upgraded (but won't touch nvidia-580xx)
```

### Step 3: Block CachyOS 590+ Drivers Explicitly

```bash
# Check current packages
pacman -Q | grep nvidia-580xx

# Optionally remove conflicting 590+ if present
sudo pacman -Rdd nvidia nvidia-utils 2>/dev/null || true

# Reinstall 580 from Garuda (if needed)
yay -S nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils
```

### Step 4: Kernel Integration with CachyOS

Your CachyOS kernel build supports any driver via DKMS:

```bash
# Load optimized CachyOS environment (works with 580)
source ~/Projects/sbh/config/cachyos-env/optimized-customized-nvidia-lkm.env

# Or hardened variant
source ~/Projects/sbh/config/cachyos-env/optimized-customized-hardened-nvidia-lkm.env

# Driver 580 will auto-build modules for new kernels via DKMS
```

### Step 5: Automatic SONAME Repair Hook

The package also ships a generic post-transaction hook that repairs stale SONAME
links for kernel build tools when binutils or kernel headers are upgraded.
This keeps `objtool` working if a compatible library version is present but the
old SONAME was dropped.

```bash
sudo /usr/lib/dystopian-sbh/repair-kernel-toolchain-sonames.sh
```

---

## CUDA 12.x Ecosystem Setup

### Installation

```bash
# CUDA Toolkit 12.x (last version for Pascal)
sudo pacman -S cuda

# NVIDIA OpenCL runtime
sudo pacman -S opencl-nvidia-580xx

# Verify CUDA
nvcc --version
cuda-samples
cd /opt/cuda/samples/1_Utilities/deviceQuery
./deviceQuery  # Should show GTX 1050 Ti, Compute 6.1
```

### CUDA Development

**Compatible versions:**
```
✓ CUDA Toolkit 12.0, 12.1, 12.2, 12.3, 12.4, 12.5 (latest for Pascal)
✗ CUDA 13.0+ (Turing 7.5+ only, no Pascal support)
```

**Framework Support (CUDA 12.x):**
```
✓ TensorFlow 2.13-2.15 (GPU)
✓ PyTorch 2.0-2.2 (GPU)
✓ cuDNN 9.x (compatible)
✓ cuBLAS, cuFFT, cuSPARSE
✗ Anything requiring CUDA 13+
```

### Compile Example

```bash
# Simple CUDA program
cat > test.cu << 'EOF'
#include <stdio.h>
__global__ void kernel() {
    printf("Hello from GPU!\n");
}
int main() {
    kernel<<<1,1>>>();
    cudaDeviceSynchronize();
    return 0;
}
EOF

# Compile (specifies Pascal, 6.1)
nvcc -arch=sm_61 test.cu -o test
./test
```

---

## Secure Boot Integration with Driver 580

### Mode 1: Secure Boot DISABLED (Standard Setup)

**Configuration:** No signing required, direct kernel boot

```bash
# Check Secure Boot status
mokutil --sb-state
# Output: SecureBoot disabled in firmware

# NVIDIA driver setup (no module signing needed)
sudo dkms install nvidia/580 -k 7.0.10-zen1-1-zen

# Verify driver loaded
lsmod | grep nvidia

# No further Secure Boot integration required
```

**When to use:**
- ✓ Development systems
- ✓ Personal workstations (no security critical data)
- ✓ Testing/experimentation

---

### Mode 2: Secure Boot + UKI (With Signing)

**Configuration:** Signed UKI + signed NVIDIA kernel modules

```bash
# After building CachyOS kernel, integrate with Secure Boot + UKI
sudo sbh-secureboot

# Stage 0: Creates Secure Boot keys and UKI
# Stage 1: Post-reboot TPM sealing (if TPM2 present)

# Verify kernel is signed
sbverify /boot/vmlinuz-*
# Output: Signature verification OK

# Verify NVIDIA module is signed
grep "Signature:" /lib/modules/*/kernel/drivers/gpu/drm/nvidia*.ko | head -3

# Should show signatures present (one per module)
```

**NVIDIA DKMS with UKI:**
```bash
# DKMS automatically signs modules for UKI
sudo dkms install nvidia/580 -k 7.0.10-zen1-1-zen

# Modules are signed with Secure Boot DB keys
# Verified at boot time before loading
```

**When to use:**
- ✓ Secure Boot enabled in firmware
- ✓ Standard security (kernel + modules verified)
- ✓ Most recommended for CachyOS systems

---

### Mode 3: Secure Boot + TPM2 + LUKS (Maximum Hardening)

**Configuration:** UKI + TPM2-sealed LUKS + module signing

```bash
# Full setup: Secure Boot + UKI + TPM2 + LUKS
sudo sbh-secureboot --tpm2 --luks

# Stage 0: Creates Secure Boot keys, UKI, TPM policy
# Stage 1: Post-reboot seals LUKS key to TPM

# Verify Secure Boot
sbverify /boot/vmlinuz-*
# Output: Signature verification OK

# Verify TPM2 sealing
sudo tpm2_pcrread sha256:7,11
# PCR7: Secure Boot policy (kernel image)
# PCR11: UKI measurements

# Verify LUKS sealed to TPM
sudo cryptsetup luksDump /dev/nvmeXnYpZ | grep -A 5 "Keyslot"
# Should show TPM2 slot active

# Test auto-unlock (if LUKS root)
sudo systemctl reboot
# Should boot without password prompt
```

**NVIDIA DKMS with TPM2:**
```bash
# Build driver for each kernel variant
for kernel in $(ls /lib/modules); do
  sudo dkms install nvidia/580 -k "$kernel"
done

# Modules signed and measured into TPM
# LUKS sealed to PCRs 7,11 (kernel + modules)
```

**When to use:**
- ✓ Maximum security (encrypted disk + verified boot)
- ✓ Production systems
- ✓ Sensitive data/workstations
- ✓ Compliance/hardening requirements

---

### Secure Boot Mode Decision Matrix

| Feature | Mode 1 (Disabled) | Mode 2 (UKI) | Mode 3 (TPM2) |
|---------|-------------------|-------------|----------------|
| Secure Boot firmware | ✗ Disabled | ✓ Enabled | ✓ Enabled |
| UKI (kernel signed) | ✗ | ✓ | ✓ |
| NVIDIA modules signed | ✗ | ✓ | ✓ |
| TPM2 measured boot | ✗ | ✗ | ✓ |
| LUKS sealed to TPM | ✗ | ✗ | ✓ |
| LUKS auto-unlock | ✗ | ✗ | ✓ |
| Setup complexity | Simple | Medium | Advanced |
| Security level | Low | Medium | High |
| Boot time overhead | ~0 | ~0.5s | ~1s (TPM) |

---

### Check Current Secure Boot Mode

```bash
#!/bin/bash
echo "=== Secure Boot Status ==="

# 1. Firmware setting
if mokutil --sb-state 2>/dev/null | grep -q "enabled"; then
  echo "✓ Secure Boot: ENABLED in firmware"
  SB_ENABLED=1
else
  echo "✗ Secure Boot: DISABLED in firmware"
  SB_ENABLED=0
fi

# 2. UKI present
if [ -f /boot/vmlinuz-* ]; then
  if sbverify /boot/vmlinuz-* 2>/dev/null | grep -q "Signature verification OK"; then
    echo "✓ UKI: Signed"
    UKI_SIGNED=1
  else
    echo "✗ UKI: Not signed"
    UKI_SIGNED=0
  fi
fi

# 3. NVIDIA modules signed
if grep -q "Signature:" /lib/modules/*/kernel/drivers/gpu/drm/nvidia*.ko 2>/dev/null; then
  echo "✓ NVIDIA modules: Signed"
  MOD_SIGNED=1
else
  echo "✗ NVIDIA modules: Not signed"
  MOD_SIGNED=0
fi

# 4. TPM2 present
if sudo tpm2_getcap 2>/dev/null | grep -q "TPM2"; then
  echo "✓ TPM2: Present"
  if sudo tpm2_pcrread sha256:11 2>/dev/null | grep -q "0x"; then
    echo "✓ TPM2 PCR11: Measured (UKI measurements)"
    TPM2_SEALED=1
  fi
else
  echo "✗ TPM2: Not present"
  TPM2_SEALED=0
fi

# Summary
echo ""
echo "=== Current Mode ==="
if [ $SB_ENABLED -eq 0 ]; then
  echo "Mode: 1 (Secure Boot DISABLED)"
elif [ $TPM2_SEALED -eq 1 ]; then
  echo "Mode: 3 (Secure Boot + TPM2 + LUKS)"
elif [ $UKI_SIGNED -eq 1 ]; then
  echo "Mode: 2 (Secure Boot + UKI)"
fi
```

---

### TPM2 + LUKS Integration Details

```bash
# Check LUKS encryption
sudo cryptsetup status /dev/mapper/root

# View TPM2 slots
sudo cryptsetup luksDump /dev/nvmeXnYpZ

# Manual TPM2 unlock (if auto-unlock fails)
sudo systemctl start systemd-cryptsetup-ask@
```

---

## System Update Strategy: Staying Safe

### Safe Update Procedure

```bash
# Check what would be updated (DRY RUN)
sudo pacman -Syu --print 2>&1 | grep -i nvidia

# Should show: nothing (nvidia packages pinned)

# Perform update
sudo pacman -Syu

# Verify driver unchanged
nvidia-smi | grep "Driver Version"
# Should still show: 580.159.03
```

### If Accidental Upgrade Happens

```bash
# Detect: nvidia-smi fails or shows 590+
nvidia-smi
# ERROR: NVIDIA driver not compatible OR shows 590.x

# Rollback from cache
sudo pacman -U /var/cache/pacman/pkg/nvidia-580xx-dkms-580.159.03-2-x86_64.pkg.tar.zst

# Or reinstall from AUR
yay -S nvidia-580xx-dkms --reinstall
```

---

## Monitoring: Driver Health Checks

### Weekly Health Check

```bash
# Run this script weekly
#!/bin/bash
echo "=== NVIDIA Driver Health ==="
nvidia-smi | head -3
echo ""
echo "Driver version:"
nvidia-smi -q -d DRIVER_VERSION
echo ""
echo "Compute capability:"
nvidia-smi --query-gpu=compute_cap --format=csv,noheader
echo ""
echo "CUDA support:"
which nvcc && nvcc --version || echo "CUDA not installed"
```

### Set Reminder for EOL (August 2028)

```bash
# Add to crontab (check annually)
# 0 0 1 8 * echo "NVIDIA R580 support ends August 4, 2028 - consider GPU upgrade"
```

---

## Migration Path: Before August 2028

**Timeline:**
```
Now–Aug 2026    → Use R580 with full features
Aug 2026–2028   → Use R580 LTSB (security updates only)
Aug 2028        → EOL (no more support)
```

**GPU Upgrade Options (if needed before 2028):**

| GPU | Architecture | CUDA | Driver | Notes |
|-----|-------------|------|--------|-------|
| **GTX 1050 Ti** | Pascal 6.1 | 12.x | 580 | Current (EOL 2028) |
| **RTX 2080** | Turing 7.5 | 13+ | 590+ | Older gaming GPU |
| **RTX 3060 Ti** | Ampere 8.6 | 13+ | 590+ | Mid-range current |
| **RTX 4070 Ti** | Ada 8.9 | 13+ | 590+ | Modern, high perf |
| **RTX 6000 Ada** | Ada 8.9 | 13+ | 590+ | Professional |

---

## CachyOS UKI Best Practices (Secure Boot + UKI)

### Understanding UKI with NVIDIA 580

**Unified Kernel Image (UKI)** bundles:
- Kernel (`vmlinuz`)
- Initramfs
- Kernel command line
- Optional: Secure Boot signatures

**With NVIDIA DKMS**, the workflow is:
```
Kernel Update → DKMS rebuilds modules → Modules signed → UKI regenerated
```

### Step 1: Install UKI Tools

```bash
sudo pacman -S mkinitcpio-uki-hook systemd-ukify sbctl efitools
```

### Step 2: Create Secure Boot Signing Keys

```bash
# Generate MOK (Machine Owner Key) for module signing
openssl req -new -x509 -newkey rsa:2048 \
  -keyout /root/MOK.key \
  -out /root/MOK.crt \
  -days 3650 -nodes \
  -subj "/CN=CachyOS NVIDIA Pascal"

# Also create DER format for UEFI enrollment
openssl x509 -in /root/MOK.crt -outform DER -out /root/MOK.der

# Secure the private key
sudo chmod 400 /root/MOK.key
sudo chmod 400 /root/MOK.der
```

### Step 3: Configure Automatic DKMS Module Signing

Create `/etc/dkms/post-install.sh`:

```bash
#!/bin/bash
# Automatic NVIDIA module signing for Secure Boot

KERNEL_VERSION=$1
MOK_KEY="/root/MOK.key"
MOK_CRT="/root/MOK.crt"
SIGN_SCRIPT="/usr/src/linux-headers-${KERNEL_VERSION}/scripts/sign-file"

if [ ! -f "$SIGN_SCRIPT" ]; then
  echo "ERROR: sign-file script not found for kernel $KERNEL_VERSION"
  exit 1
fi

echo "Signing NVIDIA modules for kernel $KERNEL_VERSION..."

# Sign all NVIDIA kernel modules
for module in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  MODULE_PATH="/lib/modules/${KERNEL_VERSION}/kernel/drivers/gpu/drm/${module}.ko"
  
  if [ -f "$MODULE_PATH" ]; then
    echo "Signing: $MODULE_PATH"
    sudo "$SIGN_SCRIPT" sha256 "$MOK_KEY" "$MOK_CRT" "$MODULE_PATH"
  fi
done

echo "✓ NVIDIA modules signed for $KERNEL_VERSION"
```

Make it executable:
```bash
sudo chmod +x /etc/dkms/post-install.sh
```

### Step 4: Automate UKI Generation on Kernel Update

Create `/etc/pacman.d/hooks/99-ukify-cachyos.hook`:

```ini
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = linux-cachyos*
Target = nvidia-580xx-dkms

[Action]
Description = Generating Unified Kernel Image...
When = PostTransaction
Exec = /usr/lib/dystopian-sbh/generate-uki.sh
```

Create `/usr/lib/dystopian-sbh/generate-uki.sh`:

```bash
#!/bin/bash
# CachyOS UKI generation script with NVIDIA 580

set -e

KERNEL_VERSION=$(ls -t /usr/lib/modules | head -1)
KERNEL_IMAGE="/boot/vmlinuz-linux-cachyos"
INITRD="/boot/initramfs-linux-cachyos.img"
MICROCODE="/boot/intel-ucode.img"  # Use amd-ucode for AMD
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

# Build UKI with ukify
ukify build \
  --linux "$KERNEL_IMAGE" \
  --initrd "$MICROCODE" \
  --initrd "$INITRD" \
  --cmdline "root=UUID=$(blkid -s UUID -o value /dev/disk/by-path/pci-*-part3) rw quiet nvidia_drm.modeset=1" \
  --output "$OUTPUT"

echo "✓ UKI generated: $OUTPUT"

# Sign UKI if keys present
if [ -f "$MOK_KEY" ] && [ -f "$MOK_CRT" ]; then
  echo "Signing UKI with Secure Boot key..."
  sbsign --key "$MOK_KEY" --cert "$MOK_CRT" \
    --output "$OUTPUT" "$OUTPUT"
  echo "✓ UKI signed"
fi

# Update systemd-boot entry
echo "✓ UKI ready for boot"
```

Make it executable:
```bash
sudo chmod +x /usr/lib/dystopian-sbh/generate-uki.sh
```

### Step 5: Enroll MOK in Secure Boot (First Time Only)

```bash
# Enroll the key
sudo mokutil --import /root/MOK.der

# Follow prompts, reboot
sudo systemctl reboot

# At boot, complete MOK enrollment in UEFI (shim screen)
# Then verify
mokutil --list-enrolled | grep "CachyOS"
```

### Step 6: Configure systemd-boot Entry

Edit `/efi/loader/entries/cachyos.conf`:

```
title   CachyOS UKI + NVIDIA 580
efi     /EFI/Linux/cachyos-linux.efi
```

### Step 7: Workflow on Kernel/Driver Update

**Automatic (via pacman hook):**
```bash
# Update kernel or NVIDIA driver
sudo pacman -Syu

# Hooks execute automatically:
# 1. DKMS rebuilds NVIDIA modules
# 2. Modules are signed (via post-install.sh)
# 3. UKI is regenerated (via 99-ukify-cachyos.hook)
# 4. Boot is ready

sudo systemctl reboot
```

**Manual (if hooks fail):**
```bash
# Rebuild NVIDIA modules
sudo dkms install nvidia/580 -k 7.0.10-zen1-1-zen

# Sign modules
sudo /etc/dkms/post-install.sh 7.0.10-zen1-1-zen

# Regenerate UKI
sudo /usr/lib/dystopian-sbh/generate-uki.sh

# Verify
sbverify /efi/EFI/Linux/cachyos-linux.efi
```

### Step 8: Verify UKI Setup

```bash
#!/bin/bash
echo "=== UKI & Secure Boot Verification ==="

# Check kernel command line
echo "Kernel cmdline:"
cat /proc/cmdline

# Check UKI signature
echo ""
echo "UKI signature status:"
sbverify /efi/EFI/Linux/cachyos-linux.efi || echo "Not signed"

# Check NVIDIA modules signed
echo ""
echo "NVIDIA module signatures:"
for module in /lib/modules/*/kernel/drivers/gpu/drm/nvidia*.ko; do
  if [ -f "$module" ]; then
    if modinfo "$module" | grep -q "sig_key"; then
      echo "✓ $(basename $module): Signed"
    else
      echo "✗ $(basename $module): NOT signed"
    fi
  fi
done

# Check MOK enrolled
echo ""
echo "MOK enrollment status:"
mokutil --list-enrolled | head -5

# Check Secure Boot firmware status
echo ""
echo "Secure Boot firmware:"
mokutil --sb-state
```

### CachyOS UKI Maintenance

**On each kernel update:**
1. DKMS automatically rebuilds
2. Modules automatically signed (post-install.sh)
3. UKI automatically regenerated (pacman hook)
4. Just reboot

**Troubleshooting:**
```bash
# Check DKMS status
sudo dkms status

# Manually rebuild if needed
sudo dkms remove nvidia/580 --all
sudo dkms install nvidia/580

# Regenerate UKI manually
sudo /usr/lib/dystopian-sbh/generate-uki.sh

# Check systemd-boot
bootctl status
```

### Best Practices Summary

| Practice | Why |
|----------|-----|
| Automate DKMS signing | Prevents manual mistakes |
| Use pacman hooks | Ensures UKI stays in sync |
| Sign UKI with Secure Boot keys | Required for Secure Boot |
| Keep MOK key secure | Private key = system compromise risk |
| Monitor DKMS status | Catch build failures early |
| Test UKI boots before relying | Ensure fallback method exists |

---

## Troubleshooting

### Issue: DKMS Module Won't Build with 580

**Symptom:** `sudo dkms install nvidia/580` fails

**Fix:**
```bash
# Ensure kernel headers installed
sudo pacman -S linux-cachyos-headers

# Clean and rebuild
sudo dkms remove nvidia/580 --all
sudo dkms install nvidia/580

# If still fails, check gcc version
gcc --version  # Should be 12+
```

### Issue: CUDA 12 Not Found After Driver Update

**Symptom:** `nvcc --version` fails or shows no CUDA

**Fix:**
```bash
# Verify CUDA installed
pacman -Q | grep cuda

# If missing, reinstall
sudo pacman -S cuda

# Set path
export PATH=/opt/cuda/bin:$PATH
export LD_LIBRARY_PATH=/opt/cuda/lib64:$LD_LIBRARY_PATH

# Verify
nvcc --version
```

### Issue: Driver Downgraded to 590+ Accidentally

**Symptom:** `nvidia-smi` shows 590+ or fails

**Fix:**
```bash
# Check pinning
grep "IgnorePkg" /etc/pacman.conf

# Should include nvidia-580xx packages

# Add if missing:
sudo tee -a /etc/pacman.conf << 'EOF'
# Pin driver 580 for Pascal GPU
IgnorePkg = nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils
EOF

# Reinstall 580
yay -S nvidia-580xx-dkms --reinstall
sudo systemctl reboot
```

---

## Summary: Driver 580 Lock Strategy

| Step | Action | Why |
|------|--------|-----|
| 1 | Pin nvidia-580xx packages | Prevent auto-upgrade to 590+ |
| 2 | Use CUDA 12.x | Last supported version |
| 3 | Build with CachyOS kernel | Works with any driver via DKMS |
| 4 | Sign modules for Secure Boot | Integrate with sbh-secureboot |
| 5 | Monitor annually | Plan GPU upgrade before Aug 2028 |

**Status:** ✓ GTX 1050 Ti locked to R580  
**CUDA:** ✓ Working with CUDA 12.x  
**Timeline:** ✓ Supported until August 2028  
**Next Action:** Plan GPU upgrade in 2027–2028

---

## Files

```
~/Projects/sbh/doc/
├── NVIDIA-INTEGRATION.md         (GTX 1050 Ti setup guide)
├── NVIDIA-DRIVER-MODES.md        (LKM vs BUILTIN comparison)
└── NVIDIA-PASCAL-DRIVER-LOCK.md  (this file - driver 580 lock)

Config:
~/Projects/sbh/config/cachyos-env/
├── optimized-customized-nvidia-lkm.env        (CachyOS + R580)
├── optimized-customized-hardened-nvidia-lkm.env (Hardened + R580)
└── (both support any driver via DKMS)
```

---

## References

- NVIDIA Official: Pascal EOL announcement, R580 LTSB support plan
- CUDA Toolkit matrix: CUDA 12.x final for Pascal, CUDA 13+ Turing only
- Phoronix: "NVIDIA Confirms 580 Linux Driver Is The Last For Maxwell/Pascal/Volta"
- TechPowerUp: "NVIDIA's v580 Driver Branch Ends Support"
- Arch Wiki: pacman.conf `IgnorePkg` configuration

---

**Last Updated:** May 28, 2026  
**Driver Status:** R580.159.03 (FINAL for Pascal)  
**Next Review:** August 2027 (plan GPU upgrade)
