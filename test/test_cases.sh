#!/bin/bash
set -euo pipefail

echo "[INFO] Running generic test vector checks..."

# Example 1: Check if Python is installed
if command -v python3 >/dev/null 2>&1; then
  echo "[PASS] Python3 is available"
else
  echo "[FAIL] Python3 not found"
  exit 1
fi

# Example 2: Check if Docker is installed
if command -v docker >/dev/null 2>&1; then
  echo "[PASS] Docker is available"
else
  echo "[FAIL] Docker not found"
  exit 1
fi

# Example 3: Check if Jenkins service directory exists
if [ -d "/var/lib/jenkins" ]; then
  echo "[PASS] Jenkins directory exists"
else
  echo "[FAIL] Jenkins directory missing"
  exit 1
fi

echo "[INFO] Generic test vector checks completed successfully."
