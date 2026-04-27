#!/bin/bash
#
# Backwards-compatible wrapper around integrate_realtek_driver.sh that
# integrates the Realtek RTL8822BU / RTL88x2BU vendor driver (cilynx fork)
# into a kernel tree as an in-tree staging driver.
#
# All options are forwarded to integrate_realtek_driver.sh; see that script
# for the full set of flags (--ref, --defconfig, --force, etc.).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
exec "$SCRIPT_DIR/integrate_realtek_driver.sh" --driver rtl88x2bu "$@"
