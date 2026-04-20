#!/usr/bin/env bash
set -euo pipefail

git submodule update --init --recursive

GHIDRA_VERSION="12.0.4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/subprojects/akiba_framework/lib"
MODULES_DIR="$SCRIPT_DIR/subprojects/akiba_framework/modules"

echo "[1/4] Fetching Ghidra $GHIDRA_VERSION release info from GitHub..."
RELEASE_TAG="Ghidra_${GHIDRA_VERSION}_build"
API_URL="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/tags/${RELEASE_TAG}"

DOWNLOAD_URL=$(curl -fsSL "$API_URL" | grep '"browser_download_url"' | grep '\.zip"' | head -1 | sed 's/.*"browser_download_url": "\(.*\)"/\1/')

if [ -z "$DOWNLOAD_URL" ]; then
    echo "ERROR: Could not find zip download URL for Ghidra $GHIDRA_VERSION" >&2
    exit 1
fi

ZIP_FILENAME=$(basename "$DOWNLOAD_URL")
EXTRACT_DIR_NAME="${ZIP_FILENAME%.zip}"
TMP_ZIP="/tmp/$ZIP_FILENAME"
TMP_EXTRACT="/tmp/$EXTRACT_DIR_NAME"

echo "[2/4] Downloading $ZIP_FILENAME to /tmp..."
curl -fL "$DOWNLOAD_URL" -o "$TMP_ZIP"

echo "Extracting to /tmp..."
unzip -q "$TMP_ZIP" -d /tmp

echo "Building ghidra.jar..."
"$TMP_EXTRACT/support/buildGhidraJar"

echo "Moving ghidra.jar to $LIB_DIR..."
mkdir -p "$LIB_DIR"
mv "$TMP_EXTRACT/support/ghidra.jar" "$LIB_DIR/ghidra.jar"

echo "[3/4] Cleaning up /tmp..."
rm -f "$TMP_ZIP"
rm -rf "$TMP_EXTRACT"

echo "[4/4] Building AkibaUtils module..."
cd "$SCRIPT_DIR"
./gradlew akiba_mod_utils:moduleJar-AkibaUtils

AMOD_JAR=$(find subprojects/akiba_mod_utils/build/libs -name "amod-AkibaUtils-*.jar" | head -1)
if [ -z "$AMOD_JAR" ]; then
    echo "ERROR: Could not find amod-AkibaUtils-*.jar after build" >&2
    exit 1
fi

mkdir -p "$MODULES_DIR"
mv "$AMOD_JAR" "$MODULES_DIR/"
echo "Moved $(basename "$AMOD_JAR") to $MODULES_DIR"

echo "Done."
