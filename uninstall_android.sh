#!/bin/bash

# ==============================================================================
# Omniverse — Android Wipe & Uninstaller Utility
# ==============================================================================
# Detects connected Android hardware, provides a beautiful interactive menu,
# and performs either an in-place storage/cache wipe or a full package uninstallation.
# ==============================================================================

set -eo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}         OMNIVERSE — ANDROID STORAGE WIPE & UNINSTALLER${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

# 1. Pre-flight Checks
if ! command -v adb &> /dev/null; then
    echo -e "${RED}error:${NC} Android Debug Bridge ('adb') is not installed."
    echo -e "       Please install the Android SDK Platform Tools to proceed."
    exit 1
fi

# 2. Hardware Detection
echo -e "${BLUE}info:${NC} Scanning for connected Android devices..."
DEVICES=$(adb devices | grep -v "List" | grep "device" | cut -f1)

if [ -z "$DEVICES" ]; then
    echo -e "${RED}error:${NC} No connected Android devices detected."
    echo -e "       Please connect your phone, tablet, or Android TV via USB with USB Debugging enabled."
    exit 1
fi

# Use first detected device
DEVICE_ID=$(echo "$DEVICES" | head -n 1)
DEVICE_MODEL=$(adb -s "$DEVICE_ID" shell getprop ro.product.model | tr -d '\r')

echo -e "${GREEN}success:${NC} Detected connected target device:"
echo -e "         - Model: ${BOLD}${DEVICE_MODEL}${NC}"
echo -e "         - ID:    ${CYAN}${DEVICE_ID}${NC}"
echo -e ""

# 3. Interactive Operation Selector
echo -e "${BOLD}Select Wiping Operation:${NC}"
echo -e "  [1] ${CYAN}${BOLD}Reset App State (Wipe Storage & Cache)${NC}"
echo -e "      Keep the app installed but purge all databases, watch progress, preferences, and API credentials."
echo -e "  [2] ${RED}${BOLD}Complete Package Uninstallation${NC}"
echo -e "      Completely uninstall the app package and delete all local app data directories."
echo -e "  [3] ${YELLOW}Cancel Operations${NC}"
echo -e ""

read -p "Enter selection [1-3]: " selection

case "$selection" in
    1)
        echo -e "${BLUE}info:${NC} Purging storage and cache for com.finix.omniverse on ${DEVICE_MODEL}..."
        if adb -s "$DEVICE_ID" shell pm clear com.finix.omniverse &> /dev/null; then
            echo -e "${GREEN}${BOLD}======================================================================${NC}"
            echo -e "${GREEN}success:${NC} App storage and cache wiped successfully!"
            echo -e "         Omniverse has been reset to a 100% clean, first-time-install state."
            echo -e "${GREEN}${BOLD}======================================================================${NC}"
        else
            echo -e "${RED}error:${NC} Wiping failed. Is the app installed on your device?"
            exit 1
        fi
        ;;
    2)
        echo -e "${BLUE}info:${NC} Uninstalling com.finix.omniverse from ${DEVICE_MODEL}..."
        if adb -s "$DEVICE_ID" uninstall com.finix.omniverse &> /dev/null; then
            echo -e "${GREEN}${BOLD}======================================================================${NC}"
            echo -e "${GREEN}success:${NC} Omniverse has been completely uninstalled from ${DEVICE_MODEL}."
            echo -e "${GREEN}${BOLD}======================================================================${NC}"
        else
            echo -e "${RED}error:${NC} Uninstallation failed. Is the app installed on your device?"
            exit 1
        fi
        ;;
    3|*)
        echo -e "${YELLOW}info:${NC} Operations cancelled by user."
        exit 0
        ;;
esac
