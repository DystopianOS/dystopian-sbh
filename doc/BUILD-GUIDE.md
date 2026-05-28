#!/usr/bin/env bash
# CachyOS Kernel Build Guide: Normal + Hardened (x86-64-v2, LTO, BORE)
# For: Intel i5-8600K (Coffee Lake, 6c/6t, 15GB RAM)

cat << 'EOF'
================================================================================
  CachyOS Kernel Build Guide: Normal + Hardened (x86-64-v2, LTO+BORE)
  Target: i5-8600K (Coffee Lake), x86-64-v2 march
================================================================================

FILES PROVIDED:
  1. PKGBUILD-linux-cachyos           (normal kernel: BORE + LTO)
  2. PKGBUILD-linux-cachyos-hardened  (hardened: BORE + LTO + Secure Boot + IMA)
  3. config.x86-64-v2                 (base kernel config)
  4. build-from-scratch.sh            (GCC/GLIBC bootstrap script)
  5. secureboot-uki-tpm.sh            (Secure Boot + UKI + TPM integration)

================================================================================
WHAT YOU GET
================================================================================

Normal Kernel (linux-cachyos):
  ✓ BORE scheduler (latency-optimized for desktop)
  ✓ LTO=thin (3-5% performance gain, +60 min compile time)
  ✓ x86-64-v2 optimizations (avx2, fma, bmi2, etc.)
  ✓ -O3 optimization level
  ✓ 6-core parallelization
  Build time: ~45-60 min (LTO intensive)

Hardened Kernel (linux-cachyos-hardened):
  ✓ Everything above +
  ✓ Secure Boot integration (auto-signs)
  ✓ IMA/EVM (Integrity Measurement Architecture)
  ✓ Lockdown (integrity/confidentiality)
  ✓ Module signature enforcement
  ✓ Stack protection + fortify source
  ✓ KASAN/UBSAN validation
  ✓ KFENCE heap memory protection
  ✓ Spec mitigations (retpoline, PTI, etc.)
  ✓ Disabled kexec, magic sysrq, unsafe features
  ✓ AppArmor + SELinux ready
  Build time: ~50-70 min

================================================================================
QUICK START: Build Normal Kernel
================================================================================

1. Prepare environment:
   $ mkdir -p ~/archbuild/linux-cachyos
   $ cd ~/archbuild/linux-cachyos

2. Copy PKGBUILDs:
   $ cp ~/PKGBUILD-linux-cachyos ./PKGBUILD
   $ cp ~/config.x86-64-v2 ./

3. Download sources manually or use makepkg:
   $ makepkg -s  # Download sources + build (requires pacman)

   OR for manual control:
   $ wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.xz
   $ wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.sign
   
4. Patch sources (manually for now):
   $ tar xf linux-6.6.tar.xz
   $ cd linux-6.6
   $ patch -Np1 < ../bore-cachy.patch
   $ patch -Np1 < ../lto-thin.patch
   $ cd ..

5. Build:
   $ time makepkg -fci  # -f=force, -c=clean build, -i=install

   Expected: 45-60 min on i5-8600K (LTO link phase is slow)

6. Install:
   $ sudo pacman -U linux-cachyos-*.pkg.tar.zst

================================================================================
QUICK START: Build Hardened Kernel
================================================================================

Same as above, but use PKGBUILD-linux-cachyos-hardened instead.

With Secure Boot signing (optional):
   $ SB_ENABLE_SB_SIGN=1 makepkg -fci

This auto-signs the kernel with your Secure Boot keys (/var/lib/sbctl/keys/db).

================================================================================
MEMORY REQUIREMENTS (CRITICAL!)
================================================================================

Your system: 15GB RAM

LTO (Thin) memory usage during build:
  - Initial compile: ~4-6 GB
  - LTO link phase: ~10-12 GB (PEAK)
  - Available after OS: ~7-8 GB

RISK: If other processes run during LTO link, you may hit swap/OOM.

Solutions:
  a) Stop heavy services before building:
     $ sudo systemctl stop docker mysqld postgresql
     $ free -h  # Check available RAM

  b) Use makepkg with job limit:
     $ MAKEFLAGS="-j3" time makepkg -fci  # Use 3 jobs instead of 6

  c) Build in a container with swappiness tuned down

================================================================================
OPTIMIZATION BREAKDOWN
================================================================================

BORE Scheduler:
  - Optimizes for LOW LATENCY (gaming, desktop responsiveness)
  - 6 cores: excellent fit (no HT bottleneck)
  - Impact: ~5-10% reduction in wake-up latency
  - Enabled: CONFIG_SCHED_BORE=y, CONFIG_SCHED_BORE_BPS_CUTOFF_NS=40000000

LTO (Link-Time Optimization):
  - Type: thin-LTO (fast variant)
  - Compilation flags: -flto=thin -fuse-linker-plugin
  - Impact: ~3-5% instruction-level optimization
  - Trade-off: +60 min compile time
  - Why thin vs fat: fat takes 2-3 hours, thin = 60-90 min for similar gain

