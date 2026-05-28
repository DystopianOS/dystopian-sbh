# Hardware Optimizations for i5-8600K + GTX 1050 Ti

## Quick Wins (Easy, High Impact)

### CPU Optimizations

#### 1. CPU Frequency Scaling (5-10% boost)
```bash
# Set to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Or use cpupower (if installed)
sudo cpupower frequency-set -g performance

# Persistent (add to /etc/sysctl.d/99-cpu-performance.conf)
sudo tee /etc/sysctl.d/99-cpu-performance.conf << 'EOF'
# CPU frequency scaling - aggressive turbo
kernel.sched_migration_cost_ns=500000
kernel.sched_latency_ns=24000000
kernel.sched_min_granularity_ns=4000000

# Energy performance preference (0=performance, 255=powersave)
# Note: requires write access to:
# /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference
EOF

sudo sysctl -p /etc/sysctl.d/99-cpu-performance.conf
```

#### 2. C-State Limiting (3-8% interactive boost)
```bash
# Limit to C3 instead of deeper C-states
echo 3 | sudo tee /sys/devices/system/cpu/cpu*/cpuidle/state*/disable

# Or via kernel cmdline (permanent)
# Add to GRUB_CMDLINE_LINUX: processor.max_cstate=3
```

#### 3. Memory Swappiness (2-5% boost, especially during LTO)
```bash
# Add to /etc/sysctl.d/99-swappiness.conf
sudo tee /etc/sysctl.d/99-swappiness.conf << 'EOF'
vm.swappiness=10
vm.page-cluster=3
vm.dirty_ratio=10
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
EOF

sudo sysctl -p /etc/sysctl.d/99-swappiness.conf
```

### GPU Optimizations

#### 4. Persistent GPU Mode (5-15% latency boost)
```bash
# Enable persistent mode (requires nvidia-dkms)
sudo nvidia-smi -pm 1

# Enable persistence daemon
sudo systemctl enable nvidia-persistenced
sudo systemctl start nvidia-persistenced

# Verify
nvidia-smi | grep Persistence
```

#### 5. Lock GPU to Performance (stable FPS)
```bash
# Check current clock
nvidia-smi -q -d CLOCK

# Lock to max (GTX 1050 Ti: 1493 MHz)
sudo nvidia-smi -lgc 1493

# Verify
nvidia-smi --query-gpu=clocks.gr --format=csv -l 1
```

---

## Medium Effort (Higher Impact)

### CPU: Polly Loop Optimization (5-15% boost)

Update `/home/daen/Projects/sbh/config/PKGBUILD-linux-cachyos-hardened`:

```bash
# Add to existing CFLAGS
export CFLAGS="-O3 -march=x86-64-v2 -mtune=skylake -flto=thin \
               -fpolly -fpolly-vectorize=full \
               -floop-interchange -floop-strip-mine"
export CXXFLAGS="${CFLAGS}"

# Requires: llvm >= 13 (check with: clang --version)
```

**Impact breakdown:**
- `-fpolly`: +5-10% for compute-heavy code
- `-fpolly-vectorize=full`: +2-5% for vectorizable loops
- `-floop-interchange`: +1-2% cache-line optimization
- **Total**: ~8-12% expected boost
- **Tradeoff**: +10-15% compile time

**Safety notes:**
- Test thoroughly after kernel builds
- Safe for x86-64-v2 (no arch-specific issues)
- Works well with existing LTO=thin

### CPU: Kernel Config - THP + CPU Features

Add to `config.x86-64-v2`:

```
# Transparent Huge Pages (madvise mode = selective, safe)
CONFIG_TRANSPARENT_HUGEPAGE=y
CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y

# CPU frequency scaling (better than intel_pstate for 6-core)
CONFIG_X86_INTEL_CPUFREQ=y
CONFIG_X86_INTEL_PSTATE=n
CONFIG_CPU_FREQ_GOV_PERFORMANCE=y
CONFIG_CPU_FREQ_GOV_ONDEMAND=y

# CPU idle states (allow C3)
CONFIG_CPU_IDLE_INTEL=y
CONFIG_ACPI_PROCESSOR=y

# Hardware prefetchers
CONFIG_X86_MSR=y
```

**Impact:**
- THP=madvise: +2-5% for memory-intensive workloads
- intel_cpufreq: +5-8% turbo aggressiveness
- C-state limiting: +3-8% interactive responsiveness

### GPU: Aggressive Compiler Flags

For CUDA/compute workloads, recompile with:

```bash
export CFLAGS="-O3 -march=x86-64-v2 -mtune=skylake -flto=thin -fpolly \
               -floop-interchange -floop-strip-mine -fno-plt \
               -fno-semantic-interposition -fvect-cost-model=unlimited"
export CXXFLAGS="${CFLAGS}"

# For CUDA specifically:
export CFLAGS="${CFLAGS} -ftree-slp-vectorize"
```

