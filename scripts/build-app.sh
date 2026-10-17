#!/usr/bin/env bash
# Builds "build/Greenshot for Mac (Community).app".
#
# Environment:
#   VERSION        version shown in Finder and About (default 0.1.0)
#   BUILD_NUMBER   CFBundleVersion (default 1)
#   BUNDLE_ID      bundle identifier (default io.github.greenshot-mac.GreenshotMac)
#   SIGN_IDENTITY  codesign identity. Default: a code signing certificate named "Greenshot Dev" in your keychain
#                  when there is one, else "-" (ad hoc). macOS remembers the screen recording permission per
#                  signature: ad hoc builds need it again after every rebuild, a stable identity (even a
#                  self-signed one, see the README) keeps it.
#   ARCHS          e.g. "arm64 x86_64" for a universal app (Intel and Apple silicon)
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Greenshot for Mac (Community)"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-io.github.greenshot-mac.GreenshotMac}"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q '"Greenshot Dev"'; then
    SIGN_IDENTITY="Greenshot Dev"
  else
    SIGN_IDENTITY="-"
  fi
fi

args=(-c release --product GreenshotMac)
for arch in ${ARCHS:-}; do args+=(--arch "$arch"); done
# A multi-arch build uses another build system; its own folder keeps `swift test` in .build working.
if [[ -n "${ARCHS:-}" ]]; then args+=(--scratch-path .build/universal); fi
swift build "${args[@]}"
BIN_DIR="$(swift build "${args[@]}" --show-bin-path)"

if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GreenshotMac" "$APP/Contents/MacOS/GreenshotMac"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# The hardened runtime needs the Apple Events entitlement for the Office, Mail and Notes destinations.
codesign --force --options runtime --entitlements "$ROOT/Resources/GreenshotMac.entitlements" --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP (signed: $([[ "$SIGN_IDENTITY" == "-" ]] && echo "ad hoc" || echo "$SIGN_IDENTITY"))"
