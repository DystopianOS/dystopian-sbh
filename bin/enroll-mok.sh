#!/bin/bash
# Enroll MOK key in Secure Boot (one-time setup)
# Run with: sudo /home/daen/Projects/sbh/bin/enroll-mok.sh

set -e

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must run as root (sudo)"
  exit 1
fi

echo "=== Enrolling MOK key in Secure Boot ==="

# Check if MOK.der exists
if [ ! -f /root/MOK.der ]; then
  echo "ERROR: MOK.der not found in /root/"
  echo "Run: sudo /home/daen/Projects/sbh/bin/setup-mok-keys.sh"
  exit 1
fi

# Enroll the key
echo "Importing MOK key..."
mokutil --import /root/MOK.der

echo ""
echo "✓ MOK key import request created"
echo ""
echo "IMPORTANT: You will see a blue shim screen on next reboot"
echo "1. Follow prompts to complete MOK enrollment"
echo "2. Set a password for MOK management (remember it!)"
echo "3. Reboot when prompted"
echo ""
echo "After reboot, verify enrollment:"
echo "  mokutil --list-enrolled | grep 'CachyOS'"
