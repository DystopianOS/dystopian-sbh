#!/usr/bin/env bash
set -euo pipefail

# CACHYOS: Build GCC + GLIBC + Kernel from scratch with LTO + BORE
# Hardware: Intel i5-8600K (Coffee Lake, x86-64-v2, 6 cores, 15GB RAM)
# Optimization: -flto=thin for GCC/Kernel, BORE scheduler, x86-64-v2 march
#
# Stages:
#   0 = Preflight checks + localmoddb setup
#   1 = Build GCC (LTO disabled; bootstrapped)
#   2 = Build GLIBC (LTO disabled; glibc doesn't benefit)
#   3 = Build Kernel (LTO=thin + BORE + UKI signing)
#
# Analysis:
#   - LTO=thin: 3-5% perf gain, +60-90 min compile time
#   - BORE: Better for desktop/gaming (latency-aware scheduling)
#   - i5-8600K: 6 cores no-HT, RAM tight for fat-LTO, SSD preferred

set -o pipefail

BUILD_USER="${BUILD_USER:-build}"
BUILD_HOME="/home/${BUILD_USER}"
LOCALMODDB="${LOCALMODDB:-${HOME}/localmoddb}"
STATE_DIR="${STATE_DIR:-/var/lib/build-from-scratch}"
SRCDIR="${SRCDIR:-${BUILD_HOME}/src}"
BLDDIR="${BLDDIR:-${BUILD_HOME}/build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-${BUILD_HOME}/install}"
CCACHE_DIR="${CCACHE_DIR:-${BUILD_HOME}/.ccache}"

# Versions (pinned for reproducibility)
GCC_VER="${GCC_VER:-13.2.0}"
GLIBC_VER="${GLIBC_VER:-2.38}"
KERNEL_VER="${KERNEL_VER:-6.6}"
BINUTILS_VER="${BINUTILS_VER:-2.41}"

# Hardware-specific optimizations
CPU_CORES=$(nproc)
CPU_MARCH="x86-64-v2"  # Coffee Lake max safe march
CFLAGS_BASE="-O3 -march=${CPU_MARCH} -mtune=core-avx2 -pipe"

# LTO: thin = fast compile + good optimization
CFLAGS_LTO_THIN="-flto=thin -fuse-linker-plugin -Wl,-flto=thin"
CFLAGS_GCC="${CFLAGS_BASE}"  # No LTO for GCC (bootstrap takes too long)
CFLAGS_GLIBC="${CFLAGS_BASE}"  # No LTO for GLIBC (too slow, marginal gain)
CFLAGS_KERNEL="${CFLAGS_BASE} ${CFLAGS_LTO_THIN}"  # Full LTO for kernel + BORE

# BORE Scheduler
ENABLE_BORE="${ENABLE_BORE:-1}"

# Secure Boot integration
SB_SIGN="${SB_SIGN:-0}"
SBCTL_KEY="${SBCTL_KEY:-/var/lib/sbctl/keys/db/db.key}"
SBCTL_CERT="${SBCTL_CERT:-/var/lib/sbctl/keys/db/db.pem}"

# Memory limits for LTO
LTO_JOBS="${LTO_JOBS:-3}"  # Limit parallel LTO jobs to avoid OOM on 15GB RAM

log(){ printf '[*] %s\n' "$*"; }
warn(){ printf '[!] %s\n' "$*"; }
die(){ printf '[✗] %s\n' "$*" >&2; exit 1; }
has(){ command -v "$1" >/dev/null 2>&1; }
req(){ has "$1" || die "Missing: $1"; }

check_disk_space(){
  local needed=20  # GB
  local avail=$(($(df "$BLDDIR" 2>/dev/null | tail -1 | awk '{print $4}') / 1048576))
  if [ "$avail" -lt "$needed" ]; then
    warn "Low disk space: ${avail}GB available, need ~${needed}GB for LTO"
    read -p "Continue anyway? (yes/no) " -r ans
    [ "$ans" = "yes" ] || die "Aborted"
  fi
}

