#!/bin/bash
set -euo pipefail

echo "=== Setting up Python 3.14-ready Async Dev Environment ==="
echo

# Check Python version
python3 --version
echo

# Install uv if not present
if ! command -v uv &> /dev/null; then
    echo "Installing uv (Python package manager)..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# Create venv with uv
echo "Creating venv with uv..."
cd /home/daen/Projects/sbh/python-dev
uv venv --python 3.14 2>/dev/null || uv venv 2>/dev/null
source venv/bin/activate

# Install dev dependencies (async, linting, type checking)
echo "Installing dependencies..."
uv pip install \
    ruff \
    pyright \
    pytest \
    pytest-asyncio \
    aiofiles \
    black \
    mypy

echo "✓ Setup complete"
