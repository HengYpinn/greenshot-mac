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

args=(-c release)
for arch in ${ARCHS:-}; do args+=(--arch "$arch"); done
# A multi-arch build uses another build system; its own folder keeps `swift test` in .build working.
SCRATCH=.build
if [[ -n "${ARCHS:-}" ]]; then SCRATCH=.build/universal; args+=(--scratch-path "$SCRATCH"); fi
# The app, greenshot-cli (its command line tool), greenshot-mcp (the MCP server for AI tools) and the browser extension's
# native messaging host.
swift build "${args[@]}" --product GreenshotMac
swift build "${args[@]}" --product greenshot-cli
swift build "${args[@]}" --product greenshot-native-host
swift build "${args[@]}" --product greenshot-mcp
BIN_DIR="$(swift build "${args[@]}" --show-bin-path)"

if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN_DIR/GreenshotMac" "$APP/Contents/MacOS/GreenshotMac"
cp "$BIN_DIR/greenshot-cli" "$APP/Contents/Helpers/greenshot-cli"
cp "$BIN_DIR/greenshot-native-host" "$APP/Contents/Helpers/greenshot-native-host"
cp "$BIN_DIR/greenshot-mcp" "$APP/Contents/Helpers/greenshot-mcp"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The AppleScript dictionary (Info.plist OSAScriptingDefinition).
cp Resources/GreenshotMac.sdef "$APP/Contents/Resources/GreenshotMac.sdef"
# The recipe schema (recipe editor, AI tools' get_recipe_schema) and the example recipes greenshot-mcp sends with it.
cp Resources/recipe.schema.json "$APP/Contents/Resources/recipe.schema.json"
ditto Resources/RecipeExamples "$APP/Contents/Resources/RecipeExamples"
# The browser extension, for Settings › Expert › Browser extension › Show Extension Folder.
if [[ -d Extensions/Browser ]]; then ditto Extensions/Browser "$APP/Contents/Resources/BrowserExtension"; fi
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
  Resources/Info.plist > "$APP/Contents/Info.plist"
# The translations (docs/translations.md): one <language>.lproj each, listed in CFBundleLocalizations so macOS offers
# them in System Settings › General › Language & Region › Applications; the help pages by language.
if [[ -d Resources/Localizations ]]; then
  ditto Resources/Localizations "$APP/Contents/Resources"
  LOCALIZATIONS="$(cd Resources/Localizations && for d in *.lproj; do printf '"%s",' "${d%.lproj}"; done)"
  plutil -replace CFBundleLocalizations -json "[${LOCALIZATIONS%,}]" "$APP/Contents/Info.plist"
fi
if [[ -d Resources/Help ]]; then ditto Resources/Help "$APP/Contents/Resources/Help"; fi
plutil -lint "$APP/Contents/Info.plist" >/dev/null
if ! sdef "$APP" >/dev/null; then
  echo "error: the AppleScript dictionary Resources/GreenshotMac.sdef doesn't load" >&2
  exit 1
fi

# Shortcuts, Siri and Spotlight find the app's actions (App Intents) in Contents/Resources/Metadata.appintents, which
# Xcode's build system extracts with appintentsmetadataprocessor from the compiler's constant values. SwiftPM's Swift
# Build backend writes those values itself; older backends get the flags in a second build. Every failure here only
# warns: the app works without its Shortcuts actions.
warn_intents() { echo "warning: no Shortcuts actions in the app: $*" >&2; }
find_const_values() {
  find "$SCRATCH" -name 'GreenshotMac*.swiftconstvalues' -ipath '*release*' 2>/dev/null | sort
}
extract_app_intents() {
  if ! xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
    warn_intents "appintentsmetadataprocessor not found (it comes with Xcode)"
    return
  fi
  local consts
  consts="$(find_const_values)"
  if [[ -z "$consts" ]]; then
    local protocols
    protocols="$(mktemp -t appintents-protocols).json"
    echo '["AnyResolverProviding","AppEntity","AppEnum","AppExtension","AppIntent","AppIntentsPackage","AppShortcutProviding",'\
'"AppShortcutsProvider","AppUnionValue","AppUnionValueCasesProviding","DynamicOptionsProvider","EntityQuery",'\
'"ExtensionPointDefining","IntentValueQuery","Resolver","TransientEntity","_AssistantIntentsProvider",'\
'"_GenerativeFunctionExtractable","_IntentValueRepresentable"]' > "$protocols"
    if ! swift build "${args[@]}" --product GreenshotMac -Xswiftc -emit-const-values \
        -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$protocols"; then
      warn_intents "the build with constant values failed"
      return
    fi
    consts="$(find_const_values)"
  fi
  if [[ -z "$consts" ]]; then
    warn_intents "the compiler wrote no constant values"
    return
  fi
  # The metadata doesn't depend on the architecture: the values of one are enough.
  local const_file arch
  const_file="$(echo "$consts" | grep -m1 arm64 || echo "$consts" | head -n1)"
  arch="$(echo "$const_file" | grep -q x86_64 && echo x86_64 || echo arm64)"
  local lists
  lists="$(mktemp -d)"
  echo "$const_file" > "$lists/const-values.txt"
  find "$ROOT/Sources/GreenshotMac" -name '*.swift' | sort > "$lists/sources.txt"
  local toolchain xcode_build
  toolchain="$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")"
  xcode_build="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
  if ! xcrun appintentsmetadataprocessor --toolchain-dir "$toolchain" --module-name GreenshotMac \
      --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" --xcode-version "${xcode_build:-unknown}" \
      --platform-family macOS --deployment-target 14.0 --bundle-identifier "$BUNDLE_ID" \
      --output "$APP/Contents/Resources" --target-triple "$arch-apple-macos14.0" \
      --binary-file "$APP/Contents/MacOS/GreenshotMac" --source-file-list "$lists/sources.txt" \
      --swift-const-vals-list "$lists/const-values.txt" --compile-time-extraction --deployment-aware-processing \
      >"$lists/processor.log" 2>&1; then
    warn_intents "appintentsmetadataprocessor failed (see $lists/processor.log)"
    return
  fi
  if [[ ! -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" ]]; then
    warn_intents "appintentsmetadataprocessor wrote no metadata"
  fi
}
extract_app_intents

# Nested code is signed first (inside out), with its own identifier; then the bundle seals it.
codesign --force --options runtime --identifier "$BUNDLE_ID.cli" --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/greenshot-cli"
codesign --force --options runtime --identifier "$BUNDLE_ID.nativehost" --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/greenshot-native-host"
codesign --force --options runtime --identifier "$BUNDLE_ID.mcp" --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/greenshot-mcp"
# The hardened runtime needs the Apple Events entitlement for the Office, Mail and Notes destinations.
codesign --force --options runtime --entitlements "$ROOT/Resources/GreenshotMac.entitlements" --sign "$SIGN_IDENTITY" "$APP"
echo "Built $APP (signed: $([[ "$SIGN_IDENTITY" == "-" ]] && echo "ad hoc" || echo "$SIGN_IDENTITY"))"
echo "Command line tool: sudo ln -sf '$APP/Contents/Helpers/greenshot-cli' /usr/local/bin/greenshot-cli"
echo "MCP server for AI tools: $APP/Contents/Helpers/greenshot-mcp (see docs/mcp/README.md)"