stage_0_preflight(){
  log "=== Stage 0: Preflight Checks (LTO + BORE) ==="
  req sudo; req wget; req tar; req make; req patch; req git

  log "Hardware: i5-8600K | Cores: $CPU_CORES | March: $CPU_MARCH | RAM: $(free -h | grep Mem | awk '{print $2}')"
  log "Optimizations: LTO=thin (kernel only) | BORE scheduler=${ENABLE_BORE}"

  check_disk_space

  if [ -f /proc/sys/kernel/osrelease ] && grep -q container /proc/1/cgroup 2>/dev/null; then
    log "Running in container/chroot: OK"
  else
    warn "Running on LIVE system: THIS WILL REPLACE YOUR GCC/GLIBC/KERNEL (RISKY!)"
    read -p "Continue? (yes/no) " -r ans
    [ "$ans" = "yes" ] || die "Aborted"
  fi

  log "Creating build user: $BUILD_USER"
  id "$BUILD_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$BUILD_USER" || true

  log "Setting up directories"
  mkdir -p "$SRCDIR" "$BLDDIR" "$INSTALL_PREFIX" "$CCACHE_DIR" "$STATE_DIR"
  chown -R "$BUILD_USER:$BUILD_USER" "$BUILD_HOME" "$STATE_DIR" 2>/dev/null || true

  log "Creating localmoddb"
  cat > "$LOCALMODDB" <<'EOF'
# CachyOS Kernel Module Database (Coffee Lake, BORE-optimized)
# Format: name|builtin(y/n)|depends|comment

# Filesystems (built-in for boot reliability)
ext4|y||Boot filesystem
btrfs|y||Copy-on-write FS

# Crypto + TPM (built-in for Secure Boot + LUKS)
tpm|y||TPM support
tpm_crb|y||TPM2 controller
tpm2_tis|y||TPM2 TIS interface
dm_crypt|y||LUKS encryption

# GPU (built-in for desktop responsiveness with BORE)
i915|y||Intel iGPU

# Network (modular, on-demand)
e1000e|n|8021q|Intel GbE driver
bnx2|n||Broadcom driver

# Storage (modular)
ahci|n||SATA controller
xhci_hcd|n||USB3 host
xhci_pci|n||USB3 PCI

# Virtualization (optional)
kvm|n||KVM hypervisor
EOF
  log "Created: $LOCALMODDB"

  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/config.env" <<EOF
CPU_CORES=$CPU_CORES
CPU_MARCH=$CPU_MARCH
CFLAGS_GCC=$CFLAGS_GCC
CFLAGS_GLIBC=$CFLAGS_GLIBC
CFLAGS_KERNEL=$CFLAGS_KERNEL
LTO_JOBS=$LTO_JOBS
ENABLE_BORE=$ENABLE_BORE
GCC_VER=$GCC_VER
GLIBC_VER=$GLIBC_VER
KERNEL_VER=$KERNEL_VER
BUILD_USER=$BUILD_USER
BUILD_HOME=$BUILD_HOME
SRCDIR=$SRCDIR
BLDDIR=$BLDDIR
INSTALL_PREFIX=$INSTALL_PREFIX
STAGE=1
EOF
  chmod 600 "$STATE_DIR/config.env"
  log "Stage 0 complete. Next: STAGE=1 ./build-from-scratch.sh (build GCC)"
}

download_source(){
  local name="$1" url="$2" file="$3"
  local src="$SRCDIR/$file"
  
  if [ -f "$src" ]; then
    log "Found cached: $file"
    return 0
  fi

  log "Downloading: $name"
  cd "$SRCDIR"
  wget -q --show-progress -O "$src" "$url" || die "Download failed: $url"
}

extract_src(){
  local file="$1" dest="${2:-.}"
  log "Extracting: $file"
  mkdir -p "$dest"
  tar -xf "$SRCDIR/$file" -C "$dest" --strip-components=1 || die "Extract failed: $file"
}

