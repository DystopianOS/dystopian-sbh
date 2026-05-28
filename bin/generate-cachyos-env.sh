#!/usr/bin/env bash
# Generate customized CachyOS PKGBUILD for i5-8600K + GTX 1050 Ti
# Uses official CachyOS repo + hardware-specific overrides

set -euo pipefail

log() { printf '[*] %s\n' "$*"; }
die() { printf '[✗] %s\n' "$*" >&2; exit 1; }

# ═══════════════════════════════════════════════════════════════════════════
# HARDWARE PROFILES
# ═══════════════════════════════════════════════════════════════════════════

generate_env_file() {
  local variant="$1" output="$2"
  
  log "Generating environment for variant: $variant"
  
  case "$variant" in
    native-minimal)
      cat > "$output" << 'EOF'
# Native minimal build for i5-8600K (THIS HOST ONLY)
export _cachy_config=yes
export _cpusched=bore                    # BORE for latency
export _makenconfig=no
export _makexconfig=no
export _localmodcfg=yes                  # Use modprobed.db (only needed modules)
export _localmodcfg_path="$HOME/.config/modprobed.db"
export _use_current=no
export _cc_harder=yes                    # -O3 compilation
export _per_gov=no
export _tcp_bbr3=no
export _HZ_ticks=1000                    # 1000Hz timer (responsive desktop)
export _tickrate=full                    # Full tickless (higher performance)
export _preempt=full                     # Full preemption (lower latency)
export _hugepage=madvise                 # Safe THP (+ 2-5% perf)
export _processor_opt=native             # -march=native (i5-8600K specific, +3-8%)
export _use_llvm_lto=thin                # Thin LTO (balance perf/time)
export _use_llvm_lto_suffix=yes
export _cc_cflags="-O3 -march=native -mtune=native -fpolly -fpolly-vectorize=full -floop-interchange -floop-strip-mine"
export _cc_cxxflags="$_cc_cflags"
EOF
      ;;
    
    polly-optimized)
      cat > "$output" << 'EOF'
# Polly optimized (portable x86-64-v2)
export _cachy_config=yes
export _cpusched=bore
export _makenconfig=no
export _makexconfig=no
export _localmodcfg=yes
export _localmodcfg_path="$HOME/.config/modprobed.db"
export _use_current=no
export _cc_harder=yes
export _per_gov=no
export _tcp_bbr3=no
export _HZ_ticks=1000
export _tickrate=full
export _preempt=full
export _hugepage=madvise
export _processor_opt=""                 # Defaults to generic (portable)
export _use_llvm_lto=thin
export _use_llvm_lto_suffix=yes
export _cc_cflags="-O3 -march=x86-64-v2 -mtune=skylake -fpolly -fpolly-vectorize=full -floop-interchange -floop-strip-mine"
export _cc_cxxflags="$_cc_cflags"
EOF
      ;;
    
    hardened-minimal)
      cat > "$output" << 'EOF'
# Hardened minimal for i5-8600K (THIS HOST ONLY)
export _cachy_config=yes
export _cpusched=hardened                # Hardened BORE scheduler
export _makenconfig=no
export _makexconfig=no
export _localmodcfg=yes
export _localmodcfg_path="$HOME/.config/modprobed.db"
export _use_current=no
export _cc_harder=yes
export _per_gov=no
export _tcp_bbr3=no
export _HZ_ticks=1000
export _tickrate=full
export _preempt=full
export _hugepage=madvise
export _processor_opt=native             # Native for i5-8600K
export _use_llvm_lto=thin
export _use_llvm_lto_suffix=yes
export _cc_cflags="-O3 -march=native -mtune=native -fpolly -fpolly-vectorize=full"
export _cc_cxxflags="$_cc_cflags"
EOF
      ;;
    
    *)
      die "Unknown variant: $variant"
      ;;
  esac
  
  log "✓ Generated: $output"
  cat "$output"
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════

main() {
  log "Generating CachyOS PKGBUILD environment files for i5-8600K"
  
  local out_dir="/home/daen/Projects/sbh/config/cachyos-env"
  mkdir -p "$out_dir"
  
  generate_env_file "native-minimal" "$out_dir/native-minimal.env"
  generate_env_file "polly-optimized" "$out_dir/polly-optimized.env"
  generate_env_file "hardened-minimal" "$out_dir/hardened-minimal.env"
  
  log ""
  log "═══════════════════════════════════════════════════════════════════════════"
  log "BUILD INSTRUCTIONS"
  log "═══════════════════════════════════════════════════════════════════════════"
  log ""
  log "1. Clone CachyOS official repo:"
  log "   cd ~/ABS && git clone https://github.com/CachyOS/linux-cachyos.git"
  log "   cd linux-cachyos/linux-cachyos-bore"
  log ""
  log "2. Load environment for your build variant:"
  log "   source $out_dir/native-minimal.env          # Max perf, THIS HOST ONLY"
  log "   source $out_dir/polly-optimized.env         # Polly, portable"
  log "   source $out_dir/hardened-minimal.env        # Hardened + Polly"
  log ""
  log "3. Build:"
  log "   makepkg --skippgpcheck -fci"
  log ""
  log "4. After install, rebuild UKI + sign:"
  log "   sudo sbh-secureboot"
  log ""
}

main "$@"
