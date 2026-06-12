#!/bin/bash

# ==============================================================================
# Android Real Device Automated Deployer & Orchestrator
# ==============================================================================
# Detects connected Android devices via adb, compiles the project via Gradle,
# deploys the APK, and launches the MainActivity.
# ==============================================================================

set -eo pipefail

# Force the Java Home to the embedded JDK inside Android Studio
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}       OMNIPLAY — AUTOMATED ANDROID REAL DEVICE DEPLOYER${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

# 1. Pre-flight Checks
if ! command -v adb &> /dev/null; then
    echo -e "${RED}error:${NC} ADB ('adb') is required but not installed or not in PATH."
    echo -e "       Please install the Android SDK / Platform Tools."
    exit 1
fi

if ! command -v java &> /dev/null; then
    echo -e "${RED}error:${NC} Java JDK not found. JDK 17+ is required to compile."
    exit 1
fi

if [ -f "android/gradlew" ]; then
    chmod +x android/gradlew
else
    echo -e "${RED}error:${NC} Gradle wrapper ('gradlew') was not found in 'android/'."
    exit 1
fi

# 2. Device Detection
echo -e "${BLUE}info:${NC} Scanning for connected Android devices via adb..."
DEVICE_ID=$(adb devices | grep -E "\bdevice\b" | head -n 1 | awk '{print $1}')

if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}error:${NC} No active connected Android devices found."
    echo -e "       Please connect a device via USB, ensure USB Debugging is enabled,"
    echo -e "       and accept the RSA authorization prompt on the device's screen."
    echo -e "       Current status:"
    adb devices
    exit 1
fi

# Try to get the friendly device brand + model name
DEVICE_NAME=$(adb -s "$DEVICE_ID" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "Android Device")
DEVICE_BRAND=$(adb -s "$DEVICE_ID" shell getprop ro.product.brand 2>/dev/null | tr -d '\r' || echo "")
if [ -n "$DEVICE_BRAND" ]; then
    DEVICE_NAME="${DEVICE_BRAND} ${DEVICE_NAME}"
fi

echo -e "${GREEN}success:${NC} Detected connected target device:"
echo -e "         - Name:  ${BOLD}${DEVICE_NAME}${NC}"
echo -e "         - Serial: ${CYAN}${DEVICE_ID}${NC}"

# 3. Compiling the Debug APK
echo -e "${BLUE}info:${NC} Compiling Kotlin/Compose Android app via Gradle..."
(cd android && ./gradlew assembleDebug)

APK_PATH="android/app/build/outputs/apk/debug/app-debug.apk"

if [ ! -f "$APK_PATH" ]; then
    echo -e "${RED}error:${NC} Compiled APK bundle was not found at expected path: $APK_PATH"
    exit 1
fi

# 4. Installing the APK
echo -e "${BLUE}info:${NC} Deploying app to ${DEVICE_NAME} (this will replace previous installs)..."
adb -s "$DEVICE_ID" install -r -d "$APK_PATH"

# 5. Launching the App
echo -e "${BLUE}info:${NC} Booting Omniverse on ${DEVICE_NAME}..."
adb -s "$DEVICE_ID" shell am start -n com.finix.omniverse/com.finix.omniverse.MainActivity

echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}success:${NC} Omniverse is now running on your ${DEVICE_NAME}!"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
