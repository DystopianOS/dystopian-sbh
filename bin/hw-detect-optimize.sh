#!/usr/bin/env bash
set -euo pipefail
umask 077

# HARDWARE DETECTION + AUTO-OPTIMIZATION FOR i5-8600K + GTX 1050 Ti
# Detects your exact hardware, creates custom sysctl + GPU + CPU tuning
# No sudo required for detection; recommend for runtime tuning

log(){ printf '[*] %s\n' "$*"; }
warn(){ printf '[!] %s\n' "$*"; }
die(){ printf '[✗] %s\n' "$*" >&2; exit 1; }
has(){ command -v "$1" >/dev/null 2>&1; }

# ═══════════════════════════════════════════════════════════════════════════
# HARDWARE DETECTION
# ═══════════════════════════════════════════════════════════════════════════

detect_cpu() {
  log "Detecting CPU..."
  
  local brand model cores threads freq_base freq_max l3_cache
  
  if [ -f /proc/cpuinfo ]; then
    brand=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $NF}')
    model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    cores=$(grep -c "^processor" /proc/cpuinfo)
    threads=$cores
    
    freq_base=$(grep -m1 "cpu MHz" /proc/cpuinfo | awk '{print int($NF)}')
    l3_cache=$(grep -m1 "cache size" /proc/cpuinfo | awk '{print $NF}')
  fi
  
  # Turbo boost detection
  local turbo_enabled=0
  if has cpupower; then
    turbo_enabled=$(cpupower frequency-info -b 2>/dev/null | grep -c "boost state support" || echo 0)
  fi
  
  cat << EOF
╔════════════════════════════════════════════════════════════════╗
║                      CPU INFORMATION                          ║
╠════════════════════════════════════════════════════════════════╣
  Brand:              $brand
  Model:              $model
  Cores/Threads:      $cores/$threads
  Base Frequency:     $freq_base MHz
  L3 Cache:           $l3_cache
  Turbo Boost:        $([ "$turbo_enabled" = "1" ] && echo "Enabled" || echo "Disabled")
╚════════════════════════════════════════════════════════════════╝
EOF

  echo "CPU_BRAND=$brand"
  echo "CPU_MODEL=$model"
  echo "CPU_CORES=$cores"
  echo "CPU_THREADS=$threads"
  echo "CPU_BASE_FREQ=$freq_base"
  echo "CPU_L3=$l3_cache"
}

detect_ram() {
  log "Detecting RAM..."
  
  local total_kb total_gb
  total_kb=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
  total_gb=$((total_kb / 1024 / 1024))
  
  cat << EOF
╔════════════════════════════════════════════════════════════════╗
║                      MEMORY INFORMATION                       ║
╠════════════════════════════════════════════════════════════════╣
  Total RAM:          ${total_gb}GB
  Swap:               $(free -h | grep Swap | awk '{print $2}')
  Recommended THP:    madvise (safe with lockdown)
  Recommended LTO:    thin (j3 during link phase)
╚════════════════════════════════════════════════════════════════╝
EOF

  echo "RAM_GB=$total_gb"
}

detect_gpu() {
  log "Detecting GPU..."
  
  if has nvidia-smi; then
    local gpu_name gpu_memory gpu_clock compute_cap
    
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    gpu_memory=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader | head -1 | awk '{print $1}')
    gpu_clock=$(nvidia-smi --query-gpu=clocks.max.gr --format=csv,noheader | head -1)
    compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1)
    
    local driver_ver
    driver_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    
    cat << EOF
╔════════════════════════════════════════════════════════════════╗
║                      GPU INFORMATION                          ║
╠════════════════════════════════════════════════════════════════╣
  GPU Name:           $gpu_name
  Compute Capability: $compute_cap (Pascal SM 6.1)
  Memory:             $gpu_memory MB
  Max Clock:          $gpu_clock MHz
  Driver Version:     $driver_ver
╚════════════════════════════════════════════════════════════════╝
EOF

    echo "GPU_NAME=$gpu_name"
    echo "GPU_MEMORY=$gpu_memory"
    echo "GPU_CLOCK=$gpu_clock"
    echo "GPU_COMPUTE_CAP=$compute_cap"
    echo "NVIDIA_DRIVER=$driver_ver"
  else
    warn "NVIDIA GPU not detected (nvidia-smi not found)"
    echo "GPU_NAME=none"
  fi
}

