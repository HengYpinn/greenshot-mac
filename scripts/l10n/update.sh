#!/usr/bin/env bash
# The translations again after texts in the code changed: extract.sh, then l10n.py generate (docs/translations.md).
# Pass --machine to also use the machine translations in scripts/l10n/machine (off by default).
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$ROOT/scripts/l10n/extract.sh"
python3 -I "$ROOT/scripts/l10n/l10n.py" generate "$@"
