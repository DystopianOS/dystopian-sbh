# CachyOS SBH Python Development Environment

Python 3.14-ready async utilities for Secure Boot + NVIDIA + TPM2 orchestration.

## Setup

```bash
cd python-dev
source .venv/bin/activate
```

## Tools & Versions

- **Python:** 3.14.0
- **Ruff:** 0.15.15 (linting)
- **Pyright:** 1.1.409 (type checking, strict mode)
- **Pytest:** 9.0.3 (async testing)
- **Package Manager:** uv (no pip)

## Quality Checks

```bash
# Lint with ruff
ruff check src tests

# Type check with pyright (JSON output)
pyright src tests --outputjson > pyright-report.json

# Run async tests
export PYTHONPATH="$(pwd):$PYTHONPATH"
pytest tests/ -v
```

## Modules

### `src/tpm_async.py`
Asynchronous TPM2 operations for Secure Boot orchestration.

**Functions:**
- `tpm_seal_pcrs(pcrs: list[int], value: bytes) -> bool` — Seal TPM2 PCRs
- `tpm_unseal_luks(device_path: str) -> str | None` — Unseal LUKS passphrase from TPM2

### `src/nvidia_async.py`
Asynchronous NVIDIA driver operations.

**Functions:**
- `nvidia_query_info(gpu_id: int = 0) -> dict[str, str]` — Query GPU info
- `nvidia_set_persistence(enabled: bool = True) -> bool` — Enable/disable persistence mode
- `nvidia_validate_driver() -> bool` — Validate NVIDIA driver installation

### `src/cryptsetup_async.py`
Asynchronous cryptsetup/LUKS operations.

**Functions:**
- `cryptsetup_open(device: str, mapper_name: str, passphrase: str) -> bool` — Open LUKS device
- `cryptsetup_close(mapper_name: str) -> bool` — Close LUKS device
- `cryptsetup_status(mapper_name: str) -> dict[str, str]` — Query device status
- `cryptsetup_open_all(devices: dict[str, str], passphrase: str) -> dict[str, bool]` — Open multiple devices in parallel

## Type Checking Strictness

All modules use **strict mode** with:
- ✓ Type annotations required for all parameters and returns
- ✓ Union types use modern `X | None` syntax
- ✓ Async context managers with `asyncio.timeout()`
- ✓ No implicit `Any` types
- ✓ Full error tracking via try/except

## Testing

All async tests use pytest-asyncio with automatic detection:

```bash
pytest tests/ -v
```

Expected: **6 passed** ✓

## Configuration Files

- **`pyproject.toml`** — Ruff, Pyright, and Pytest configuration
- **`.venv/`** — Virtual environment (Python 3.14)

## Python 3.14 Features Used

- Union type syntax: `X | None` (PEP 604)
- Type hints: `dict[str, str]`, `list[int]` (PEP 585)
- Async context managers: `async with asyncio.timeout(...)`
- Match statements (backcompat: not used in this version)

## Next Steps

- Integrate with shell orchestration scripts
- Add CI/CD linting (GitHub Actions)
- Add performance benchmarks
- Add integration tests with real TPM2/LUKS

