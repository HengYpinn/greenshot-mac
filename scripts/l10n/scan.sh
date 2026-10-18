#!/usr/bin/env bash
# The texts in the code that aren't localizable yet: builds the app with the compiler's -emit-localized-strings into
# .build/l10n-scan (incremental after the first run) and lists, per file, the string literals that look like
# user-visible text and are neither a SwiftUI literal nor in String(localized:). Touches no table (docs/translations.md).
# Usage: scripts/l10n/scan.sh [--summary] <paths relative to the repository, e.g. Sources/GreenshotMac/Editor>
# Output: path:line<TAB>ui|other<TAB>text (ui: the argument of a UI call; other: decide whether it is a text).
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SCRATCH="${L10N_SCAN_SCRATCH:-$ROOT/.build/l10n-scan}"
mkdir -p "$SCRATCH/strings"
if [[ -z "${L10N_SCAN_NO_BUILD:-}" ]]; then
  swift build --scratch-path "$SCRATCH" --product GreenshotMac \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$SCRATCH/strings" >&2
fi
python3 -I scripts/l10n/l10n.py scan --strings "$SCRATCH/strings" "$@"
