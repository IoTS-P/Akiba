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
# GitHub's release CDN drops long TLS reads from some networks; the proxy listed first is tried
# before the origin, and both are retried.
PROXY_URL="https://gh-proxy.com/${URL}"
ok=0
for candidate in "$PROXY_URL" "$URL"; do
  echo "    trying $candidate"
  if curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 -o "$tmp/release.zip" "$candidate"; then
    ok=1
    break
  fi
done
[ "$ok" = 1 ] || { echo "!!! download failed from every source" >&2; exit 1; }

echo ">>> Extracting docs/GhidraAPI_javadoc.zip"
unzip -q -j "$tmp/release.zip" "*/docs/GhidraAPI_javadoc.zip" -d "$OUT_DIR"

ls -l "$OUT_DIR/GhidraAPI_javadoc.zip"
echo ">>> Ready: set AKIBA_GHIDRA_DOCS_ZIP=$OUT_DIR/GhidraAPI_javadoc.zip (or leave the default path)"