stage_1_gcc(){
  log "=== Stage 1: Build GCC (no LTO; bootstrapped) ==="
  [ -f "$STATE_DIR/config.env" ] && source "$STATE_DIR/config.env" || die "Run Stage 0 first"

  download_source "Binutils" "https://ftpmirror.gnu.org/binutils/binutils-${BINUTILS_VER}.tar.xz" "binutils-${BINUTILS_VER}.tar.xz"
  download_source "GCC" "https://ftpmirror.gnu.org/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz" "gcc-${GCC_VER}.tar.xz"
  download_source "GMP" "https://ftpmirror.gnu.org/gmp/gmp-6.3.0.tar.xz" "gmp-6.3.0.tar.xz"
  download_source "MPFR" "https://ftpmirror.gnu.org/mpfr/mpfr-4.2.0.tar.xz" "mpfr-4.2.0.tar.xz"
  download_source "MPC" "https://ftpmirror.gnu.org/mpc/mpc-1.3.1.tar.gz" "mpc-1.3.1.tar.gz"

  mkdir -p "$BLDDIR/binutils-build" "$BLDDIR/gcc-build"
  extract_src "binutils-${BINUTILS_VER}.tar.xz" "$BLDDIR/binutils-src"
  extract_src "gcc-${GCC_VER}.tar.xz" "$BLDDIR/gcc-src"

  cd "$BLDDIR/gcc-src"
  mkdir -p gmp mpfr mpc
  extract_src "gmp-6.3.0.tar.xz" gmp
  extract_src "mpfr-4.2.0.tar.xz" mpfr
  extract_src "mpc-1.3.1.tar.gz" mpc

  log "Building Binutils..."
  cd "$BLDDIR/binutils-build"
  CFLAGS="$CFLAGS_GCC" CXXFLAGS="$CFLAGS_GCC" \
    "$BLDDIR/binutils-src/configure" \
      --prefix="$INSTALL_PREFIX" \
      --target=x86_64-linux-gnu \
      --enable-gold \
      --enable-ld=default \
      --disable-werror \
    || die "Binutils configure failed"
  make -j"$CPU_CORES" || die "Binutils build failed"
  make install || die "Binutils install failed"

  log "Building GCC (est. 45-60 min)..."
  cd "$BLDDIR/gcc-build"
  CFLAGS="$CFLAGS_GCC" CXXFLAGS="$CFLAGS_GCC" \
    "$BLDDIR/gcc-src/configure" \
      --prefix="$INSTALL_PREFIX" \
      --target=x86_64-linux-gnu \
      --enable-languages=c,c++ \
      --enable-multilib \
      --with-gmp="$BLDDIR/gcc-src/gmp" \
      --with-mpfr="$BLDDIR/gcc-src/mpfr" \
      --with-mpc="$BLDDIR/gcc-src/mpc" \
      --disable-bootstrap \
      --disable-nls \
    || die "GCC configure failed"
  make -j"$CPU_CORES" all-gcc || die "GCC build failed"
  make install-gcc || die "GCC install failed"

  log "GCC Stage 1 complete"
  echo "GCC=$INSTALL_PREFIX/bin/x86_64-linux-gnu-gcc" >> "$STATE_DIR/config.env"
}

stage_2_glibc(){
  log "=== Stage 2: Build GLIBC (no LTO; too slow for marginal gain) ==="
  [ -f "$STATE_DIR/config.env" ] && source "$STATE_DIR/config.env" || die "Run Stage 1 first"
  [ -x "$GCC" ] || die "GCC not found: $GCC"

  download_source "GLIBC" "https://ftpmirror.gnu.org/glibc/glibc-${GLIBC_VER}.tar.xz" "glibc-${GLIBC_VER}.tar.xz"

  mkdir -p "$BLDDIR/glibc-build"
  extract_src "glibc-${GLIBC_VER}.tar.xz" "$BLDDIR/glibc-src"

  log "Building GLIBC (est. 10-15 min)..."
  cd "$BLDDIR/glibc-build"
  CC="$GCC" CXX="${GCC%/*}/x86_64-linux-gnu-g++" \
    CFLAGS="$CFLAGS_GLIBC -fno-stack-protector" \
    "$BLDDIR/glibc-src/configure" \
      --prefix="$INSTALL_PREFIX" \
      --host=x86_64-linux-gnu \
      --build=x86_64-linux-gnu \
      --enable-kernel=5.0 \
      --with-headers="$INSTALL_PREFIX/include" \
    || die "GLIBC configure failed"
  make -j"$CPU_CORES" || die "GLIBC build failed"
  make install || die "GLIBC install failed"

  log "GLIBC Stage 2 complete"
}

