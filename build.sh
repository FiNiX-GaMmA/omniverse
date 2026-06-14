#!/bin/bash

# ==============================================================================
# Omniplay — Enterprise-Grade Native Compilation Orchestrator
# ==============================================================================
# Orchestrates local builds and compilation from source for native mobile codebases:
# 1. Android (Kotlin + Jetpack Compose) via Gradle.
# 2. iOS (Swift + SwiftUI) via Xcode & XcodeGen.
# ==============================================================================

# Fail immediately if any command in a pipeline fails
set -eo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print Banner
echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}         OMNIPLAY — ENTERPRISE NATIVE BUILD SYSTEM (v2.0)${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

# Function: Display usage documentation
show_help() {
    echo -e "Usage: ${BOLD}./build.sh [target]${NC}"
    echo -e ""
    echo -e "Available Compilation Targets:"
    echo -e "  ${GREEN}android${NC}     Compile, sign, and package native Android Release APK via Gradle."
    echo -e "  ${GREEN}ios${NC}         Generate Xcode project, compile Swift sources, and package Unsigned IPA (macOS)."
    echo -e "  ${GREEN}desktop${NC}     Install npm dependencies and package the Electron app for Windows, macOS, and Linux."
    echo -e "  ${GREEN}clean${NC}       Clear native build caches, Gradle outputs, and Xcode build states."
    echo -e "  ${GREEN}help${NC}        Show this compilation documentation."
    echo -e ""
    echo -e "Examples:"
    echo -e "  ./build.sh android"
    echo -e "  ./build.sh ios"
}

# Function: Clean workspace and build artifacts
target_clean() {
    echo -e "${BLUE}info:${NC} Purging compilation outputs and cache structures..."

    # Clean Android
    if [ -d "android" ]; then
        echo -e "${BLUE}info:${NC} Running Android Gradle clean task..."
        (cd android && ./gradlew clean)
    fi

    # Clean iOS
    if [ -d "ios" ]; then
        echo -e "${BLUE}info:${NC} Purging Xcode build structures..."
        rm -rf ios/build ios/DerivedData
    fi

    # Clean Desktop
    if [ -d "desktop" ]; then
        echo -e "${BLUE}info:${NC} Purging Electron desktop build outputs..."
        rm -rf desktop/dist desktop/node_modules
    fi

    # Clean distribution folder
    rm -rf dist

    echo -e "${GREEN}success:${NC} Native workspace cleaned."
}

# Function: Compile Android release app
target_android() {
    # Auto-detect Android Studio JDK as fallback if not set
    if [ -z "$JAVA_HOME" ] && [ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]; then
        export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        export PATH="$JAVA_HOME/bin:$PATH"
    fi

    echo -e "${BLUE}info:${NC} Executing Android pre-build checks..."

    # Check Java JDK
    if ! command -v java &> /dev/null; then
        echo -e "${RED}error:${NC} Java JDK not found. JDK 17+ is required to compile native Android sources."
        exit 1
    fi

    # Ensure Gradle wrapper is executable
    if [ -f "android/gradlew" ]; then
        chmod +x android/gradlew
    else
        echo -e "${RED}error:${NC} Gradle wrapper ('gradlew') was not found in 'android/'."
        exit 1
    fi

    echo -e "${BLUE}info:${NC} Compiling native Android signed APK via Gradle..."
    (cd android && ./gradlew assembleRelease)

    # Package output binary
    mkdir -p dist
    if [ -f "android/app/build/outputs/apk/release/app-release.apk" ]; then
        cp android/app/build/outputs/apk/release/app-release.apk dist/Omniverse-android-signed.apk
        echo -e "${GREEN}${BOLD}======================================================================${NC}"
        echo -e "${GREEN}success:${NC} Native Android APK compiled successfully from source!"
        echo -e "${BLUE}Output location:${NC} ${BOLD}dist/Omniverse-android-signed.apk${NC}"
        echo -e "${GREEN}${BOLD}======================================================================${NC}"
    else
        echo -e "${RED}error:${NC} Android APK compilation failed."
        exit 1
    fi
}

# Function: Compile iOS release app
target_ios() {
    echo -e "${BLUE}info:${NC} Executing iOS pre-build checks..."

    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}error:${NC} iOS compilation requires macOS with Xcode installed."
        exit 1
    fi

    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${RED}error:${NC} Xcode Command Line Tools ('xcodebuild') are required."
        exit 1
    fi

    # Generate Xcode Project via XcodeGen if project.yml is present
    if [ -f "ios/project.yml" ] && command -v xcodegen &> /dev/null; then
        echo -e "${BLUE}info:${NC} Re-generating Xcode project files via XcodeGen..."
        (cd ios && xcodegen)
    fi

    echo -e "${BLUE}info:${NC} Compiling iOS App bundle via xcodebuild (no codesign)..."
    (cd ios && xcodebuild -project Omniverse.xcodeproj \
                          -scheme Omniverse \
                          -configuration Release \
                          -sdk iphoneos \
                          -archivePath build/Omniverse.xcarchive \
                          CODE_SIGN_IDENTITY="" \
                          CODE_SIGNING_REQUIRED=NO \
                          CODE_SIGNING_ALLOWED=NO \
                          clean archive)

    echo -e "${BLUE}info:${NC} Packaging compiled native bundle into Unsigned IPA..."
    mkdir -p dist
    mkdir -p ios/build/Payload

    if [ -d "ios/build/Omniverse.xcarchive/Products/Applications/Omniverse.app" ]; then
        cp -r ios/build/Omniverse.xcarchive/Products/Applications/Omniverse.app ios/build/Payload/
        (cd ios/build && zip -q -r ../../dist/Omniverse-ios-unsigned.ipa Payload)
        rm -rf ios/build/Payload

        echo -e "${GREEN}${BOLD}======================================================================${NC}"
        echo -e "${GREEN}success:${NC} Native iOS/iPadOS IPA compiled successfully from source!"
        echo -e "${BLUE}Output location:${NC} ${BOLD}dist/Omniverse-ios-unsigned.ipa${NC}"
        echo -e "${GREEN}${BOLD}======================================================================${NC}"
    else
        echo -e "${RED}error:${NC} Xcode build archive was not found. Compilation failed."
        rm -rf ios/build/Payload
        exit 1
    fi
}

