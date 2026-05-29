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

runtime_linking_error_for() {
  local binary="$1"
  local output

  if output="$("$binary" --help 2>&1 >/dev/null)"; then
    return 1
  fi

  if grep -Eq 'error while loading shared libraries|version `[^`]+` not found' <<<"$output"; then
    return 0
  fi

  return 1
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

rebuild_objtool_binary() {
  local binary="$1"
  local tool_dir

  if [[ "$(basename "$binary")" != "objtool" ]]; then
    return 1
  fi

  tool_dir="$(dirname "$binary")"
  if [[ ! -f "$tool_dir/Makefile" ]]; then
    warn "Cannot rebuild $binary (missing $tool_dir/Makefile)"
    return 1
  fi

  log "Rebuilding stale $binary"
  if make -C "$tool_dir" objtool >/dev/null; then
    log "Rebuilt $binary successfully"
    return 0
  fi

  warn "Failed to rebuild $binary"
  return 1
}

verify_tools() {
  local binary missing
  local unresolved=0
  local runtime_repaired=0

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

  if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
  fi

  while IFS= read -r binary; do
    [[ -n "$binary" ]] || continue
    if runtime_linking_error_for "$binary"; then
      unresolved=1
      if rebuild_objtool_binary "$binary"; then
        runtime_repaired=1
      fi
    fi
  done < <(discover_kernel_tools)

  if [[ $runtime_repaired -eq 1 ]] && command -v ldconfig >/dev/null 2>&1; then
    ldconfig
  fi

  if [[ $unresolved -eq 0 ]]; then
    log "No missing kernel tool SONAMEs detected"
  else
    log "Kernel tool dependency repair attempted; run script again to verify clean state"
  fi
}

main() {
  require_root

  if ! command -v ldd >/dev/null 2>&1; then
    die "ldd not found"
  fi

  verify_tools
}

main "$@"