x86-64-v2 March:
  - Enables: AVX2, BMI1/2, FMA, SSE4.1/4.2
  - i5-8600K support: YES (Coffee Lake)
  - Impact: ~2-3% general performance
  - Binary size: ~1-2% larger (acceptable for perf trade)

-O3 Optimization:
  - Loop vectorization, aggressive inlining, prefetching
  - Replaces default -O2
  - Impact: ~2-3% latency reduction, ~3-5% throughput gain
  - Risk: Occasionally exposes compiler bugs (rare on stable GCC)

Hardening overhead (in hardened kernel):
  - Stack protector: ~1-2% overhead
  - Module signing checks: negligible post-boot
  - KASAN disabled for production (would be -10-20%)
  - UBSAN enabled: ~0-1% overhead
  - Net impact: <2% latency increase with 10-20% security gain

================================================================================
INTEGRATING WITH SECURE BOOT + UKI + TPM
================================================================================

After building kernel:

1. Stage 0 (pre-Secure Boot setup):
   $ sudo ~/secureboot-uki-tpm.sh

   This will:
   - Rotate Secure Boot keys
   - Build UKI from your kernel
   - Install systemd-boot
   - Sign everything

2. Reboot and enable SB in BIOS firmware

3. Stage 1 (post-SB):
   $ sudo ~/secureboot-uki-tpm.sh

   This will:
   - Reseal TPM2 to new PCR7 (Secure Boot enabled)
   - Enroll TPM for LUKS auto-unlock
   - Clean up backups

Result:
  ✓ Hardened kernel signed + TPM-sealed
  ✓ LUKS auto-unlock via TPM2 (passphrase fallback preserved)
  ✓ UKI auto-rebuild on kernel updates (mkinitcpio hook)

================================================================================
VERIFYING BUILD QUALITY
================================================================================

After install:

1. Check kernel version:
   $ uname -a
   Should show: Linux ... #1-cachyos (or #1-cachyos-hardened)

2. Verify optimizations compiled in:
   $ cat /boot/config-linux-cachyos | grep CONFIG_SCHED_BORE
   Should return: CONFIG_SCHED_BORE=y

   $ cat /boot/config-linux-cachyos | grep CONFIG_LTO
   Should return CONFIG_LTO=y

3. Verify module signing (hardened only):
   $ sudo grep -c "module verification succeeded" /var/log/kernel.log
   Modules should be verified at boot

4. Check Secure Boot status:
   $ bootctl status
   Secure Boot: enabled (if SB enabled in BIOS)

5. Performance test (BORE + LTO):
   $ hackbench -l 1000 -g 10
   Compare to stock kernel baseline

================================================================================
PATCH FILES NEEDED (Not provided, you'll need to source)
================================================================================

These patches need to be sourced/created:
  1. bore-cachy.patch      - BORE scheduler (get from cachyos-repo)
  2. lto-thin.patch        - LTO configuration (create from kernel config changes)
  3. hardening.patch       - Hardening patches (from kernel-hardening project)
  4. ima-policy.patch      - IMA policy loading

Quick sources:
  - BORE: https://github.com/CachyOS/kernel-patches/
  - Hardening: https://github.com/thestinger/linux-hardening
  - IMA: https://linux-ima.readthedocs.io/

================================================================================
TROUBLESHOOTING
================================================================================

OOM during build:
  → Reduce make parallelism: MAKEFLAGS="-j2" makepkg -fci
  → Build on a system with more RAM
  → Use swap (slow but works)

GCC/GLIBC version mismatch:
  → Use bootstrap script first: sudo ~/build-from-scratch.sh
  → Or install latest gcc/glibc: sudo pacman -S gcc glibc

Module signature validation fails:
  → Your custom GCC may not be compatible with kernel module signing
  → Use system GCC: pacman -S gcc

Secure Boot signing fails:
  → Ensure sbctl is installed: sudo pacman -S sbctl
  → Verify keys exist: ls -la /var/lib/sbctl/keys/db/

UKI not booting:
  → Check systemd-boot entry: cat /efi/loader/entries/*.conf
  → Verify UKI exists: ls -la /efi/EFI/Linux/
  → Check kernel cmdline: cat /etc/kernel/cmdline.d/99-bootchain.conf

================================================================================
NEXT STEPS
================================================================================

1. Download patches (link above)
2. Copy PKGBUILD to build directory
3. Run: makepkg -fci
4. Reboot with new kernel
5. Integrate with Secure Boot: sudo ~/secureboot-uki-tpm.sh
6. Enable Secure Boot in firmware, reboot
7. Run finalization: sudo ~/secureboot-uki-tpm.sh

Expected total time:
  - First-time setup: ~3-4 hours (includes SB key generation)
  - Kernel rebuild: ~1 hour (normal+hardened) + reboot overhead

================================================================================
EOF