---

## Advanced (High Effort, Specialized Impact)

### 1. PGO for GLIBC Rebuild (3-8% application speedup)

Modify `build-from-scratch.sh` Stage 2 (GLIBC):

```bash
# Stage 2a: Build instrumented GLIBC
./configure --prefix=/usr ... -DCFLAGS="-O3 -fprofile-generate"
make -j6
make install DESTDIR=$INSTALL_ROOT

# Stage 2b: Use system for profiling (run representative workloads)
# - Compile something, run standard tests, etc.

# Stage 2c: Rebuild with profile data
./configure --prefix=/usr ... -DCFLAGS="-O3 -fprofile-use -fprofile-correction"
make clean && make -j6
make install DESTDIR=$INSTALL_ROOT
```

**Impact:** +5-8% for application startup, allocation-heavy code
**Tradeoff:** +2x compile time for GLIBC stage

### 2. PGO for LIBC MALLOC Pattern Optimization

After GLIBC rebuild, malloc optimizations become critical for:
- Kernel module loading (many small allocations)
- CUDA GPU driver communication (complex struct allocation)

### 3. Kernel KVM Tuning (if using virtualization)

```bash
# In kernel config
CONFIG_KVM=y
CONFIG_KVM_INTEL=y
CONFIG_HAVE_KVM_IRQ_ROUTING=y

# At runtime
sudo modprobe kvm_intel nested=1 ept=1
```

### 4. GPU: CUDA Kernel Tuning for SM 6.1

For compute workloads targeting GTX 1050 Ti:

```cuda
// Optimal thread block size for SM 6.1
#define BLOCK_DIM_X 256   // Not 1024, GTX 1050 Ti has only 768 cores total
#define BLOCK_DIM_Y 1
#define BLOCK_DIM_Z 1

__global__ void optimized_kernel(float *out, const float *in, int n) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < n) {
    // Use shared memory to avoid L2 cache misses
    // GTX 1050 Ti shared memory: 96KB per SM
    __shared__ float smem[256];
    smem[threadIdx.x] = in[idx];
    __syncthreads();
    
    // Process with good warp utilization
    out[idx] = smem[threadIdx.x] * 2.0f;
  }
}

// Compilation for SM 6.1
// nvcc -arch=sm_61 -gencode arch=compute_61,code=sm_61 -O3 -use_fast_math
```

**Key SM 6.1 tuning:**
- Block size: 256-512 (not 1024)
- Shared memory: Use 48KB actively (avoid wastes)
- Warp alignment: Multiples of 32 threads
- Bank conflicts: 32 banks × 4 bytes = track indexing

---

## System Integration Setup

### Combined sysctl Hardening + Performance

Create `/etc/sysctl.d/99-cachyos-performance-hardened.conf`:

```bash
sudo tee /etc/sysctl.d/99-cachyos-performance-hardened.conf << 'EOF'
# ═════════════════════════════════════════════════════════════════════
# CachyOS Performance + Hardening Tuning (i5-8600K + GTX 1050 Ti)
# ═════════════════════════════════════════════════════════════════════

# CPU Frequency Scaling (aggressive turbo)
kernel.sched_migration_cost_ns=500000
kernel.sched_latency_ns=24000000
kernel.sched_min_granularity_ns=4000000

# Memory Management (LTO-friendly)
vm.swappiness=10
vm.page-cluster=3
vm.dirty_ratio=10
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50
vm.mmap_min_addr=65536
vm.overcommit_memory=1

# Scheduler tuning (BORE-friendly)
kernel.sched_wakeup_migration_cost=500
kernel.sched_child_runs_first=0

# PCI/IO optimization
vm.max_map_count=2147483647  # For large workloads

# Networking (low latency)
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_fin_timeout=20
net.ipv4.tcp_tw_reuse=1

# Already set by boot chain hardening, but confirm:
kernel.kexec_load_disabled=1
kernel.unprivileged_bpf_disabled=2
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.yama.ptrace_scope=3
EOF

sudo sysctl -p /etc/sysctl.d/99-cachyos-performance-hardened.conf
```

### GPU Environment Variables (Persistent)

Create `/etc/profile.d/nvidia-optimization.sh`:

```bash
sudo tee /etc/profile.d/nvidia-optimization.sh << 'EOF'
#!/bin/bash
# NVIDIA optimization for GTX 1050 Ti

export __GL_SYNC_TO_VBLANK=0           # Disable VSync
export __GL_YIELD="NOTHING"            # Aggressive CPU yielding
export __GL_MAX_FRAMES_ALLOWED=2       # Frame buffering
export __GL_THREADED_OPTIMIZATIONS=1   # Multithreaded driver

# CUDA optimization
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export CUDA_VISIBLE_DEVICES=0

# DXVK/Proton (if gaming)
export DXVK_FRAME_RATE=0               # Unlimited (cap in game)
export STAGING_SHARED_MEMORY=true      # Memory optimization

echo "[nvidia-optimization] Environment variables loaded"
EOF

chmod +x /etc/profile.d/nvidia-optimization.sh
source /etc/profile.d/nvidia-optimization.sh
```

