#!/usr/bin/env bash
# Prepare the Ghidra API javadoc once, at image build time.
#
# query_ghidra_api only needs docs/GhidraAPI_javadoc.zip, but that file lives inside the ~400 MB
# release archive. Downloading it on first use made the first query take minutes; this script
# pays that cost once, while the image is built, and leaves a single small zip behind.
set -euo pipefail

VERSION="${GHIDRA_VERSION:-12.2}"
BUILD_DATE="${GHIDRA_BUILD_DATE:-20261016}"
OUT_DIR="${OUT_DIR:-/home/akiba/akiba_docs}"
URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${VERSION}_build/ghidra_${VERSION}_PUBLIC_${BUILD_DATE}.zip"

mkdir -p "$OUT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo ">>> Downloading Ghidra $VERSION (release archive)"
curl -fL --retry 3 -o "$tmp/release.zip" "$URL"

echo ">>> Extracting docs/GhidraAPI_javadoc.zip"
unzip -q -j "$tmp/release.zip" "*/docs/GhidraAPI_javadoc.zip" -d "$OUT_DIR"

ls -l "$OUT_DIR/GhidraAPI_javadoc.zip"
echo ">>> Ready: set AKIBA_GHIDRA_DOCS_ZIP=$OUT_DIR/GhidraAPI_javadoc.zip (or leave the default path)"
