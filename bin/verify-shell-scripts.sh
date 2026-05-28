#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS=(
  "bin/build-from-scratch.sh"
  "bin/enroll-mok.sh"
  "bin/generate-cachyos-env.sh"
  "bin/hw-detect-optimize.sh"
  "bin/secureboot-uki-tpm.sh"
  "bin/setup-complete-uki.sh"
  "bin/setup-dkms-signing.sh"
  "bin/setup-mok-keys.sh"
  "bin/setup-uki-hook.sh"
  "bin/verify-shell-scripts.sh"
  "bin/strip-kernel-debug.sh"
  "bin/verify-uki-setup.sh"
)

fail() {
  printf '[✗] %s\n' "$*" >&2
  exit 1
}

printf '[*] Shell script smoke check\n'

for script in "${SCRIPTS[@]}"; do
  path="${ROOT_DIR}/${script}"
  [ -f "$path" ] || fail "Missing script: $script"
  bash -n "$path"
done

grep -q 'root_cmdline()' "$ROOT_DIR/bin/secureboot-uki-tpm.sh" \
  || fail "secureboot-uki-tpm.sh lost its root cmdline helper"

grep -q 'cmdline.d/99-bootchain.conf' "$ROOT_DIR/bin/secureboot-uki-tpm.sh" \
  || fail "secureboot-uki-tpm.sh no longer writes the bootchain cmdline file"

if grep -qF 'blkid -s PARTUUID -o value /dev/disk/by-path/pci-*-part*' "$ROOT_DIR/bin/setup-uki-hook.sh"; then
  fail "setup-uki-hook.sh still uses the broken wildcard PARTUUID lookup"
fi

printf '[✓] Shell script smoke check passed\n'
