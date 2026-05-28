# NVIDIA Pascal GTX 1050 Ti + CachyOS: Comprehensive Help Guide

**Version:** 1.0  
**Date:** May 28, 2026  
**System:** GTX 1050 Ti (Compute Capability 6.1) + CachyOS + Driver 580 LTSB  
**Status:** Locked to R580 (Final for Pascal)

---

## 🆘 Quick Help Topics

### Immediate Questions

**Q: Can I upgrade to CachyOS driver 590+?**
- **A:** NO. Driver 590+ completely dropped Pascal (CC 6.1) support. Your system is locked to driver 580.

**Q: When does driver 580 stop working?**
- **A:** 
  - Active support: August 4, 2026 (8 months from now)
  - Security patches: Until August 4, 2028 (2 years from now)
  - Completely EOL: After August 2028

**Q: Is my CUDA working?**
- **A:** Yes. CUDA 12.x is installed and works with driver 580. CUDA 13+ requires Turing GPU (incompatible with Pascal).

**Q: What if I accidentally updated to driver 590+?**
- **A:** See "TROUBLESHOOTING" section → "Accidental Driver Downgrade"

---

## 📚 MAIN DOCUMENTATION

### Primary Guide
**File:** `/home/daen/Projects/sbh/doc/NVIDIA-PASCAL-DRIVER-LOCK.md`

**Contains:**
- Critical status overview
- Driver 580 lock strategy
- CUDA 12.x setup
- Secure Boot integration (3 modes)
- CachyOS UKI best practices
- Complete troubleshooting
- Migration path planning

**How to read:**
1. Start with "Critical: GTX 1050 Ti on Driver 580 LTSB" (status overview)
2. Jump to "Installation: Keep Driver 580 Stable" if setting up now
3. Reference "Secure Boot Integration" for boot hardening
4. Consult "CachyOS UKI Best Practices" for automation setup

### Related Documentation
- `doc/NVIDIA-INTEGRATION.md` — GPU tuning & NVENC/NVDEC
- `doc/NVIDIA-DRIVER-MODES.md` — LKM vs BUILTIN kernel integration
- `config/cachyos-env/*.env` — Kernel build configurations

---

## ⚡ QUICK START: Common Tasks

### Task 1: Verify Driver is Locked

```bash
# Check driver version
nvidia-smi | head -3

# Verify IgnorePkg is set
grep "IgnorePkg.*nvidia-580xx" /etc/pacman.conf

# Check package pinning
pacman -Q | grep nvidia-580xx
```

**Expected Output:**
```
Driver Version: 580.159.03
IgnorePkg = nvidia-580xx-dkms nvidia-580xx-utils ...
nvidia-580xx-dkms 580.159.03-2
```

### Task 2: Safe System Update

```bash
# Check what would be updated (DRY RUN)
sudo pacman -Syu --print 2>&1 | grep -i nvidia
# Should show: (no output = nothing to update)

# Perform update (nvidia packages skipped)
sudo pacman -Syu

# Verify driver unchanged
nvidia-smi | grep "Driver Version"
# Should still show: 580.159.03
```

### Task 3: Check CUDA 12.x

```bash
# Check CUDA installed
pacman -Q cuda

# Verify CUDA version
nvcc --version

# Test CUDA is working
cuda-samples
cd /opt/cuda/samples/1_Utilities/deviceQuery
./deviceQuery
```

**Expected:** Shows GTX 1050 Ti, Compute 6.1, ~768 CUDA cores

### Task 4: Health Check (Weekly)

```bash
#!/bin/bash
echo "=== NVIDIA Pascal Health Check ==="
echo ""
echo "Driver:"
nvidia-smi | head -3
echo ""
echo "CUDA:"
nvcc --version | head -2
echo ""
echo "Pinning:"
grep "IgnorePkg.*nvidia-580xx" /etc/pacman.conf && echo "✓ Locked" || echo "✗ NOT LOCKED"
echo ""
echo "Support Timeline:"
echo "  Now - Aug 4, 2026: Active support (Game Ready, CUDA updates)"
echo "  Aug 4, 2026 - Aug 4, 2028: Security updates only"
echo "  After Aug 4, 2028: Complete EOL (no updates)"
```

