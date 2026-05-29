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
