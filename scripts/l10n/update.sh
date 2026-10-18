#!/usr/bin/env bash
# The translations again after texts in the code changed: extract.sh, then l10n.py generate (docs/translations.md).
# Pass --no-machine to leave out the machine translations of scripts/l10n/machine (they are in by default).
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$ROOT/scripts/l10n/extract.sh"
python3 -I "$ROOT/scripts/l10n/l10n.py" generate "$@"
