#!/bin/bash
set -euo pipefail

# --- Config ---
IMAGE_NAME="installer-sandbox"
CONTAINER_NAME="installer-test-${BUILD_NUMBER}-$(date +%s)"
TIMEOUT="${EXECUTION_TIMEOUT:-1800}"   # default 30 minutes, override with EXECUTION_TIMEOUT

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"   # test/ folder
SRC_DIR="$SCRIPT_DIR/../src"

if [ ! -d "$SRC_DIR" ]; then
  echo "[FAIL] src/ directory not found at $SRC_DIR"
  exit 1
fi

echo "[INFO] Building sandbox image..."
docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile.test" "$SCRIPT_DIR/.."

# --- Run container ---
echo "[INFO] Cleaning up any stale container..."
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "[INFO] Starting sandbox container..."
docker run --rm --name "$CONTAINER_NAME" -d "$IMAGE_NAME" tail -f /dev/null

# --- Results tracking ---
RESULT_INSTALL="PASS"
RESULT_TESTCASE="SKIPPED"
RESULT_UNINSTALL="PASS"
LOG_INSTALL="$SCRIPT_DIR/install.log"
LOG_TESTCASE="$SCRIPT_DIR/testvector.log"
LOG_UNINSTALL="$SCRIPT_DIR/uninstall.log"

# --- Execute install.sh ---
echo "[INFO] Running src/install.sh inside container (timeout=$TIMEOUT seconds)..."
if ! docker exec "$CONTAINER_NAME" timeout "$TIMEOUT" bash /root/src/install.sh; then
  RESULT_INSTALL="FAIL"
  docker logs "$CONTAINER_NAME" > "$LOG_INSTALL"
  echo "[INFO] Logs saved to $LOG_INSTALL"
fi

# --- Execute test_cases.sh ---
if docker exec "$CONTAINER_NAME" test -f /root/test/test_cases.sh; then
  echo "[INFO] Running test_cases.sh inside container..."
  if ! docker exec "$CONTAINER_NAME" timeout "$TIMEOUT" bash /root/test/test_cases.sh; then
    RESULT_TESTCASE="FAIL"
    docker logs "$CONTAINER_NAME" > "$LOG_TESTCASE"
    echo "[INFO] Logs saved to $LOG_TESTCASE"
  else
    RESULT_TESTCASE="PASS"
  fi
else
  echo "[INFO] No test_cases.sh found, skipping custom checks."
  RESULT_TESTCASE="SKIPPED"
fi


# --- Execute uninstall.sh ---
echo "[INFO] Running src/uninstall.sh inside container (timeout=$TIMEOUT seconds)..."
if ! docker exec "$CONTAINER_NAME" timeout "$TIMEOUT" bash /root/src/uninstall.sh; then
  RESULT_UNINSTALL="FAIL"
  docker logs "$CONTAINER_NAME" > "$LOG_UNINSTALL"
  echo "[INFO] Logs saved to $LOG_UNINSTALL"
fi

# --- Cleanup ---
echo "[INFO] Stopping and removing container..."
docker rm -f "$CONTAINER_NAME"
rm "$SCRIPT_DIR/Dockerfile.test"

# --- Summary Report ---
echo
echo "=== Summary Report ==="
printf "%-15s %-10s %-30s\n" "Step" "Result" "Log File"
printf "%-15s %-10s %-30s\n" "install.sh" "$RESULT_INSTALL" "$LOG_INSTALL"
printf "%-15s %-10s %-30s\n" "testvector.sh" "$RESULT_TESTCASE" "$LOG_TESTCASE"
printf "%-15s %-10s %-30s\n" "uninstall.sh" "$RESULT_UNINSTALL" "$LOG_UNINSTALL"
echo "======================"
echo "[DONE] Test completed in isolated Docker sandbox."
