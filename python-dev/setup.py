"""Setup configuration for cachyos-sbh-py package."""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as f:
    long_description = f.read()

setup(
    name="cachyos-sbh-py",
    version="1.0.0",
    description="Python 3.14+ async utilities for Secure Boot + NVIDIA + TPM2",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="CachyOS SBH Project",
    url="https://github.com/cachyos/cachyos-sbh",
    license="MIT",
    packages=find_packages(include=["cachyos_sbh*"]),
    python_requires=">=3.14",
    install_requires=[
        "aiofiles>=25.1.0",
    ],
    extras_require={
        "dev": [
            "ruff>=0.15.0",
            "pyright>=1.1.0",
            "pytest>=9.0.0",
            "pytest-asyncio>=1.4.0",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.14",
        "Programming Language :: Python :: 3 :: Only",
        "Operating System :: POSIX :: Linux",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    keywords="secure-boot tpm2 luks nvidia-gpu cryptsetup async python",
    project_urls={
        "Documentation": "https://github.com/cachyos/cachyos-sbh/tree/main/python-dev",
        "Source": "https://github.com/cachyos/cachyos-sbh",
        "Tracker": "https://github.com/cachyos/cachyos-sbh/issues",
    },
)
