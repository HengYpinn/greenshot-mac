#!/usr/bin/env bash
# Writes scripts/l10n/mac-keys.json: every localizable text of the app (SwiftUI literals, String(localized:)), as the
# compiler finds them (-emit-localized-strings), with the files they are in. A fresh build (about a minute), so no
# text of a deleted file stays behind. See docs/translations.md.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SCRATCH="${L10N_SCRATCH:-$ROOT/.build/l10n-extract}"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/strings"
swift build --scratch-path "$SCRATCH" --product GreenshotMac \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$SCRATCH/strings"
python3 -I scripts/l10n/l10n.py keys "$SCRATCH/strings" > scripts/l10n/mac-keys.json
echo "Wrote scripts/l10n/mac-keys.json ($(grep -c '"key":' scripts/l10n/mac-keys.json) texts)"
