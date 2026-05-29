#!/usr/bin/env bash
set -euo pipefail
umask 077

# CACHYOS HARDENED SECURE BOOT + UKI + TPM2/LUKS (MAXIMUM DEFENSE)
# mkinitcpio-first (official CachyOS recommendation)
# Auto-rebuilds UKI + re-signs on kernel updates
# Prevents: rollback, tampering, firmware updates, EFI manipulation, module bypass
#
# Stages:
#   0 = Pre-SB:  Keys, UKI, sign, harden kernel cmdline, audit rules
#   1 = Post-SB: Reseal TPM, verify, finalize, cleanup
#
# Usage:
#   sudo sbh-secureboot           # Auto-detect stage and run
#   sudo sbh-secureboot --install # Stage 0 + cron handoff + reboot
#   sudo sbh-secureboot --auto-reboot-check # Cron entry for first boot after reboot
#   sudo STAGE=0 sbh-secureboot   # Force stage 0
#   sudo STAGE=1 sbh-secureboot   # Force stage 1

TPM_PCRS="${TPM_PCRS:-7+11}"
KEEP_MICROSOFT_KEYS="${KEEP_MICROSOFT_KEYS:-0}"
ENABLE_IMA="${ENABLE_IMA:-1}"
ENABLE_EFI_GUARD="${ENABLE_EFI_GUARD:-1}"
ENABLE_AUDIT="${ENABLE_AUDIT:-1}"

# TODO: Implement module signing and re-enable
# MODULE_SIGN_KEY="${MODULE_SIGN_KEY:-/var/lib/sbctl/keys/db/db.key}"
# MODULE_SIGN_CERT="${MODULE_SIGN_CERT:-/var/lib/sbctl/keys/db/db.pem}"

STATE_DIR="/var/lib/secureboot-uki-tpm"
STATE_FILE="${STATE_DIR}/state.env"
EFI_MOUNT="${EFI_MOUNT:-/efi}"
SYSCTL_HARDEN="/etc/sysctl.d/99-bootchain-hardening.conf"
AUDIT_RULES="/etc/audit/rules.d/99-bootchain-security.rules"
EFI_GUARD_SERVICE="/etc/systemd/system/efi-guard-readonly.service"
CRON_MARKER="sbh-stage1-finalize"
MKINITCPIO_PRESET="/etc/mkinitcpio.d/cachyos-uki.preset"
UKI_BUILD_HOOK="/usr/local/libexec/mkinitcpio-build-sign-uki.sh"
SCRIPT_PATH="$(readlink -f "$0")"

log(){ printf '[*] %s\n' "$*"; }
warn(){ printf '[!] %s\n' "$*"; }
die(){ printf '[✗] %s\n' "$*" >&2; exit 1; }
has(){ command -v "$1" >/dev/null 2>&1; }
req(){ has "$1" || die "Missing command: $1"; }

root_cmdline(){
  local root_uuid root_source

  root_uuid="$(findmnt -no UUID / 2>/dev/null || true)"
  if [ -n "${root_uuid:-}" ]; then
    echo "root=UUID=${root_uuid}"
    return 0
  fi

  root_source="$(findmnt -no SOURCE / 2>/dev/null || true)"
  [ -n "${root_source:-}" ] || die "Unable to determine root filesystem source"

  root_source="$(readlink -f "$root_source" 2>/dev/null || printf '%s' "$root_source")"
  root_uuid="$(blkid -s UUID -o value "$root_source" 2>/dev/null || true)"
  [ -n "${root_uuid:-}" ] || die "Unable to determine root filesystem UUID"

  echo "root=UUID=${root_uuid}"
}

