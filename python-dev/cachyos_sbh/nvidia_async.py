"""Async NVIDIA driver operations."""

import asyncio


async def nvidia_query_info(gpu_id: int = 0) -> dict[str, str]:
    """
    Asynchronously query NVIDIA GPU information.

    Args:
        gpu_id: GPU device ID (0-based)

    Returns:
        Dictionary with GPU info (model, driver version, CUDA version, etc.)

    Raises:
        RuntimeError: If nvidia-smi is not available
    """
    try:
        result = await asyncio.create_subprocess_exec(
            "nvidia-smi",
            "-i",
            str(gpu_id),
            "--query-gpu=index,name,driver_version,compute_cap",
            "--format=csv,noheader",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        stdout, stderr = await asyncio.wait_for(result.communicate(), timeout=5)

        if result.returncode != 0:
            raise RuntimeError(f"nvidia-smi failed: {stderr.decode()}")

        output = stdout.decode().strip()
        fields = output.split(", ")
        return {
            "gpu_id": fields[0],
            "name": fields[1],
            "driver_version": fields[2],
            "compute_cap": fields[3],
        }
    except TimeoutError as e:
        raise RuntimeError("nvidia-smi query timed out") from e
    except FileNotFoundError as e:
        raise RuntimeError("nvidia-smi not found") from e


async def nvidia_set_persistence(enabled: bool = True) -> bool:
    """
    Asynchronously enable/disable NVIDIA persistence mode.

    Args:
        enabled: True to enable persistence, False to disable

    Returns:
        True if successful, False otherwise
    """
    mode = "1" if enabled else "0"
    try:
        result = await asyncio.create_subprocess_exec(
            "nvidia-smi",
            "-pm",
            mode,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        _, stderr = await asyncio.wait_for(result.communicate(), timeout=5)

        if result.returncode != 0:
            print(f"Failed to set persistence: {stderr.decode()}")
            return False

        return True
    except (TimeoutError, FileNotFoundError) as e:
        print(f"Error setting persistence: {e}")
        return False


async def nvidia_validate_driver() -> bool:
    """
    Asynchronously validate NVIDIA driver is properly installed.

    Returns:
        True if driver is valid, False otherwise
    """
    try:
        info = await nvidia_query_info()
        return all(k in info for k in ["gpu_id", "driver_version"])
    except RuntimeError:
        return False


async def main() -> None:
    """Example usage of async NVIDIA operations."""
    if await nvidia_validate_driver():
        info = await nvidia_query_info()
        print(f"NVIDIA GPU info: {info}")

        persistence_set = await nvidia_set_persistence(enabled=True)
        print(f"Persistence mode set: {persistence_set}")
    else:
        print("NVIDIA driver not available")


if __name__ == "__main__":
    asyncio.run(main())