### Task 5: Setup Secure Boot (UKI Mode)

```bash
# 1. Install UKI tools
sudo pacman -S mkinitcpio-uki-hook systemd-ukify sbctl

# 2. Generate signing keys
openssl req -new -x509 -newkey rsa:2048 \
  -keyout /root/MOK.key -out /root/MOK.crt \
  -days 3650 -nodes -subj "/CN=CachyOS NVIDIA Pascal"

# 3. Enroll keys
sudo mokutil --import /root/MOK.crt

# 4. Reboot and complete enrollment in UEFI

# 5. Verify
mokutil --list-enrolled | grep "CachyOS"
```

See `NVIDIA-PASCAL-DRIVER-LOCK.md` → "CachyOS UKI Best Practices" for full automation setup.

---

## 🔍 TROUBLESHOOTING

### Problem: nvidia-smi Shows "Failed to communicate"

**Cause:** NVIDIA driver module not loaded

**Solution:**
```bash
# Check module status
lsmod | grep nvidia

# If not loaded, load it
sudo modprobe nvidia nvidia_uvm nvidia_modeset

# If still fails, rebuild DKMS
sudo dkms status | grep nvidia
sudo dkms remove nvidia/580 --all
sudo dkms install nvidia/580 -k $(uname -r)

# Verify
nvidia-smi
```

---

### Problem: System Upgraded to Driver 590+

**Symptom:** 
```
nvidia-smi shows: Driver Version: 590.x or 595.x
Error: "unsupported architecture" or GPU not detected
```

**Solution (Rollback):**
```bash
# 1. Check what happened
pacman -Q | grep nvidia

# 2. Remove 590+ packages
sudo pacman -Rdd nvidia nvidia-utils 2>/dev/null || true

# 3. Reinstall 580 from Garuda
yay -S nvidia-580xx-dkms nvidia-580xx-utils --reinstall

# 4. Rebuild DKMS module
sudo dkms install nvidia/580 -k $(uname -r)

# 5. Verify
nvidia-smi
```

**Prevention:**
Ensure IgnorePkg is in `/etc/pacman.conf`:
```bash
grep "IgnorePkg.*nvidia-580xx" /etc/pacman.conf
```

---

### Problem: CUDA 12.x Not Found

**Symptom:**
```bash
$ nvcc --version
command not found
```

**Solution:**
```bash
# Install CUDA if missing
sudo pacman -S cuda

# Check version
nvcc --version  # Should show 12.x

# Set paths (add to ~/.bashrc or ~/.zshrc)
export PATH=/opt/cuda/bin:$PATH
export LD_LIBRARY_PATH=/opt/cuda/lib64:$LD_LIBRARY_PATH

# Verify
nvcc --version
cuda-samples
./deviceQuery
```

---

### Problem: DKMS Build Fails After Kernel Update

**Symptom:**
```
dkms: ERROR! Could not find the dkms source directory.
```

**Solution:**
```bash
# 1. Install kernel headers
sudo pacman -S linux-cachyos-headers  # For CachyOS BORE
# OR
sudo pacman -S linux-headers  # For Zen

# 2. Verify headers installed
ls /usr/src/linux-* | head -3

# 3. Rebuild DKMS
sudo dkms remove nvidia/580 --all
sudo dkms install nvidia/580 -k $(uname -r)

# 4. Verify
lsmod | grep nvidia
```

---

### Problem: Secure Boot Module Signature Error

**Symptom:**
```
ERROR: NVIDIA kernel module signature verification failed
Secure Boot: Signature verification failed
```