detect_storage() {
  log "Detecting storage..."
  
  local root_dev root_scheduler
  root_dev=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
  
  if [ -f "/sys/block/${root_dev##*/}/queue/scheduler" ]; then
    root_scheduler=$(cat "/sys/block/${root_dev##*/}/queue/scheduler" | tr -d '[]')
  fi
  
  cat << EOF
╔════════════════════════════════════════════════════════════════╗
║                  STORAGE INFORMATION                          ║
╠════════════════════════════════════════════════════════════════╣
  Root Device:        $root_dev
  Current Scheduler:  $root_scheduler
  Recommended:        mq-deadline (already good)
╚════════════════════════════════════════════════════════════════╝
EOF

  echo "ROOT_DEVICE=$root_dev"
}

detect_tpm() {
  log "Detecting TPM..."
  
  if [ -c /dev/tpm0 ]; then
    local tpm_version
    if has tpm2_getcap; then
      tpm_version="TPM 2.0"
    else
      tpm_version="Unknown TPM"
    fi
    
    echo "TPM_AVAILABLE=1"
    echo "TPM_VERSION=$tpm_version"
  else
    echo "TPM_AVAILABLE=0"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# AUTO-TUNING RECOMMENDATIONS
# ═══════════════════════════════════════════════════════════════════════════

generate_sysctl_tuning() {
  local ram_gb="$1" cores="$2" output_file="${3:-.}/99-cachyos-localized.conf"
  
  log "Generating localized sysctl tuning for ${ram_gb}GB RAM, ${cores} cores..."
  
  # Calculate values based on hardware
  local swappiness=10
  local vm_dirty_ratio=10
  local dirty_bg_ratio=5
  
  if [ "$ram_gb" -lt 8 ]; then
    swappiness=5
    vm_dirty_ratio=5
    dirty_bg_ratio=2
  fi
  
  cat > "$output_file" << EOF
# Localized CachyOS Performance + Hardening Tuning
# Generated for: ${ram_gb}GB RAM, ${cores} cores
# Date: $(date -u)

# ═══════════════════════════════════════════════════════════════
# CPU FREQUENCY SCALING (aggressive turbo for desktop)
# ═══════════════════════════════════════════════════════════════
kernel.sched_migration_cost_ns=500000
kernel.sched_latency_ns=24000000
kernel.sched_min_granularity_ns=4000000
kernel.sched_wakeup_migration_cost=500

# BORE scheduler tuning (already in kernel, but optimize)
kernel.sched_child_runs_first=0

# ═══════════════════════════════════════════════════════════════
# MEMORY MANAGEMENT (LTO-friendly, swap-aware)
# ═══════════════════════════════════════════════════════════════
vm.swappiness=${swappiness}
vm.page-cluster=3
vm.dirty_ratio=${vm_dirty_ratio}
vm.dirty_background_ratio=${dirty_bg_ratio}
vm.vfs_cache_pressure=50
vm.mmap_min_addr=65536
vm.overcommit_memory=1
vm.max_map_count=2147483647

# ═══════════════════════════════════════════════════════════════
# NETWORKING (low latency for gaming/interactive)
# ═══════════════════════════════════════════════════════════════
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_fin_timeout=20
net.ipv4.tcp_tw_reuse=1
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096

# ═══════════════════════════════════════════════════════════════
# HARDENING (from boot chain, keep locked)
# ═══════════════════════════════════════════════════════════════
kernel.kexec_load_disabled=1
kernel.unprivileged_bpf_disabled=2
kernel.unprivileged_userns_clone=0
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.yama.ptrace_scope=3
kernel.sysrq=0
kernel.perf_event_paranoid=4
kernel.panic=10
kernel.panic_on_oops=1

# ═══════════════════════════════════════════════════════════════
# FILESYSTEM & I/O
# ═══════════════════════════════════════════════════════════════
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_regular=2
fs.protected_fifos=2
fs.suid_dumpable=0

# ═══════════════════════════════════════════════════════════════
# TUNING NOTES
# ═══════════════════════════════════════════════════════════════
# vm.swappiness=${swappiness}    → Avoid unnecessary swap (tight RAM for LTO)
# vm.dirty_ratio=${vm_dirty_ratio}         → Less frequent flushing (safer during link phase)
# kernel.sched_*              → BORE scheduler support
# TCP tuning                  → Lower latency for games/interactive
EOF

  log "✓ Generated: $output_file"
  cat "$output_file"
}

generate_gpu_profile() {
  local gpu_name="$1" output_file="${2:-.}/nvidia-optimization.profile"
  
  log "Generating GPU optimization profile for: $gpu_name"
  
  cat > "$output_file" << 'EOF'
#!/bin/bash
# NVIDIA GPU Optimization Profile for GTX 1050 Ti (Pascal SM 6.1)
# Run with: source nvidia-optimization.profile

# ═══════════════════════════════════════════════════════════════
# PERSISTENT GPU MODE (faster GPU init, 5-15% latency boost)
# ═══════════════════════════════════════════════════════════════
if command -v nvidia-smi &>/dev/null; then
  echo "[nvidia-profile] Enabling persistent GPU mode..."
  sudo nvidia-smi -pm 1 2>/dev/null || echo "Note: Requires sudo"
  
  echo "[nvidia-profile] Enabling persistence daemon..."
  sudo systemctl enable nvidia-persistenced 2>/dev/null || true
  sudo systemctl start nvidia-persistenced 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════
# ENVIRONMENT VARIABLES (VSync off, frame buffering)
# ═══════════════════════════════════════════════════════════════
export __GL_SYNC_TO_VBLANK=0           # Disable VSync (lower latency)
export __GL_YIELD="NOTHING"            # Aggressive CPU yielding
export __GL_MAX_FRAMES_ALLOWED=2       # Frame buffering (prevent stutter)
export __GL_THREADED_OPTIMIZATIONS=1   # Multithreaded driver

# CUDA optimization
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export CUDA_VISIBLE_DEVICES=0

# Proton/DXVK gaming optimization
export DXVK_FRAME_RATE=0               # Unlimited (cap in game settings)
export STAGING_SHARED_MEMORY=true      # Memory optimization

echo "[nvidia-profile] Environment variables loaded (GTX 1050 Ti optimized)"
echo "  __GL_SYNC_TO_VBLANK=$__GL_SYNC_TO_VBLANK"
echo "  __GL_THREADED_OPTIMIZATIONS=$__GL_THREADED_OPTIMIZATIONS"
echo "  CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
EOF

  chmod +x "$output_file"
  log "✓ Generated: $output_file"
  cat "$output_file"
}

generate_kernel_config() {
  local output_file="${1:-.}/config.x86-64-v2-localized"
  
  log "Generating localized kernel config for i5-8600K..."
  
  # Copy base config and add localizations
  cat > "$output_file" << 'EOF'
# Localized kernel config for i5-8600K + GTX 1050 Ti
# Date: $(date -u)

# CPU FEATURE SET (x86-64-v2 = AVX2, BMI2, FMA; no AVX-512)
CONFIG_X86_64=y
CONFIG_X86_64_V2=y

# LTO CONFIGURATION (thin for 15GB RAM)
CONFIG_LTO_CLANG_THIN=y
CONFIG_LTO_CLANG=y

# BORE SCHEDULER
CONFIG_SCHED_BORE=y

# TRANSPARENT HUGE PAGES (madvise = selective, safe)
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y

# CPU FREQUENCY SCALING (intel_cpufreq better than intel_pstate for 6-core)
CONFIG_X86_INTEL_CPUFREQ=y
CONFIG_X86_INTEL_PSTATE=n
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_POWERSAVE=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y

# CPU IDLE (allow efficient C-state limiting)
CONFIG_CPU_IDLE_INTEL=y
CONFIG_ACPI_PROCESSOR=y

# HARDWARE PREFETCHERS
CONFIG_X86_MSR=y

# TPM2 (for LUKS auto-unlock)
CONFIG_TCG_TPM=y
CONFIG_TCG_TIS=y
CONFIG_TCG_CRBB=y

# CRYPTOGRAPHY (LUKS, module signing)
CONFIG_CRYPTO_BLKCIPHER=m
CONFIG_CRYPTO_AES_NI_INTEL=m
CONFIG_CRYPTO_AES=m
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_RSA=y

# NVIDIA GPU SUPPORT (optional, for CUDA)
CONFIG_PCI_MSI=y
CONFIG_IOMMU_API=y

# SECURITY HARDENING (from boot chain)
CONFIG_LOCKDOWN_LSM=y
CONFIG_LOCKDOWN_LSM_EARLY=y
CONFIG_HAVE_EFFICIENT_UNALIGNED_ACCESS=y
CONFIG_HAVE_ARCH_SECCOMP_FILTER=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y

# IMA + EVM
CONFIG_IMA=y
CONFIG_IMA_ENFORCE=y
CONFIG_IMA_LOAD_X509=y
CONFIG_EVM=y
CONFIG_EVM_ATTR_FSUUID=y

# AUDIT
CONFIG_AUDIT=y
CONFIG_AUDIT_WATCH=y
CONFIG_AUDIT_TREE=y

EOF

  log "✓ Generated: $output_file"
}

generate_cpu_tuning_script() {
  local cores="$1" output_file="${2:-.}/tune-cpu.sh"
  
  log "Generating CPU tuning script for ${cores} cores..."
  
  cat > "$output_file" << EOF
#!/usr/bin/env bash
# CPU tuning script - i5-8600K (${cores} cores)
# Run with: sudo $output_file

set -euo pipefail

log(){ printf '[*] %s\n' "\$*"; }

# Set all CPUs to performance mode
log "Setting CPU frequency scaling to performance..."
for i in {0..$((${cores}-1))}; do
  echo performance | sudo tee /sys/devices/system/cpu/cpu\$i/cpufreq/scaling_governor
done

# Limit C-states to C3 (lower latency for desktop)
log "Limiting CPU idle states to C3..."
for cpu_path in /sys/devices/system/cpu/cpu*/cpuidle/state*; do
  if [ -d "\$cpu_path" ]; then
    state_num=\$(basename "\$cpu_path" | sed 's/state//')
    if [ "\$state_num" -gt 3 ]; then
      echo 1 | sudo tee "\$cpu_path/disable" > /dev/null
    fi
  fi
done

# Set energy performance preference to max (0=performance)
log "Setting energy performance preference to max..."
for pref in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
  [ -f "\$pref" ] && echo 0 | sudo tee "\$pref" > /dev/null || true
done

log "CPU tuning complete!"
log "Verify with: cat /proc/cpuinfo | grep MHz"
EOF

  chmod +x "$output_file"
  log "✓ Generated: $output_file"
  cat "$output_file"
}

generate_gpu_tuning_script() {
  local output_file="${1:-.}/tune-gpu.sh"
  
  log "Generating GPU tuning script for GTX 1050 Ti..."
  
  cat > "$output_file" << 'EOF'
#!/usr/bin/env bash
# GPU tuning script - GTX 1050 Ti (Pascal SM 6.1)
# Run with: sudo tune-gpu.sh

set -euo pipefail

has(){ command -v "$1" >/dev/null 2>&1; }
log(){ printf '[*] %s\n' "$*"; }

has nvidia-smi || { echo "nvidia-smi not found"; exit 1; }

# Enable persistent GPU mode (faster GPU init)
log "Enabling persistent GPU mode..."
nvidia-smi -pm 1

# Enable persistence daemon
log "Enabling persistence daemon..."
systemctl enable nvidia-persistenced 2>/dev/null || true
systemctl start nvidia-persistenced 2>/dev/null || true

# Check and display GPU status
log "GPU current status:"
nvidia-smi -q | grep -E "Persistence Mode|GPU Utilization|GPU Memory"

log "GPU tuning complete!"
log "Environment variables should be sourced from: ~/.bashrc or /etc/profile.d/"
EOF

  chmod +x "$output_file"
  log "✓ Generated: $output_file"
  cat "$output_file"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

main() {
  log "═══════════════════════════════════════════════════════════════════════════"
  log "CachyOS Hardware Detection + Auto-Tuning for i5-8600K + GTX 1050 Ti"
  log "═══════════════════════════════════════════════════════════════════════════"
  
  # Detect hardware
  CPU_DATA=$(detect_cpu)
  RAM_DATA=$(detect_ram)
  GPU_DATA=$(detect_gpu)
  STORAGE_DATA=$(detect_storage)
  TPM_DATA=$(detect_tpm)
  
  # Source detection results
  eval "$CPU_DATA"
  eval "$RAM_DATA"
  eval "$GPU_DATA"
  eval "$STORAGE_DATA"
  eval "$TPM_DATA"
  
  # Create output directory
  local output_dir="/tmp/cachyos-hw-tuning-$(date +%s)"
  mkdir -p "$output_dir"
  log "Output directory: $output_dir"
  
  # Generate all tuning files
  generate_sysctl_tuning "$RAM_GB" "$CPU_CORES" "$output_dir"
  generate_gpu_profile "$GPU_NAME" "$output_dir"
  generate_kernel_config "$output_dir"
  generate_cpu_tuning_script "$CPU_CORES" "$output_dir"
  generate_gpu_tuning_script "$output_dir"
  
  # Summary
  log ""
  log "═══════════════════════════════════════════════════════════════════════════"
  log "GENERATED TUNING FILES"
  log "═══════════════════════════════════════════════════════════════════════════"
  ls -lah "$output_dir"
  
  log ""
  log "NEXT STEPS:"
  log ""
  log "1. Apply sysctl tuning (persistent):"
  log "   sudo cp $output_dir/99-cachyos-localized.conf /etc/sysctl.d/"
  log "   sudo sysctl -p /etc/sysctl.d/99-cachyos-localized.conf"
  log ""
  log "2. Apply GPU optimization (session):"
  log "   source $output_dir/nvidia-optimization.profile"
  log ""
  log "3. Apply CPU tuning (requires sudo, affects all cores):"
  log "   sudo bash $output_dir/tune-cpu.sh"
  log ""
  log "4. Apply GPU tuning (requires sudo, affects GPU):"
  log "   sudo bash $output_dir/tune-gpu.sh"
  log ""
  log "5. Use kernel config for custom build:"
  log "   cp $output_dir/config.x86-64-v2-localized ~/Projects/sbh/config/"
  log ""
}

main "$@"