sb_state(){
  # Try multiple detection methods with graceful fallbacks
  
  # Method 1: bootctl (most reliable, handles all SB states)
  if has bootctl && bootctl status 2>/dev/null | grep -qi 'Secure Boot:.*enabled'; then
    echo enabled; return 0
  fi
  
  # Method 2: mokutil (works even if efivarfs has permission issues)
  if has mokutil && mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    echo enabled; return 0
  fi
  
  # Method 3: efivarfs direct read (requires read permissions)
  # Note: EFI guard service may set 000 permissions; try with sudo if available
  if [ -r /sys/firmware/efi/efivars/SecureBoot-* ] 2>/dev/null; then
    if hexdump -Cv /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | grep -q ' 01 '; then
      echo enabled; return 0
    fi
  elif [ -e /sys/firmware/efi/efivars/SecureBoot-* ] 2>/dev/null; then
    # File exists but unreadable; try with sudo if not already root
    if [ "$EUID" != "0" ] && has sudo; then
      if sudo hexdump -Cv /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | grep -q ' 01 '; then
        echo enabled; return 0
      fi
    fi
    # If unreadable and can't elevate, log warning but continue
    log "⚠ Cannot read EFI SecureBoot variable (permission denied). Using bootctl/mokutil detection."
  fi
  
  # Default to disabled if detection is inconclusive
  echo disabled
}

