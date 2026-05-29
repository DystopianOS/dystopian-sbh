# Installation Guide

## Files Summary

All scripts are now in `~/Projects/sbh/bin/`:
- **secureboot-uki-tpm.sh** (11KB) - Two-stage Secure Boot + UKI + TPM2/LUKS orchestration
- **build-from-scratch.sh** (12KB) - Bootstrap GCC/GLIBC/Kernel with LTO + BORE

Config files in `~/Projects/sbh/config/`:
- PKGBUILD-linux-cachyos (normal kernel: BORE + LTO)
- PKGBUILD-linux-cachyos-hardened (hardened kernel: lockdown + IMA + module signing)
- config.x86-64-v2 (kernel config for i5-8600K)

Documentation in `~/Projects/sbh/doc/`:
- BUILD-GUIDE.md (complete walkthrough)

## Installation via Pacman Package

```bash
# Build the package (if not already built)
cd ~/Projects/Dystopian/Dystopian-PKGBUILDS/dystopian-sbh
makepkg -f

# Install the built package
sudo pacman -U dystopian-sbh-1.0.0-1-x86_64.pkg.tar.zst --noconfirm

# Verify installation
which dystopian-sbh
dystopian-sbh --help 2>/dev/null || echo "Script installed, no --help defined"
ls -la /usr/bin/dystopian-sbh*
```

**Installation paths (via pacman):**
- Main orchestrator: `/usr/bin/dystopian-sbh`
- Build helper: `/usr/bin/dystopian-sbh-build`
- Env generator: `/usr/bin/dystopian-sbh-gen-env`
- Hardware detection: `/usr/bin/dystopian-sbh-hw-detect`
- Secure Boot + UKI: `/usr/bin/dystopian-sbh-secureboot-uki`
- Debug stripper: `/usr/bin/dystopian-sbh-strip-debug`
- Config & docs: `/usr/share/dystopian-sbh/` and `/usr/share/doc/dystopian-sbh/`

## Manual Installation (Legacy)

For development or custom installation without pacman:

```bash
# Install executables manually
sudo install -Dm755 ~/Projects/sbh/bin/secureboot-uki-tpm.sh /usr/local/sbin/sbh-secureboot
sudo install -Dm755 ~/Projects/sbh/bin/build-from-scratch.sh /usr/local/sbin/sbh-build

# Create convenience symlinks
sudo ln -sf /usr/local/sbin/sbh-secureboot /usr/local/sbin/sbh-sb
sudo ln -sf /usr/local/sbin/sbh-build /usr/local/sbin/sbh-kernel-build

# Install config directory
sudo mkdir -p /etc/sbh
sudo cp -v ~/Projects/sbh/config/* /etc/sbh/
sudo chmod 644 /etc/sbh/*

# Verify installation
sudo sbh-secureboot --help 2>/dev/null || echo "Script installed, no --help defined"
ls -la /usr/local/sbin/sbh-*
```

## Usage

### Secure Boot + UKI + TPM2 Setup

**Stage 0 (Pre-Secure Boot in firmware):**
```bash
sudo sbh-secureboot
```
This will:
- Rotate Secure Boot keys
- Build Unified Kernel Image (UKI)
- Sign all EFI artifacts
- Install hardening (kernel cmdline, sysctl, audit rules)
- Set up systemd-boot
- Install an `@reboot` cron handoff for automatic Stage 1 finalization
- Reboot into setup mode and **HALT** with instructions to enable SB in BIOS

**Stage 1 (Post-Secure Boot enabled):**
Runs automatically at boot via the `@reboot` cron handoff once Secure Boot is enabled, then:
- Re-seals TPM2 to SB + UKI measurements (PCRs 7+11)
- Updates LUKS auto-unlock
- Cleans up backups
- Verifies boot chain
- Removes the cron handoff after successful completion

You can also start the process explicitly with:

```bash
sudo sbh-secureboot --install
```
This enters setup mode, installs the cron handoff, and reboots when Stage 0 finishes.

### Custom Kernel Build

```bash
sudo sbh-kernel-build
```
Stages:
- **0**: Preflight (disk/RAM checks, localmoddb generation)
- **1**: Build GCC 13.2
- **2**: Build GLIBC 2.38
- **3**: Build Kernel with LTO (thin) + BORE + x86-64-v2

## Environment Variables

### secureboot-uki-tpm.sh

```bash
# Keep Microsoft UEFI certs in SB DB (default: 0)
KEEP_MICROSOFT_KEYS=1 sbh-secureboot

# Disable IMA enforcement (default: enabled)
ENABLE_IMA=0 sbh-secureboot

# Disable audit rules (default: enabled)
ENABLE_AUDIT=0 sbh-secureboot

# Force stage (default: auto-detect)
STAGE=0 sbh-secureboot
STAGE=1 sbh-secureboot

# Custom EFI mount (default: /efi)
EFI_MOUNT=/boot/efi sbh-secureboot
```

### build-from-scratch.sh

```bash
# Skip preflight checks (dangerous!)
SKIP_PREFLIGHT=1 sbh-kernel-build

# Override CPU count for LTO linking (default: 3)
MAKEFLAGS="-j4" sbh-kernel-build

# Skip specific stages
SKIP_GCC=1 sbh-kernel-build
SKIP_GLIBC=1 sbh-kernel-build
SKIP_KERNEL=1 sbh-kernel-build
```

