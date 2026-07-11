#!/bin/bash

# ==============================================================================
# Omniverse — Native macOS (Mac Catalyst) Builder & Installer
# ==============================================================================
# Builds the SAME SwiftUI codebase as the iOS/iPadOS app as a native macOS app
# via Mac Catalyst, packages a drag-to-Applications .dmg, and installs it.
# Look, feel, and features are identical to the iPad app because it IS the iPad
# app, recompiled for macOS.
# ==============================================================================

set -eo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}       OMNIVERSE — NATIVE macOS (MAC CATALYST) INSTALLER${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}error:${NC} macOS build requires macOS with Xcode installed."
    exit 1
fi
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}error:${NC} Xcode ('xcodebuild') is required."
    exit 1
fi

# Keep the Xcode project in sync with project.yml (Catalyst is enabled there).
if command -v xcodegen &> /dev/null; then
    echo -e "${BLUE}info:${NC} Regenerating Xcode project via XcodeGen..."
    (cd ios && xcodegen)
else
    echo -e "${YELLOW}warning:${NC} XcodeGen not found. Using existing project (Catalyst must already be enabled)."
fi

BUNDLE_ID="com.finix.omniverse"
BUILD_DIR="ios/build_mac"
DIST_DIR="dist_desktop"
APP_PATH="${BUILD_DIR}/Build/Products/Release-maccatalyst/Omniverse.app"

echo -e "${BLUE}info:${NC} Compiling native macOS app (Mac Catalyst, Release)..."
echo -e "         - Using pre-configured Xcode GUI signing (Personal Team)"
echo -e "         - Bundle ID: ${CYAN}${BUNDLE_ID}${NC}"

if ! (cd ios && xcodebuild -project Omniverse.xcodeproj \
                          -scheme Omniverse \
                          -configuration Release \
                          -destination 'platform=macOS,variant=Mac Catalyst' \
                          -derivedDataPath build_mac \
                          build); then
    echo -e ""
    echo -e "${RED}${BOLD}======================================================================${NC}"
    echo -e "${RED}${BOLD}                       XCODEBUILD COMPILATION FAILED                  ${NC}"
    echo -e "${RED}${BOLD}======================================================================${NC}"
    echo -e "If this is a signing error, open ${BOLD}ios/Omniverse.xcodeproj${NC} in Xcode,"
    echo -e "go to ${BOLD}Signing & Capabilities${NC}, pick your Personal Team, then re-run."
    echo -e "${RED}${BOLD}======================================================================${NC}"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}error:${NC} Built app not found at: $APP_PATH"
    exit 1
fi

echo -e "${GREEN}success:${NC} Native macOS app built."

# Package a drag-to-Applications .dmg
echo -e "${BLUE}info:${NC} Packaging .dmg installer..."
rm -rf "$DIST_DIR"; mkdir -p "$DIST_DIR"
STAGE="$(mktemp -d)/Omniverse"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG_PATH="${DIST_DIR}/Omniverse-macOS.dmg"
hdiutil create -volname "Omniverse" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$(dirname "$STAGE")"

echo -e "${GREEN}success:${NC} Installer created: ${BOLD}${DMG_PATH}${NC}"

# Install locally
echo -e "${BLUE}info:${NC} Installing to /Applications..."
rm -rf "/Applications/Omniverse.app"
cp -R "$APP_PATH" "/Applications/Omniverse.app"

echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}success:${NC} Omniverse (native macOS) installed to /Applications."
echo -e "         Share ${BOLD}${DMG_PATH}${NC} to install on other Macs (drag to Applications)."
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${RED}${BOLD}CRITICAL macOS GATEKEEPER & 'APP DAMAGED' FIX:${NC}"
echo -e "If macOS blocks execution or claims the app is 'damaged' / 'from an unidentified developer':"
echo -e "Simply run the following command in your terminal to clear the quarantine flag:"
echo -e "👉  ${CYAN}${BOLD}xattr -cr /Applications/Omniverse.app${NC}  👈"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${YELLOW}note:${NC} The app is signed with your Personal/Development team, so it runs on"
echo -e "      your Macs. To distribute widely without Gatekeeper warnings, sign with a"
echo -e "      Developer ID certificate and notarize."
