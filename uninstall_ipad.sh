#!/bin/bash

# ==============================================================================
# Omniverse — iPadOS & iOS Automated App Uninstaller
# ==============================================================================
# Scans for connected iPads/iPhones, and utilizes Apple's official devicectl
# toolchain to completely uninstall the app and purge all sandboxed data.
# ==============================================================================

set -eo pipefail

# Force the developer directory to the full Xcode application bundle
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}       OMNIVERSE — IPADOS & IOS REAL DEVICE UNINSTALLER${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

# 1. Pre-flight Checks
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}error:${NC} iOS app uninstallation requires macOS with Xcode installed."
    exit 1
fi

if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}error:${NC} Xcode Command Line Tools ('xcodebuild') are required."
    exit 1
fi

# 2. Dynamic Hardware Detection
echo -e "${BLUE}info:${NC} Scanning for connected iOS hardware..."
DEVICE_NAME=$(xcrun devicectl list devices | grep -i "iPad" | head -n 1 | sed -E 's/ {2,}/|/g' | cut -d'|' -f1)
DEVICE_ID=$(xcrun devicectl list devices | grep -i "iPad" | grep_match=$(grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" | head -n 1)) || true

# Fallback: scan for any other iOS devices
if [ -z "$DEVICE_ID" ]; then
    DEVICE_NAME=$(xcrun devicectl list devices | grep -E -v "Name|-------" | head -n 1 | sed -E 's/ {2,}/|/g' | cut -d'|' -f1)
    DEVICE_ID=$(xcrun devicectl list devices | grep -E -v "Name|-------" | grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" | head -n 1)
fi

if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}error:${NC} No connected iPad or iOS device found."
    echo -e "       Please connect your iOS device via USB or ensure it is on the same Wi-Fi with Developer Mode enabled."
    exit 1
fi

echo -e "${GREEN}success:${NC} Detected connected target device:"
echo -e "         - Name:  ${BOLD}${DEVICE_NAME}${NC}"
echo -e "         - ID:    ${CYAN}${DEVICE_ID}${NC}"
echo -e ""

# 3. Interactive Uninstallation Selector
echo -e "${BOLD}Select Wiping Operation:${NC}"
echo -e "  [1] ${RED}${BOLD}Complete Package Uninstallation${NC}"
echo -e "      Completely uninstall the app package from ${DEVICE_NAME}. iOS will automatically purge all sandboxed data, settings, and keychain caches."
echo -e "  [2] ${YELLOW}Cancel Operations${NC}"
echo -e ""

read -p "Enter selection [1-2]: " selection

case "$selection" in
    1)
        echo -e "${BLUE}info:${NC} Uninstalling com.finix.omniverse from ${DEVICE_NAME}..."
        if xcrun devicectl device uninstall app --device "$DEVICE_ID" com.finix.omniverse &> /dev/null; then
            echo -e "${GREEN}${BOLD}======================================================================${NC}"
            echo -e "${GREEN}success:${NC} Omniverse has been completely uninstalled from ${DEVICE_NAME}."
            echo -e "         All sandboxed cache, databases, and keychains are cleared!"
            echo -e "${GREEN}${BOLD}======================================================================${NC}"
        else
            echo -e "${RED}error:${NC} Uninstallation failed. Is the app installed on your device?"
            exit 1
        fi
        ;;
    2|*)
        echo -e "${YELLOW}info:${NC} Operations cancelled by user."
        exit 0
        ;;
esac