**Solution:**
```bash
# 1. Check if MOK is enrolled
mokutil --list-enrolled

# 2. If not, enroll MOK
sudo mokutil --import /root/MOK.crt
# Reboot and complete enrollment

# 3. Sign modules manually
for module in /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/nvidia*.ko; do
  sudo sbsign --key /root/MOK.key --cert /root/MOK.crt \
    --output "$module" "$module"
done

# 4. Verify
grep "Signature:" /lib/modules/*/kernel/drivers/gpu/drm/nvidia*.ko
```

---

### Problem: Low FPS / Performance Issues

**Symptom:** Gaming/rendering runs slow

**Checks:**
```bash
# 1. Verify GPU is being used
watch -n 1 nvidia-smi

# 2. Check clock speeds (should be high under load)
nvidia-smi -q -d SUPPORTED_CLOCKS

# 3. Check for power throttling
nvidia-smi -l 1 --query-gpu=power.draw

# 4. Check CPU isn't bottleneck
watch -n 1 'top -b -n 1 | head -15'

# 5. Force high performance
sudo nvidia-smi -pm 1                    # Persistent mode
sudo nvidia-smi -pl 75                   # 75W power limit
sudo nvidia-smi -lgc 1500                # Lock GPU clock to 1500 MHz
```

---

## 📊 REFERENCE TABLES

### Supported Configurations

| Component | Version | Status |
|-----------|---------|--------|
| GPU | GTX 1050 Ti | ✓ Working |
| Compute Capability | 6.1 (Pascal) | ✓ Working |
| Driver | 580.159.03 | ✓ Locked |
| CUDA | 12.x | ✓ Working |
| CachyOS Kernel | 7.0.10+ | ✓ Compatible |
| Secure Boot | UKI (optional) | ✓ Supported |
| TPM2 | systemd-cryptsetup | ✓ Supported |

### Timeline

| Date | Event | Action Needed |
|------|-------|---------------|
| Now - Aug 4, 2026 | Active support | Use normally |
| Aug 4, 2026 | Feature support ends | Plan GPU upgrade |
| Aug 4, 2026 - Aug 4, 2028 | Security updates only | No major changes |
| Aug 4, 2028 | Complete EOL | GPU must be replaced |

### Driver Versions

| Version | Pascal Support | CUDA | Status |
|---------|----------------|------|--------|
| 555 | ✓ | 12.x | Older LTS |
| 580 | ✓ | 12.x | **CURRENT (Locked)** |
| 590 | ✗ | 12.x | NOT compatible |
| 595 | ✗ | 12.x | NOT compatible |

### Secure Boot Modes

| Mode | Signing | TPM2 | Use Case |
|------|---------|------|----------|
| 1: Disabled | None | No | Development |
| 2: UKI | Kernel + modules | No | Standard hardening |
| 3: TPM2 | Kernel + modules | Yes | Production security |

---

## 🎯 USE CASES

### Use Case 1: Development Workstation (No Secure Boot)

**Setup:**
1. Keep driver 580 locked (already done)
2. Install CUDA 12.x (already done)
3. Use for Python/TensorFlow/PyTorch development

**Commands:**
```bash
# Compile Python with GPU
python -c "import torch; print(torch.cuda.is_available())"

# Run CUDA sample
/opt/cuda/samples/1_Utilities/deviceQuery

# Use nvcc for custom CUDA
nvcc -arch=sm_61 mykernel.cu -o mykernel
```

---

### Use Case 2: Gaming (With Secure Boot + UKI)

**Setup:**
1. Driver 580 locked
2. UKI Secure Boot enabled
3. Kernel modules auto-signed

**Performance Tips:**
```bash
# Enable persistent mode
sudo nvidia-smi -pm 1

# Lock clocks for stable FPS
sudo nvidia-smi -lgc 1500  # 1500 MHz

# Monitor performance
watch -n 0.5 nvidia-smi --query-gpu=utilization.gpu,temperature,power.draw --format=csv,nounits,noheader
```

