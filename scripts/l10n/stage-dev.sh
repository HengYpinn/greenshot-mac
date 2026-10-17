#!/usr/bin/env bash
# Links the translations and help pages next to a development build (`swift build`), which finds them there like the
# app finds them in Contents/Resources. Then e.g. `"$(swift build --show-bin-path)/GreenshotMac" --language de-DE
# --settings-dir <folder>` or `--snapshot <folder> --language ar-SY`. `--remove` takes the links away again; without
# them a development build is English.
# Usage: scripts/l10n/stage-dev.sh [--remove] [bin folder]
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
REMOVE=0
if [[ "${1:-}" == "--remove" ]]; then REMOVE=1; shift; fi
BIN="${1:-$(swift build --show-bin-path)}"
for folder in Resources/Localizations/*.lproj; do
  link="$BIN/$(basename "$folder")"
  if [[ $REMOVE == 1 ]]; then rm -f "$link"; else ln -sfn "$ROOT/$folder" "$link"; fi
done
if [[ $REMOVE == 1 ]]; then rm -f "$BIN/Help"; else ln -sfn "$ROOT/Resources/Help" "$BIN/Help"; fi
echo "$([[ $REMOVE == 1 ]] && echo Removed || echo Linked) the translations $([[ $REMOVE == 1 ]] && echo from || echo into) $BIN"
