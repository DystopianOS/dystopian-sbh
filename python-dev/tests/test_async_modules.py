"""Async tests for CachyOS SBH Python modules."""

import pytest

from cachyos_sbh.cryptsetup_async import cryptsetup_open, cryptsetup_status
from cachyos_sbh.nvidia_async import nvidia_validate_driver
from cachyos_sbh.tpm_async import tpm_seal_pcrs


@pytest.mark.asyncio
async def test_tpm_seal_pcrs_valid() -> None:
    """Test TPM2 PCR sealing with valid indices."""
    result = await tpm_seal_pcrs([7, 11], b"test_value")
    assert result is True


@pytest.mark.asyncio
async def test_tpm_seal_pcrs_invalid_index() -> None:
    """Test TPM2 PCR sealing with invalid PCR index."""
    with pytest.raises(ValueError, match="PCR indices must be 0-23"):
        await tpm_seal_pcrs([25, 30], b"test_value")


@pytest.mark.asyncio
async def test_cryptsetup_open_valid_device() -> None:
    """Test LUKS device opening with valid path."""
    result = await cryptsetup_open("/dev/nvme0n1p2", "crypt1", "passphrase")
    assert result is True


@pytest.mark.asyncio
async def test_cryptsetup_open_invalid_device() -> None:
    """Test LUKS device opening with invalid path."""
    with pytest.raises(ValueError, match="Invalid device path"):
        await cryptsetup_open("nvme0n1p2", "crypt1", "passphrase")


@pytest.mark.asyncio
async def test_cryptsetup_status() -> None:
    """Test LUKS device status query."""
    status = await cryptsetup_status("crypt1")
    assert status["is_open"] == "true"
    assert "cipher" in status
    assert "key_size" in status


@pytest.mark.asyncio
async def test_nvidia_validate_driver() -> None:
    """Test NVIDIA driver validation (may fail if no GPU)."""
    # This test will pass/fail depending on hardware
    result = await nvidia_validate_driver()
    assert isinstance(result, bool)