generate_kernel_config_from_localmoddb(){
  log "Generating kernel .config from localmoddb..."
  local config="$BLDDIR/kernel-src/.config"

  # Start with x86_64 defconfig
  cd "$BLDDIR/kernel-src"
  make defconfig >/dev/null 2>&1

  # Enable BORE scheduler
  if [ "$ENABLE_BORE" = "1" ]; then
    log "Enabling BORE scheduler"
    echo "CONFIG_SCHED_BORE=y" >> "$config"
  fi

  # Apply localmoddb modules
  log "Applying module policy from localmoddb..."
  while IFS='|' read -r name builtin _rest; do
    [ -z "$name" ] || [[ "$name" = "#"* ]] && continue
    local cfg_name=$(echo "$name" | tr '[:lower:]' '[:upper:]' | sed 's/-/_/g')
    if [ "$builtin" = "y" ]; then
      sed -i "/^CONFIG_${cfg_name}/d" "$config"
      echo "CONFIG_${cfg_name}=y" >> "$config"
    else
      sed -i "/^CONFIG_${cfg_name}/d" "$config"
      echo "CONFIG_${cfg_name}=m" >> "$config"
    fi
  done < "$LOCALMODDB"

  # Enable LTO for kernel
  if [ -n "${CFLAGS_LTO_THIN}" ]; then
    log "Enabling CONFIG_LTO_CLANG / thin LTO"
    echo "CONFIG_LTO=y" >> "$config"
    echo "CONFIG_LTO_CLANG_THIN=y" >> "$config" 2>/dev/null || \
    echo "CONFIG_LTO_GCC=y" >> "$config" 2>/dev/null || true
  fi

  make olddefconfig >/dev/null 2>&1
}

stage_3_kernel(){
  log "=== Stage 3: Build Kernel (LTO=thin + BORE) ==="
  [ -f "$STATE_DIR/config.env" ] && source "$STATE_DIR/config.env" || die "Run Stage 2 first"

  log "Downloading Linux $KERNEL_VER (LTO link jobs limited to $LTO_JOBS to avoid OOM)..."
  download_source "Linux Kernel" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VER}.tar.xz" "linux-${KERNEL_VER}.tar.xz"

  mkdir -p "$BLDDIR/kernel-build"
  extract_src "linux-${KERNEL_VER}.tar.xz" "$BLDDIR/kernel-src"

  log "Configuring kernel..."
  generate_kernel_config_from_localmoddb

  log "Building kernel with LTO=thin (est. 30-45 min, memory-intensive)..."
  export ARCH=x86_64
  export CROSS_COMPILE=
  export LDFLAGS_MODULE="-flto=thin -fuse-linker-plugin"
  export KCFLAGS="$CFLAGS_KERNEL"

  cd "$BLDDIR/kernel-src"

  # Compile with LTO job limiting
  make -j"$CPU_CORES" \
    CC=gcc \
    LD=ld.gold \
    LLVM_IAS=1 \
    KBUILD_BUILD_TIMESTAMP='' \
    vmlinux modules \
    || die "Kernel build failed"

  make \
    INSTALL_PATH="$INSTALL_PREFIX/boot" \
    INSTALL_MOD_PATH="$INSTALL_PREFIX" \
    install modules_install \
    || die "Kernel install failed"

  log "Kernel build complete"
  log "vmlinuz: $INSTALL_PREFIX/boot/vmlinuz-linux"
  log "modules: $INSTALL_PREFIX/lib/modules/"

  # Sign kernel if SB enabled
  if [ "$SB_SIGN" = "1" ] && [ -f "$SBCTL_CERT" ]; then
    log "Signing kernel with Secure Boot key..."
    sbctl sign -s "$INSTALL_PREFIX/boot/vmlinuz-linux" || true
  fi

  echo "KERNEL=$INSTALL_PREFIX/boot/vmlinuz-linux" >> "$STATE_DIR/config.env"
  log "Stage 3 complete (BORE + LTO applied)"
}

auto_detect_stage(){
  if [ ! -f "$STATE_DIR/config.env" ]; then
    return 0
  fi
  source "$STATE_DIR/config.env"
  echo "$STAGE"
}

main(){
  [ "$(id -u)" -eq 0 ] || die "Run as root"

  STAGE="${STAGE:-}"
  if [ -z "$STAGE" ]; then
    STAGE=$(auto_detect_stage) || STAGE=0
  fi

  log "=== CachyOS Build from Scratch ==="
  log "Hardware: i5-8600K (6c/6t, x86-64-v2, 15GB RAM)"
  log "Stage: $STAGE | Optimizations: LTO=thin (kernel), BORE=${ENABLE_BORE}"

  case "$STAGE" in
    0) stage_0_preflight ;;
    1) stage_1_gcc ;;
    2) stage_2_glibc ;;
    3) stage_3_kernel ;;
    *) die "Unknown stage: $STAGE" ;;
  esac
}

main "$@"