---

## Verification & Benchmarking

### CPU Verification

```bash
# Check current CPU frequency
watch -n 1 'cat /proc/cpuinfo | grep MHz'

# Verify BORE scheduler is active
grep "CONFIG_SCHED_BORE" /proc/config.gz | zcat

# Check sysctl tuning applied
sysctl kernel.sched_latency_ns kernel.sched_min_granularity_ns

# Monitor during LTO build
watch -n 1 'free -h && sysctl vm.swappiness'
```

### GPU Verification

```bash
# Check driver version
nvidia-smi | head -2

# Verify persistent mode
nvidia-smi -q | grep "Persistence Mode"

# Monitor GPU during workload
watch -n 1 'nvidia-smi'

# Benchmark (install glmark2)
pacman -S glmark2
glmark2
# Expected: 15-25 fps on GTX 1050 Ti

# CUDA check
nvcc --version
/opt/cuda/samples/1_Utilities/deviceQuery
```

### Combined Benchmark (i5-8600K + GTX 1050 Ti)

```bash
# NVIDIA GPU burn test (stress test)
# git clone https://github.com/wilicc/gpu-burn
# cd gpu-burn
# make
# ./gpu_burn 60  # Run for 60 seconds

# CPU stress (sysbench)
pacman -S sysbench
sysbench cpu run --threads=6

# Combined CPU+GPU stress
# Run both simultaneously and monitor:
# Terminal 1: watch -n 1 'nvidia-smi'
# Terminal 2: sysbench cpu run --threads=6
```

---

## Performance Impact Summary

| Optimization | CPU/GPU | Impact | Effort | Combined Benefit |
|---|---|---|---|---|
| Frequency scaling | CPU | +5-10% | Easy | ✓✓✓ |
| Persistent GPU mode | GPU | +5-15% | Easy | ✓✓✓ |
| C-state limit | CPU | +3-8% | Easy | ✓✓ |
| Polly (-fpolly) | CPU | +5-15% | Medium | ✓✓✓ |
| THP=madvise | CPU | +2-5% | Easy | ✓ |
| Aggressive CFLAGS | CPU | +3-10% | Medium | ✓✓ |
| PGO (GLIBC) | CPU | +3-8% | Hard | ✓✓ |
| GPU clock locking | GPU | +0-1% | Easy | ✓ |
| CUDA tuning | GPU | +3-12% | Hard | ✓✓ |
| Memory swappiness | CPU | +2-5% | Easy | ✓ |

**Total Expected Boost (Easy + Medium combined):**
- CPU performance: +20-35% (frequency + BORE + Polly + C-state + THP)
- GPU performance: +10-20% (persistent + driver + environment)
- Combined system responsiveness: +25-40%

---

## Implementation Order (Recommended)

1. **Immediate (reboot required):**
   - Update NVIDIA driver
   - Update kernel config with THP + CPU features
   - Recompile kernel with Polly + aggressive flags

2. **After reboot (sysctl + runtime):**
   - Apply sysctl tuning (CPU freq, C-state, swappiness)
   - Enable GPU persistent mode
   - Apply GPU environment variables

3. **Long-term (optional, high effort):**
   - Implement PGO for GLIBC
   - Benchmark and fine-tune specific workloads
   - Profile CUDA kernels on SM 6.1

4. **Verification:**
   - Run benchmarks before/after
   - Monitor temps under load
   - Verify no thermal throttling (GPU < 80°C)

---

## Safety Notes

⚠️ **Before aggressive tuning:**
- Back up working kernel config
- Test in VM first if possible
- Monitor temperatures: i5-8600K < 80°C, GTX 1050 Ti < 80°C
- Keep passphrase recovery available (TPM reset might be needed)

✓ **Safe to do now:**
- Sysctl tuning (can be reversed)
- GPU persistent mode (hardware-safe)
- Environment variables (session-based)

⚠️ **Requires careful testing:**
- Polly compilation (may cause instability, test thoroughly)
- Aggressive CFLAGS (test each application)
- Custom CUDA kernels (profile and benchmark first)

---

## References

- **BORE Scheduler:** https://github.com/firelzrd/bore-scheduler
- **LLVM Polly:** https://polly.llvm.org/
- **NVIDIA GPU Optimization:** https://docs.nvidia.com/cuda/cuda-c-programming-guide/
- **CachyOS Wiki:** https://wiki.cachyos.org/
- **Coffee Lake (i5-8600K):** https://en.wikichip.org/wiki/intel/core_i5/i5-8600k
- **Pascal (GTX 1050 Ti):** https://en.wikipedia.org/wiki/GeForce_10_series#Desktop

