# Maintainer: Dystopian <dcxdevelopment at protonmail dot com>
# Co-Maintainer: DCx7C5 <dcxdevelopment at protonmail dot com>
# Project: Dystopian Secure Boot + NVIDIA + TPM2 Helper

pkgname=dystopian-sbh
pkgver=1.0.0
pkgrel=1
pkgdesc="Dystopian Secure Boot + NVIDIA + TPM2 Orchestration Tools"
arch=('x86_64')
license=('MIT')
url="https://github.com/DystopianOS/${pkgname}"
groups=('dystopian')
source=("git+https://github.com/DystopianOS/dystopian-sbh#branch=main")
makedepends=('git')
depends=('bash' 'efibootmgr' 'grub' 'systemd')
optdepends=(
  'cryptsetup: For LUKS support'
  'tpm2-tools: For TPM2 operations'
  'intel-ucode: For Intel CPU microcode'
  'amd-ucode: For AMD CPU microcode'
)
provides=('dystopian-sbh')
conflicts=('dystopian-sbh')

sha512sums=('SKIP')
b2sums=('SKIP')

validpgpkeys=(
  '14A71FEDA1F764F7075FFA40FF64D67D0F00DD12'
  'C71C37EA17233736b9fad43efad24da0784d363a'
)

package() {
  cd "$srcdir/$pkgname"

  local libdir="$pkgdir/usr/lib/dystopian-sbh"
  local bindir="$pkgdir/usr/bin"

  install -d "$libdir" "$bindir"

  # Install all runtime scripts into a shared helper directory.
  for script in \
    bin/dystopian-sbh.sh \
    bin/build-from-scratch.sh \
    bin/generate-cachyos-env.sh \
    bin/hw-detect-optimize.sh \
    bin/secureboot-uki-tpm.sh \
    bin/strip-kernel-debug.sh \
    bin/setup-complete-uki.sh \
    bin/setup-uki-hook.sh \
    bin/setup-dkms-signing.sh \
    bin/setup-mok-keys.sh \
    bin/enroll-mok.sh \
    bin/verify-uki-setup.sh \
    bin/verify-shell-scripts.sh \
    bin/repair-kernel-toolchain-sonames.sh
  do
    install -Dm755 "$script" "$libdir/$(basename "$script")"
  done

  install -Dm644 hooks/98-dystopian-kernel-toolchain-sonames.hook \
    "$pkgdir/usr/share/libalpm/hooks/98-dystopian-kernel-toolchain-sonames.hook"

  # Expose user-facing launchers in /usr/bin.
  make_launcher() {
    local name="$1"
    local target="$2"

    cat > "$bindir/$name" <<EOF
#!/bin/sh
exec /usr/lib/dystopian-sbh/$target "\$@"
EOF
    chmod 755 "$bindir/$name"
  }

  make_launcher dystopian-sbh dystopian-sbh.sh
  make_launcher dystopian-sbh-build build-from-scratch.sh
  make_launcher dystopian-sbh-gen-env generate-cachyos-env.sh
  make_launcher dystopian-sbh-hw-detect hw-detect-optimize.sh
  make_launcher dystopian-sbh-secureboot-uki secureboot-uki-tpm.sh
  make_launcher dystopian-sbh-strip-debug strip-kernel-debug.sh

  # Install kernel configs
  install -Dm644 config/config.native-minimal "$pkgdir/usr/share/dystopian-sbh/config/config.native-minimal"
  install -Dm644 config/config.x86-64-v2 "$pkgdir/usr/share/dystopian-sbh/config/config.x86-64-v2"
  install -Dm644 config/PKGBUILD-linux-cachyos "$pkgdir/usr/share/dystopian-sbh/PKGBUILD/PKGBUILD-linux-cachyos"
  install -Dm644 config/PKGBUILD-linux-cachyos-hardened "$pkgdir/usr/share/dystopian-sbh/PKGBUILD/PKGBUILD-linux-cachyos-hardened"
  install -Dm644 config/PKGBUILD-linux-cachyos-native "$pkgdir/usr/share/dystopian-sbh/PKGBUILD/PKGBUILD-linux-cachyos-native"
  install -Dm644 config/PKGBUILD-linux-cachyos-optimized "$pkgdir/usr/share/dystopian-sbh/PKGBUILD/PKGBUILD-linux-cachyos-optimized"

  # Install CachyOS environment scripts
  mkdir -p "$pkgdir/usr/share/dystopian-sbh/cachyos-env"
  cp -r config/cachyos-env/* "$pkgdir/usr/share/dystopian-sbh/cachyos-env/" 2>/dev/null || true

  # Install documentation
  install -Dm644 README.md "$pkgdir/usr/share/doc/${pkgname}/README.md"
  install -Dm644 INSTALL.md "$pkgdir/usr/share/doc/${pkgname}/INSTALL.md"
  install -Dm644 LOCALIZED-NATIVE-BUILD.md "$pkgdir/usr/share/doc/${pkgname}/LOCALIZED-NATIVE-BUILD.md"
  install -Dm644 RESUMÉ.md "$pkgdir/usr/share/doc/${pkgname}/RESUME.md"
  install -Dm644 BUILD-VARIANTS-FINAL.md "$pkgdir/usr/share/doc/${pkgname}/BUILD-VARIANTS.md"

  # Install doc assets
  mkdir -p "$pkgdir/usr/share/doc/${pkgname}/doc"
  cp -r doc/* "$pkgdir/usr/share/doc/${pkgname}/doc/" 2>/dev/null || true
}

# vim:set ts=8 sts=2 sw=2 et:
