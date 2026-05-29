# CachyOS SBH Python Package (cachyos-sbh-py) — Building & Installation

## Package Information

- **Name:** `cachyos-sbh-py`
- **Version:** 1.0.0
- **Architecture:** x86_64
- **License:** MIT
- **Description:** Python 3.14+ async utilities for Secure Boot + NVIDIA + TPM2 orchestration

## Prerequisites

```bash
# Install build tools
sudo pacman -S base-devel git

# For building the package
sudo pacman -S python python-setuptools python-build

# For linting/type-checking (optional)
sudo pacman -S python-aiofiles
```

## Building from Source

### Method 1: Using makepkg (Recommended)

```bash
cd /path/to/cachyos-sbh/python-dev

# Build the package
makepkg -si

# Or with all checks
makepkg -Cci
```

### Method 2: Manual Build

```bash
cd /path/to/cachyos-sbh/python-dev

# Install dependencies
python -m pip install --user setuptools build

# Build wheel
python -m build --wheel --no-isolation

# Install wheel
sudo pip install dist/cachyos_sbh_py-1.0.0-py3-none-any.whl
```

## Installation

### From Arch User Repository (AUR)

When available on AUR:

```bash
# Clone from AUR
git clone https://aur.archlinux.org/cachyos-sbh-py.git
cd cachyos-sbh-py

# Build and install
makepkg -si
```

### Post-Installation

The `.install` script runs automatically:

1. Prints install instructions
2. Shows command for importing modules
3. Lists optional dev dependencies

For manual setup:

```bash
# Optionally install dev tools
sudo pacman -S ruff pyright python-pytest python-pytest-asyncio
```

## Package Contents

After installation:

```
/usr/lib/python3.14/site-packages/cachyos_sbh/
├── __init__.py
├── tpm_async.py         — TPM2 async operations
├── nvidia_async.py      — NVIDIA driver async operations
└── cryptsetup_async.py  — LUKS async operations

/usr/share/doc/cachyos-sbh-py/
├── README.md            — Development guide
├── pyproject.toml       — Build configuration
└── setup.py             — Setup script

/usr/share/cachyos-sbh-py/tests/
└── test_async_modules.py — Test suite

/usr/share/licenses/cachyos-sbh-py/
└── LICENSE
```

## Usage

### Basic Import

```python
from cachyos_sbh import tpm_async, nvidia_async, cryptsetup_async
import asyncio

# Example: Seal TPM2 PCRs
result = await tpm_async.tpm_seal_pcrs([7, 11], b"value")

# Example: Get NVIDIA GPU info
info = await nvidia_async.nvidia_query_info(0)

# Example: Open LUKS device
success = await cryptsetup_async.cryptsetup_open(
    "/dev/nvme0n1p2", "crypt1", "passphrase"
)
```

### Full Example Script

```python
#!/usr/bin/env python3
"""Example: Async Secure Boot orchestration with TPM2 + LUKS."""

import asyncio
from cachyos_sbh import tpm_async, cryptsetup_async

async def main():
    # 1. Open LUKS devices
    devices = {
        "/dev/nvme0n1p2": "crypt1",
        "/dev/nvme0n1p3": "crypt2",
    }
    results = await cryptsetup_async.cryptsetup_open_all(
        devices, "my-passphrase"
    )
    print(f"LUKS devices opened: {results}")
    
    # 2. Seal TPM2 to current Secure Boot state
    sealed = await tpm_async.tpm_seal_pcrs(
        [7, 11],  # SecureBoot + UKI measurements
        b"secure-state-hash"
    )
    print(f"TPM2 sealed: {sealed}")

if __name__ == "__main__":
    asyncio.run(main())
```

## Development Workflow

### Set Up Dev Environment

```bash
cd /path/to/cachyos-sbh/python-dev
source .venv/bin/activate

# Reinstall in editable mode
pip install -e .[dev]
```

### Run Quality Checks

```bash
# Lint
ruff check cachyos_sbh tests

# Type check (JSON output)
pyright cachyos_sbh tests --outputjson > report.json

# Test
export PYTHONPATH="$(pwd):$PYTHONPATH"
pytest tests/ -v
```

### Make Changes

1. Edit module files in `cachyos_sbh/`
2. Add tests to `tests/test_async_modules.py`
3. Run quality checks
4. Rebuild package: `makepkg -si`

## Troubleshooting

### Import Error: No module named 'cachyos_sbh'

Install the package:

```bash
# Via makepkg
cd /path/to/cachyos-sbh/python-dev
makepkg -si

# Or via pip (editable)
pip install -e /path/to/cachyos-sbh/python-dev
```

### Tests Fail to Import

```bash
# Add to PYTHONPATH
export PYTHONPATH="/path/to/cachyos-sbh/python-dev:$PYTHONPATH"

# Or run from project directory
cd /path/to/cachyos-sbh/python-dev
pytest tests/ -v
```

### Ruff/Pyright Not Found

Install dev tools:

```bash
sudo pacman -S ruff pyright
```

### Python 3.14 Not Available

The package is tested with Python 3.14. For older versions:

```bash
# Build with Python 3.11+
python3.11 -m build --wheel --no-isolation
```

## PKGBUILD Sections

### prepare()
Copies source files to build directory

### build()
Runs `python -m build` to create wheel

### package()
Installs wheel files and documentation

### check()
Runs pytest on the test suite

## PKGBUILD Variables

```bash
pkgname=cachyos-sbh-py              # Package name in AUR
pkgver=1.0.0                        # Version
pkgrel=1                            # Release number
arch=('x86_64')                     # Supported architectures
depends=('python>=3.14'...)         # Runtime dependencies
optdepends=(...)                    # Optional dev tools
makedepends=('python-setuptools'...) # Build dependencies
install=${pkgname}.install          # Post-install script
```

## Release Checklist

Before bumping version:

- [ ] All tests pass: `pytest tests/ -v`
- [ ] Linting clean: `ruff check cachyos_sbh tests`
- [ ] Type checking clean: `pyright cachyos_sbh tests`
- [ ] Documentation updated: `README.md`, inline docstrings
- [ ] Version updated: `pyproject.toml`, `setup.py`
- [ ] `pkgrel` incremented in `PKGBUILD`

## Contributing

1. Fork repository
2. Create feature branch
3. Make changes + tests
4. Run quality checks
5. Submit pull request

## License

MIT License — See `/usr/share/licenses/cachyos-sbh-py/LICENSE`

## Useful Links

- **CachyOS:** https://cachyos.org
- **Python Packaging:** https://packaging.python.org
- **Arch Packaging:** https://wiki.archlinux.org/title/Creating_packages
- **AUR Guidelines:** https://wiki.archlinux.org/title/Arch_User_Repository#Submitting_packages
