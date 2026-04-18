#!/usr/bin/env bash
set -euo pipefail

# Run the full OverworkTracker test suite with the default Swift toolchain.
# Used locally and by release.sh to guarantee that bad accounting logic never
# ships.

cd "$(dirname "$0")/.."

echo "==> swift test"
swift test -c debug