---

### Use Case 3: Video Encoding (NVENC)

**Setup:**
1. Driver 580 has NVENC support (H.264, HEVC 8-bit)
2. Install FFmpeg with NVIDIA support

**Usage:**
```bash
# Screen recording to Twitch
ffmpeg -f x11grab -i :0 \
  -c:v hevc_nvenc -preset default \
  -b:v 5000k -rc vbr \
  -c:a aac -b:a 128k \
  -f flv rtmp://live.twitch.tv/app/$KEY

# Transcode 4K H.265 to 1080p H.264
ffmpeg -hwaccel cuda -i input.4k.h265 \
  -c:v h264_nvenc -preset default \
  -b:v 4000k output.1080p.mp4
```

---

### Use Case 4: Production System (TPM2 + LUKS)

**Setup:**
1. Driver 580 locked
2. UKI + Secure Boot enabled
3. TPM2 + LUKS auto-unlock

**Operations:**
```bash
# Boot automatically unlocks LUKS
# No password prompt needed (TPM verifies)

# Monitor TPM sealing
sudo tpm2_pcrread sha256:7,11

# Check LUKS status
sudo cryptsetup luksDump /dev/nvmeXnYpZ
```

---

## ❓ FAQ

### Q: Will my system break on August 2026?
**A:** No. Driver 580 will continue working. NVIDIA will stop releasing new features, but the driver remains functional. Plan your GPU upgrade for late 2027 or early 2028.

### Q: Can I use CUDA 13?
**A:** No. CUDA 13+ requires Turing architecture (CC 7.5+). Your Pascal (CC 6.1) is stuck at CUDA 12.x.

### Q: Is driver 580 secure?
**A:** Yes. NVIDIA provides security patches until August 2028. After that, no more updates.

### Q: Can I run newer games?
**A:** Yes, as long as they support CUDA 12.x and don't require Tensor cores or Ray tracing (both Turing+).

### Q: What GPUs can I upgrade to?
**A:** Any newer GPU (RTX 2080+, RTX 3060+, RTX 4070+, etc.). See "Migration Path" section in main documentation.

### Q: Will my LUKS encryption break?
**A:** No. LUKS is GPU-independent. Encryption works with any driver.

### Q: Can I dual-boot with Windows?
**A:** Yes. This guide covers Linux. Windows uses separate drivers (580.xx for Windows too, with same EOL).

### Q: Can I overclock the GPU?
**A:** Yes. Use nvidia-settings or command-line tools. See "Performance Tuning" in main documentation.

### Q: Is TPM2 required?
**A:** No. It's optional. Choose Secure Boot Mode 2 (UKI only) if TPM2 not available.

### Q: Can I use nouveau (open-source) driver?
**A:** Theoretically yes, but not recommended. Pascal support in nouveau is limited. Stick with proprietary driver 580.

---

## 🚀 NEXT STEPS

### Immediate (This Week)
1. ✓ Verify driver is locked to 580
2. ✓ Check CUDA 12.x working
3. ✓ Run health check script

### Short Term (This Month)
- [ ] If using Secure Boot: Enable UKI + module signing
- [ ] Setup automated health monitoring
- [ ] Test kernel updates with locked driver

### Medium Term (Before August 2026)
- [ ] Plan GPU upgrade (timeline: late 2027/early 2028)
- [ ] Research compatible GPUs
- [ ] Budget for replacement

### Long Term (August 2028)
- [ ] GPU must be replaced by this date
- [ ] Select Turing or newer architecture
- [ ] Plan upgrade procedure

---

## 📞 SUPPORT RESOURCES

### Official Documentation
- NVIDIA: https://docs.nvidia.com/cuda/
- CachyOS: https://wiki.cachyos.org/
- Arch Linux: https://wiki.archlinux.org/title/NVIDIA
- Secure Boot: https://wiki.archlinux.org/title/Unified_kernel_image