## Hardening Features

### Secure Boot + UKI
- Unified Kernel Image (systemd-ukify) prevents loader replacement
- systemd-boot with no-edit protection
- All EFI binaries signed with Secure Boot DB key
- firmware update blocked (fwupd masked)

### Kernel Hardening
- **Lockdown (confidentiality)**: Prevents KEXEC, direct mem access, EFI var writes
- **Module signing**: Enforced MODULE_SIG_FORCE=y
- **IMA+EVM**: Kernel integrity measurement + attestation
- **Audit rules**: Tracks all Secure Boot, TPM, EFI, cryptsetup operations

### TPM2 + LUKS Auto-Unlock
- PCR 7: Secure Boot state (firmware measurements)
- PCR 11: UKI measurements (kernel + initramfs)
- Fallback: Original LUKS passphrase preserved in slot 1
- TPM2 auto-unlock only after Secure Boot confirmed enabled

### Userspace Hardening
- sysctl: kexec disabled, BPF restricted, ASLR, dmesg restricted
- EFI vars mounted read-only (efi-guard-readonly.service)
- Audit daemon capturing all boot-chain events

## Memory Requirements

**build-from-scratch.sh on i5-8600K + 15GB RAM:**
- Stage 1 (GCC): ~2GB
- Stage 2 (GLIBC): ~1.5GB
- Stage 3 (Kernel LTO): ~12GB peak during link phase
- **Workaround**: Limited to `-j3` (not `-j6`) to stay under 12GB

If OOM during kernel link:
```bash
MAKEFLAGS="-j2" sbh-kernel-build
```

## Troubleshooting

### Secure Boot detection not working
```bash
# Check SB state manually
bootctl status | grep "Secure Boot"
mokutil --sb-state
hexdump -Cv /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null

# Force stage manually
STAGE=1 sbh-secureboot

# Enter setup mode and reboot into the automatic handoff
sudo sbh-secureboot --install
```

### TPM2 resealing issues
```bash
# Check TPM2 status
systemctl status tpm2-abrmd
tpm2_getcap properties-fixed | grep TPM2_PT_FIRMWARE_VERSION

# Check existing TPM2 slots
cryptsetup luksDump /dev/disk/by-uuid/<uuid> | grep -i tpm2
```

### UKI not building
```bash
# Check ukify and sbctl
which ukify sbctl
ukify --help

# Check kernel cmdline file
cat /etc/kernel/cmdline.d/99-bootchain.conf

# Manual UKI build
ukify \
  --kernel=/usr/lib/modules/$(uname -r)/vmlinuz \
  --initrd=/boot/initramfs-linux.img \
  --cmdline="@/etc/kernel/cmdline.d/99-bootchain.conf" \
  --output=/efi/EFI/Linux/cachyos-uki.efi
sbctl sign -s /efi/EFI/Linux/cachyos-uki.efi
```

### Module signing failures
```bash
# Check SB module signing keys
ls -la /var/lib/sbctl/keys/db/

# Manually sign a module
/usr/lib/modules/$(uname -r)/build/scripts/sign-file \
  sha256 \
  /var/lib/sbctl/keys/db/db.key \
  /var/lib/sbctl/keys/db/db.pem \
  /path/to/module.ko
```

## Verification Checklist

After installation and first run:

```bash
# [ ] Secure Boot stage 0 created keys, UKI, audit rules
ls -la /sys/firmware/efi/efivars/PK-* /sys/firmware/efi/efivars/KEK-* /sys/firmware/efi/efivars/db-*

# [ ] Kernel cmdline includes lockdown
cat /proc/cmdline | grep lockdown=confidentiality

# [ ] sysctl hardening applied
sysctl kernel.kexec_load_disabled kernel.unprivileged_bpf_disabled

# [ ] Audit rules installed
sudo auditctl -l | grep -E 'efi_writes|tpm_writes|kexec'

# [ ] EFI guard service enabled
systemctl is-enabled efi-guard-readonly.service

# [ ] mkinitcpio preset configured
cat /etc/mkinitcpio.d/cachyos-uki.preset

# [ ] After Stage 1 + reboot: SB enabled + TPM2 resealed
bootctl status | grep -i "secure boot"
systemd-cryptenroll --list-devices
```

### Shell script smoke check

```bash
# Validate the shell helpers locally
bash bin/verify-shell-scripts.sh
```

The same check runs in GitHub Actions on changes under `bin/**/*.sh`.

## Performance Impact

- **Secure Boot**: negligible (firmware check at boot)
- **UKI loading**: negligible vs. GRUB2
- **Module signing**: negligible (checked at load time)
- **Audit daemon**: ~1-2% CPU (on SSD, minimal disk IO)
- **BORE scheduler**: +5-10% latency improvement for interactive workloads
- **LTO=thin kernel**: 3-5% performance gain (but +60-90 min compile time)

## Documentation

Full build walkthrough in `~/Projects/sbh/doc/BUILD-GUIDE.md`

Key sections:
- Quick Start (immediate setup)
- Hardware Requirements (RAM/CPU for LTO)
- Secure Boot Architecture (technical deep dive)
- UKI + mkinitcpio Integration
- TPM2 + LUKS Auto-Unlock
- Optimization Breakdown (LTO vs. BORE vs. combined)