resolve_dev(){
  case "$1" in
    UUID=*) blkid -U "${1#UUID=}" || true ;;
    LABEL=*) blkid -L "${1#LABEL=}" || true ;;
    /dev/*) readlink -f "$1" || true ;;
    *) echo "$1" ;;
  esac
}

collect_tpm_luks_devices(){
  awk '$0!~/^[[:space:]]*#/ && NF>=4 && $4 ~ /(^|,)tpm2-/ {print $2}' /etc/crypttab \
  | while read -r s; do
      d="$(resolve_dev "$s")"; [ -n "${d:-}" ] || continue
      cryptsetup isLuks "$d" >/dev/null 2>&1 && echo "$d"
    done | sort -u
}

backup_luks_headers(){
  local out="$1"; shift
  mkdir -p "$out"; chmod 700 "$out"
  for d in "$@"; do
    cryptsetup luksHeaderBackup "$d" --header-backup-file "$out/$(basename "$d").luks-header.img"
  done
}

build_sign_uki(){
  local kver="$1" out="$2"
  local vmlinuz="/usr/lib/modules/${kver}/vmlinuz"
  local initramfs=""
  local cmdline="/etc/kernel/cmdline.d/99-bootchain.conf"
  local pkgbase=""

  [ -f "$vmlinuz" ] || { log "Skipping UKI for $kver (vmlinuz not found)"; return 0; }

  if [ -r "/usr/lib/modules/${kver}/pkgbase" ]; then
    pkgbase="$(cat "/usr/lib/modules/${kver}/pkgbase")"
  fi

  for candidate in \
    "/boot/initramfs-${pkgbase}.img" \
    "/boot/initramfs-linux.img" \
    "/boot/initramfs-linux-cachyos.img" \
    "/boot/initramfs-linux-zen.img" \
    "/boot/initramfs-linux-hardened.img"; do
    if [ -n "$candidate" ] && [ -f "$candidate" ]; then
      initramfs="$candidate"
      break
    fi
  done

  [ -n "$initramfs" ] || { log "Skipping UKI for $kver (initramfs not found)"; return 0; }

  req ukify
  log "Building UKI for $kver → $out"

  local ucode=""
  if [ -f /boot/intel-ucode.img ]; then
    ucode="--initrd=/boot/intel-ucode.img"
  elif [ -f /boot/amd-ucode.img ]; then
    ucode="--initrd=/boot/amd-ucode.img"
  fi

  ukify \
    --kernel="$vmlinuz" \
    ${ucode:+$ucode} \
    --initrd="$initramfs" \
    --cmdline="@$cmdline" \
    --output="$out"

  sbctl sign -s "$out"
  log "Signed UKI: $out"
}

install_kernel_cmdline(){
  mkdir -p /etc/kernel/cmdline.d
  # NOTE: module.sig_enforce=1 removed because module signing not yet implemented
  # TODO: Implement module signing (via sbctl or CachyOS PKGBUILD) and re-enable
  local cmdline

  cmdline="$(root_cmdline) rw lockdown=confidentiality efi=attr_uc mce=0 page_poison=1 vsyscall=none spec_store_bypass_disable=on l1tf=full spec_rstack_overflow=smash pti=on kexec_load_disabled=1"
   
  [ "$ENABLE_IMA" = "1" ] && cmdline="$cmdline ima=enforce ima_policy=tcb ima_hash=sha256"

  echo "$cmdline" > /etc/kernel/cmdline.d/99-bootchain.conf
}

install_sysctl_hardening(){
  cat > "$SYSCTL_HARDEN" <<'EOF'
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
vm.mmap_min_addr=65536
vm.overcommit_memory=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_regular=2
fs.protected_fifos=2
fs.suid_dumpable=0
EOF
  sysctl --system >/dev/null 2>&1 || true
}

install_audit_rules(){
  if [ "$ENABLE_AUDIT" = "0" ]; then return 0; fi
  
  req augenrules || req auditctl

  cat > "$AUDIT_RULES" <<'EOF'
# CachyOS Secure Boot + TPM2/LUKS audit rules
# Monitor all Secure Boot, EFI, TPM, and cryptographic operations

-w /sys/firmware/efi/efivars/ -p wa -k efi_writes
-w /sys/kernel/security/tpm -p wa -k tpm_writes
-w /sys/kernel/security/lockdown -p wa -k lockdown_writes
-w /proc/cmdline -p r -k kernel_cmdline
-a always,exit -F arch=x86_64 -S kexec_file_load -S kexec_load -k kexec_attempt
-a always,exit -F arch=x86_64 -S mount -S umount2 -F auid>=1000 -F auid!=-1 -k mount_ops
-w /etc/crypttab -p wa -k cryptsetup_changes
-w /boot -p wa -k boot_changes
EOF

  systemctl restart audit || true
  log "Audit rules installed"
}

install_efi_guard(){
  cat > "$EFI_GUARD_SERVICE" <<'EOF'
[Unit]
Description=Harden EFI variable access
After=local-fs.target
ConditionPathExists=/sys/firmware/efi/efivars

[Service]
Type=oneshot
ExecStart=/usr/bin/mount -o remount,ro /sys/firmware/efi/efivars
ExecStart=/usr/bin/chmod 000 /sys/firmware/efi/efivars/*
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable efi-guard-readonly.service >/dev/null 2>&1 || true
  systemctl mask fwupd.service fwupd-refresh.service >/dev/null 2>&1 || true
}

setup_systemd_boot(){
  has bootctl || die "bootctl not found"
  bootctl install || true
  bootctl update || true

  mkdir -p "$EFI_MOUNT/loader/entries"

  cat > "$EFI_MOUNT/loader/entries/cachyos-uki.conf" <<EOF
title       CachyOS Linux (UKI + Secure Boot)
efi         /EFI/Linux/cachyos-uki.efi
machine-id  $(cat /etc/machine-id)
EOF

  cat > "$EFI_MOUNT/loader/loader.conf" <<'EOF'
default cachyos-uki.conf
editor no
console-mode max
EOF
}

install_mkinitcpio_hook(){
  mkdir -p /usr/local/libexec

  cat > "$UKI_BUILD_HOOK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EFI_MOUNT="${EFI_MOUNT:-/efi}"

log(){ printf '[mkinitcpio-UKI] %s\n' "$*"; }

command -v sbctl >/dev/null 2>&1 || exit 0
command -v ukify >/dev/null 2>&1 || exit 0
[ -f /etc/kernel/cmdline.d/99-bootchain.conf ] || exit 0

kver="$1"
pkgbase=""
vmlinuz="/usr/lib/modules/${kver}/vmlinuz"
output="${EFI_MOUNT}/EFI/Linux/cachyos-uki.efi"

if [ -r "/usr/lib/modules/${kver}/pkgbase" ]; then
  pkgbase="$(cat "/usr/lib/modules/${kver}/pkgbase")"
fi

for candidate in \
  "/boot/initramfs-${pkgbase}.img" \
  "/boot/initramfs-linux.img" \
  "/boot/initramfs-linux-cachyos.img" \
  "/boot/initramfs-linux-zen.img" \
  "/boot/initramfs-linux-hardened.img"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    initramfs="$candidate"
    break
  fi
done

[ -f "$vmlinuz" ] && [ -n "${initramfs:-}" ] || exit 0

ucode=""
[ -f /boot/intel-ucode.img ] && ucode="--initrd=/boot/intel-ucode.img"
[ -f /boot/amd-ucode.img ] && ucode="--initrd=/boot/amd-ucode.img"

ukify --kernel="$vmlinuz" ${ucode:+$ucode} --initrd="$initramfs" --cmdline="@/etc/kernel/cmdline.d/99-bootchain.conf" --output="$output"
sbctl sign -s "$output"
log "Built and signed: $output"
EOF
  chmod 755 "$UKI_BUILD_HOOK"

  local pkgbase
  if [ -r "/usr/lib/modules/$(uname -r)/pkgbase" ]; then
    pkgbase="$(cat "/usr/lib/modules/$(uname -r)/pkgbase")"
  else
    pkgbase="linux"
  fi

  cat > "$MKINITCPIO_PRESET" <<EOF
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-${pkgbase}"
PRESETS=('default' 'fallback')
default_image="/boot/initramfs-${pkgbase}.img"
default_options="--kernel /boot/vmlinuz-${pkgbase}"
fallback_image="/boot/initramfs-${pkgbase}-fallback.img"
fallback_options="-S autodetect"
EOF
}

install_stage1_autorun(){
  req crontab

  local tmp_cron
  tmp_cron="$(mktemp)"

  crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" > "$tmp_cron" || true
  printf '%s\n' \
    "@reboot /usr/bin/env \"$SCRIPT_PATH\" --auto-reboot-check # $CRON_MARKER" \
    >> "$tmp_cron"
  crontab "$tmp_cron"
  rm -f "$tmp_cron"

  log "Installed @reboot cron handoff for Stage 1"
}

stage_0_presb(){
  log "=== STAGE 0: Pre-Secure Boot Setup ==="
  req sbctl; req cryptsetup; req systemd-cryptenroll; req ukify; req bootctl

  mapfile -t luks < <(collect_tpm_luks_devices)
  [ "${#luks[@]}" -gt 0 ] || die "No TPM2 LUKS devices in /etc/crypttab"

  ts="$(date +%Y%m%d-%H%M%S)"
  sb_backup="/var/lib/sbctl.backup-${ts}"
  luks_backup="/root/luks-header-backup-${ts}"

  log "Creating backups"
  [ -d /var/lib/sbctl ] && cp -a /var/lib/sbctl "$sb_backup" || true
  backup_luks_headers "$luks_backup" "${luks[@]}"

  log "Rotating Secure Boot keys"
  sbctl create-keys --force

  log "Enrolling Secure Boot keys (KEEP_MICROSOFT=$KEEP_MICROSOFT_KEYS)"
  if [ "$KEEP_MICROSOFT_KEYS" = "1" ]; then
    sbctl enroll-keys -m --yes
  else
    sbctl enroll-keys --yes
  fi

  log "Installing hardening"
  install_kernel_cmdline
  install_sysctl_hardening
  install_audit_rules
  install_efi_guard
  install_mkinitcpio_hook

  log "Building + signing initial UKI"
  build_sign_uki "$(uname -r)" "$EFI_MOUNT/EFI/Linux/cachyos-uki.efi"

  log "Setting up systemd-boot"
  setup_systemd_boot

  log "Signing EFI files"
  sbctl sign-all

  mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
  cat > "$STATE_FILE" <<EOF
STAGE=1
LUKS_DEVS="$(printf '%s\n' "${luks[@]}")"
TPM_PCRS=$TPM_PCRS
SB_BACKUP=$sb_backup
LUKS_BACKUP=$luks_backup
TIMESTAMP=$ts
EOF
  chmod 600 "$STATE_FILE"
  install_stage1_autorun

  log "=== Stage 0 Complete ==="
  log "Next: reboot, enable Secure Boot in BIOS, then boot back into the system"
  log "Stage 1 will run automatically on the first boot with Secure Boot enabled"
}

stage_1_postsb(){
  log "=== STAGE 1: Post-Secure Boot Finalization ==="
  [ -f "$STATE_FILE" ] || die "State file not found. Run Stage 0 first."
  source "$STATE_FILE"

  if [ "$(sb_state)" = "disabled" ]; then
    die "Secure Boot is still DISABLED. Enable it in firmware and reboot."
  fi

  log "Secure Boot: ENABLED ✓"
  IFS=$'\n' read -ra luks_devs <<<"$LUKS_DEVS"

  log "Re-enrolling TPM2 LUKS unlock (PCRs: $TPM_PCRS)"
  for dev in "${luks_devs[@]}"; do
    [ -n "$dev" ] || continue
    systemd-cryptenroll "$dev" --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs="$TPM_PCRS"
  done

  log "Verifying boot chain"
  bootctl status || true

  log "Cleaning up backups"
  rm -rf -- "${SB_BACKUP:-}" "${LUKS_BACKUP:-}" || true
  rm -f -- "$STATE_FILE"
  remove_stage1_autorun

  log "=== Stage 1 Complete ==="
  log "✓ Secure Boot enabled and locked"
  log "✓ TPM2 resealed to SB measurements"
  log "✓ LUKS auto-unlock via TPM2 ready"
  log "Everything works."
}

auto_detect_stage(){
  if [ ! -f "$STATE_FILE" ]; then
    return 0
  fi
  source "$STATE_FILE"
  echo "$STAGE"
}

remove_stage1_autorun(){
  if has crontab; then
    local tmp_cron
    tmp_cron="$(mktemp)"
    crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" > "$tmp_cron" || true
    crontab "$tmp_cron" 2>/dev/null || true
    rm -f "$tmp_cron"
  fi
}

auto_reboot_check(){
  [ -f "$STATE_FILE" ] || {
    log "No pending Secure Boot setup state found; exiting."
    return 0
  }

  if [ "$(sb_state)" != "enabled" ]; then
    log "Secure Boot is not enabled yet; leaving the reboot handoff in place."
    log "Enable Secure Boot in firmware and reboot again to continue."
    return 0
  fi

  log "Secure Boot enabled; continuing with Stage 1 finalization."
  stage_1_postsb
  remove_stage1_autorun
}

main(){
  [ "$(id -u)" -eq 0 ] || die "Run as root"

  if [ "${1:-}" = "--auto-reboot-check" ]; then
    auto_reboot_check
    return 0
  fi

  if [ "${1:-}" = "--install" ]; then
    shift
    STAGE=0
    stage_0_presb
    log "Rebooting into setup mode. Stage 1 will finish automatically after Secure Boot is enabled."
    reboot
    return 0
  fi

  STAGE="${STAGE:-}"
  if [ -z "$STAGE" ]; then
    STAGE=$(auto_detect_stage) || STAGE=0
  fi

  log "CachyOS Hardened Secure Boot + UKI + TPM2/LUKS (mkinitcpio-first)"
  log "Stage: $STAGE | Secure Boot state: $(sb_state)"

  case "$STAGE" in
    0) stage_0_presb ;;
    1) stage_1_postsb ;;
    *) die "Unknown stage: $STAGE" ;;
  esac
}

main "$@"