# Function: Compile and package Electron Desktop app
target_desktop() {
    echo -e "${BLUE}info:${NC} Preparing Electron Desktop Workspace..."

    # Check Node.js and npm
    if ! command -v npm &> /dev/null; then
        echo -e "${RED}error:${NC} Node.js and npm are required to build the Electron desktop app."
        exit 1
    fi

    # Go to desktop directory and install dependencies if not installed
    echo -e "${BLUE}info:${NC} Installing Electron project dependencies via npm..."
    (cd desktop && npm install)

    echo -e "${BLUE}info:${NC} Bundling and packaging desktop binaries..."
    # Packaging for host operating system
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${BLUE}info:${NC} Target OS: macOS. Generating Universal App (Intel & Apple Silicon DMG)..."
        (cd desktop && npm run dist:mac)
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo -e "${BLUE}info:${NC} Target OS: Linux. Generating AppImage and DEB package..."
        (cd desktop && npm run dist:linux)
    else
        echo -e "${BLUE}info:${NC} Target OS: Windows. Generating Setup EXE installer..."
        (cd desktop && npm run dist:win)
    fi

    # Move outputs to dist/
    mkdir -p dist/desktop
    if [ -d "desktop/dist" ]; then
        cp -r desktop/dist/* dist/desktop/
        echo -e "${GREEN}${BOLD}======================================================================${NC}"
        echo -e "${GREEN}success:${NC} Omniverse Electron Desktop App compiled successfully!"
        echo -e "${BLUE}Output folder:${NC} ${BOLD}dist/desktop/${NC}"
        echo -e "${GREEN}${BOLD}======================================================================${NC}"
    else
        echo -e "${RED}error:${NC} Electron packaging failed."
        exit 1
    fi
}

# Parse Command-Line Target Arguments
case "$1" in
    android)
        target_android
        ;;
    ios)
        target_ios
        ;;
    desktop)
        target_desktop
        ;;
    clean)
        target_clean
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        echo -e "${RED}error:${NC} Unknown native compilation target '$1'."
        echo -e ""
        show_help
        exit 1
        ;;
esac
