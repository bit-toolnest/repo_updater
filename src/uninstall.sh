#!/bin/bash
set -e

echo "=== Dummy Uninstaller Script ==="
echo "This script should remove all components installed by install.sh."

# Example steps (replace with real commands):
# 1. Stop services
#    sudo systemctl stop tool.service
#    sudo systemctl disable tool.service

# 2. Remove system packages
#    sudo apt remove --purge -y <package>

# 3. Clean environment variables
#    sudo sed -i '/TOOL_HOME=/d' /etc/environment

# 4. Delete files and directories
#    sudo rm -rf /opt/tool

echo "✅ Uninstallation complete (dummy run)"
