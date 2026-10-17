#!/usr/bin/env bash
# Greenshot for Mac (Community) - an unofficial macOS port of Greenshot
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Zips the browser extension (Extensions/Browser) for Chrome, Edge and Firefox:
#   build/browser-extension/greenshot-mac-companion-<version>.zip
# manifest.json is at the root of the zip, as the browsers and Firefox's about:debugging want it. The same zip serves
# Chromium browsers and Firefox (Firefox only warns about the Chromium "key"). Nothing is uploaded anywhere: publishing
# to a browser's store is a separate decision.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Extensions/Browser"
OUT_DIR="$ROOT/build/browser-extension"

VERSION="$(plutil -extract version raw -o - "$SOURCE/manifest.json")"
ZIP="$OUT_DIR/greenshot-mac-companion-$VERSION.zip"

mkdir -p "$OUT_DIR"
rm -f "$ZIP"
(cd "$SOURCE" && zip -q -r -X "$ZIP" . -x '.*' -x '*/.*')
echo "Packed $ZIP"
