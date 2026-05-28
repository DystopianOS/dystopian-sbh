#!/usr/bin/env bash
# Setup MOK (Machine Owner Key) for NVIDIA 580 Secure Boot
# Run with: sudo /home/daen/Projects/sbh/bin/setup-mok-keys.sh

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must run as root (sudo)"
  exit 1
fi

echo "=== Setting up MOK keys for NVIDIA 580 Secure Boot ==="

# Generate MOK keys
KEYDIR="/tmp/mok-gen-$$"
mkdir -p "$KEYDIR"
trap 'rm -rf "$KEYDIR"' EXIT

echo "Generating RSA 2048-bit key and certificate..."
openssl req -new -x509 -newkey rsa:2048 \
  -keyout "$KEYDIR/MOK.key" \
  -out "$KEYDIR/MOK.crt" \
  -days 3650 -nodes \
  -subj "/CN=CachyOS NVIDIA Pascal"

echo "Converting to DER format..."
openssl x509 -in "$KEYDIR/MOK.crt" -outform DER -out "$KEYDIR/MOK.der"

# Install to /root/
echo "Installing keys to /root/..."
install -m 400 "$KEYDIR/MOK.key" /root/MOK.key
install -m 400 "$KEYDIR/MOK.der" /root/MOK.der
install -m 444 "$KEYDIR/MOK.crt" /root/MOK.crt

echo "✓ MOK keys installed:"
ls -lh /root/MOK.*

echo ""
echo "Certificate details:"
openssl x509 -in /root/MOK.crt -noout -subject

echo ""
echo "✓ MOK setup complete"
echo "Next step: Enroll MOK in Secure Boot"
echo "  sudo mokutil --import /root/MOK.der"
