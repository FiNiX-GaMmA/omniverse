#!/bin/bash

# ==============================================================================
# Omnplay — Real Device Automated Deployer & Orchestrator
# ==============================================================================
# Detects connected iPads/iPhones, builds the native Swift project with
# provisioning, deploys the app, prompts for trusted verification, and launches.
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
echo -e "${CYAN}${BOLD}       OMNIPLAY — AUTOMATED IPAD & IOS REAL DEVICE DEPLOYER${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

# 1. Pre-flight Checks
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}error:${NC} iPad deployment requires macOS with Xcode installed."
    exit 1
fi

if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}error:${NC} Xcode Command Line Tools ('xcodebuild') are required."
    exit 1
fi

if ! command -v xcodegen &> /dev/null; then
    echo -e "${YELLOW}warning:${NC} XcodeGen not found. Using existing Xcode project files."
else
    echo -e "${BLUE}info:${NC} Generating up-to-date Xcode project files via XcodeGen..."
    (cd ios && xcodegen)
fi

# 2. Dynamic Hardware Detection
echo -e "${BLUE}info:${NC} Scanning for connected Apple hardware..."
DEVICE_NAME=$(xcrun devicectl list devices | grep -i "iPad" | head -n 1 | sed -E 's/ {2,}/|/g' | cut -d'|' -f1)
DEVICE_ID=$(xcrun devicectl list devices | grep -i "iPad" | grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" | head -n 1)

if [ -z "$DEVICE_ID" ]; then
    echo -e "${YELLOW}warning:${NC} No connected iPad detected. Scanning for other iOS hardware..."
    DEVICE_NAME=$(xcrun devicectl list devices | grep -E -v "Name|-------" | head -n 1 | sed -E 's/ {2,}/|/g' | cut -d'|' -f1)
    DEVICE_ID=$(xcrun devicectl list devices | grep -E -v "Name|-------" | grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" | head -n 1)
fi

if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}error:${NC} No connected iPad or iOS device found."
    echo -e "       Please connect your iPad via USB or ensure it is on the same Wi-Fi with Developer Mode enabled."
    exit 1
fi

echo -e "${GREEN}success:${NC} Detected connected target device:"
echo -e "         - Name:  ${BOLD}${DEVICE_NAME}${NC}"
echo -e "         - ID:    ${CYAN}${DEVICE_ID}${NC}"

# 3. Compiling the App for iOS/iPadOS Real Hardware
echo -e "${BLUE}info:${NC} Compiling and codesigning Swift app bundle for target device..."
(cd ios && xcodebuild -project Omniverse.xcodeproj \
                      -scheme Omniverse \
                      -configuration Debug \
                      -sdk iphoneos \
                      -allowProvisioningUpdates \
                      -derivedDataPath build_device \
                      build)

APP_PATH="ios/build_device/Build/Products/Debug-iphoneos/Omniverse.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}error:${NC} Compiled app bundle was not found at expected path: $APP_PATH"
    exit 1
fi

# 4. Installing the App Bundle
echo -e "${BLUE}info:${NC} Installing app bundle onto ${DEVICE_NAME}..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

# 5. Handle Untrusted Developer Verification ("Waittime" + Instructions)
echo -e ""
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
echo -e "${YELLOW}${BOLD}                 DEVELOPER PROFILE TRUST VERIFICATION                 ${NC}"
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
echo -e "${BOLD}To launch and run Omniverse on your iPad, you must verify the profile:${NC}"
echo -e ""
echo -e "  1. Open ${BOLD}Settings${NC} on your iPad (${DEVICE_NAME})."
echo -e "  2. Go to ${BOLD}General > VPN & Device Management${NC}."
echo -e "  3. Under ${BOLD}Developer App${NC}, tap your apple/developer ID email."
echo -e "  4. Tap ${BOLD}Trust \"[Your Developer Account]\"${NC} and confirm."
echo -e "  5. Ensure ${BOLD}Developer Mode${NC} is enabled under ${BOLD}Settings > Privacy & Security${NC} (if prompted)."
echo -e "${YELLOW}${BOLD}======================================================================${NC}"
echo -e ""

# Pause and wait for verification
read -p "Once you have trusted and verified the app on your iPad, press [ENTER] to launch the app: " temp

# 6. Launching the App
echo -e "${BLUE}info:${NC} Launching Omniverse on ${DEVICE_NAME}..."
xcrun devicectl device process launch --device "$DEVICE_ID" com.finix.omniverse

echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}success:${NC} Omniverse is now running on your ${DEVICE_NAME}!"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