### SBH Project Files
- `doc/NVIDIA-PASCAL-DRIVER-LOCK.md` — Main comprehensive guide
- `doc/NVIDIA-INTEGRATION.md` — GPU tuning & features
- `doc/NVIDIA-DRIVER-MODES.md` — Kernel integration comparison
- `config/cachyos-env/*.env` — Kernel build configurations

### Debug Commands

**Verify everything:**
```bash
echo "=== Complete System Status ===" && \
nvidia-smi | head -5 && \
echo "" && \
nvcc --version && \
echo "" && \
grep "IgnorePkg.*nvidia-580xx" /etc/pacman.conf && \
echo "✓ All systems go"
```

**Export system info for troubleshooting:**
```bash
nvidia-smi --query=gpu.name,driver_version,vbios_version,compute_cap --format=csv
```

---

## 🎓 LEARNING RESOURCES

### For CUDA Development
- NVIDIA CUDA Toolkit documentation
- cuDNN for deep learning
- TensorFlow/PyTorch GPU guides

### For Secure Boot
- systemd-boot documentation
- Arch Wiki: Unified Kernel Image
- systemd UKI specifications

### For CachyOS
- CachyOS Wiki
- PKGBUILD customization
- Kernel optimization guides

---

## 📝 NOTES & CAVEATS

⚠️ **Critical Constraints:**
- Driver 580 = FINAL for Pascal (hard technical limit)
- CUDA 12.x = last version for Pascal
- No workarounds exist (hardware limitation)

✅ **Stable Expectations:**
- Driver 580 stable until August 2028
- Can continue using after support ends (but no updates)
- Security patches available until August 2028

⏰ **Timeline Reminders:**
- August 4, 2026 (8 months away) = Feature support ends
- August 4, 2028 (2 years away) = Complete EOL
- Plan GPU upgrade in late 2027 or early 2028

---

## 📋 CHECKLIST

Use this to verify your system is properly configured:

```
System Status Checklist:
  ☐ nvidia-smi shows driver 580.159.03
  ☐ nvidia-smi shows GTX 1050 Ti
  ☐ nvidia-smi shows Compute Capability 6.1
  ☐ nvcc --version shows CUDA 12.x
  ☐ IgnorePkg in /etc/pacman.conf includes nvidia-580xx packages
  ☐ pacman -Syu does NOT update nvidia packages
  ☐ DKMS modules build successfully
  ☐ /opt/cuda exists and contains samples
  ☐ ./deviceQuery runs and shows GPU
  ☐ Health check script works

Security/Boot Checklist (If using Secure Boot):
  ☐ Secure Boot enabled in firmware
  ☐ MOK key generated (/root/MOK.key, /root/MOK.crt)
  ☐ MOK enrolled in firmware
  ☐ UKI kernel image present (/efi/EFI/Linux/*.efi)
  ☐ NVIDIA modules signed (check with modinfo nvidia)
  ☐ systemd-boot entry configured
  ☐ sbverify shows "Signature verification OK"
  ☐ TPM2 present (if using Mode 3)
  ☐ LUKS auto-unlock works (if using Mode 3)

Maintenance Checklist:
  ☐ Weekly health check scheduled
  ☐ System updates tested (without driver upgrade)
  ☐ CUDA samples compile and run
  ☐ Performance monitoring in place
  ☐ Backup strategy established
  ☐ GPU upgrade plan started (for 2027-2028)
```

---

**Last Updated:** May 28, 2026  
**Driver Status:** 580.159.03 (FINAL for Pascal)  
**Next Review:** August 2026 (feature support ends)  
**EOL Reminder:** August 2028 (all support ends)

---

**Questions?** Refer to the comprehensive guide: `/home/daen/Projects/sbh/doc/NVIDIA-PASCAL-DRIVER-LOCK.md`
