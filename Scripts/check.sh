#!/usr/bin/env bash
# Everything a milestone must pass (CLAUDE.md): tests, universal bundle, every UI script on both slices.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift test"
swift test 2>&1 | tail -3

Scripts/bundle.sh

APP_BIN=build/ViVuView.app/Contents/MacOS/ViVuView
rm -rf build/smoke
for script in Tests/Scripts/*.txt; do
    echo "==> script $script (arm64)"
    "$APP_BIN" --script "$script" > /dev/null
    echo "==> script $script (x86_64 via Rosetta)"
    arch -x86_64 "$APP_BIN" --script "$script" > /dev/null
done
echo "==> all checks passed"
