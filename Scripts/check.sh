#!/usr/bin/env bash
# Everything a milestone must pass (CLAUDE.md): tests, universal bundle, every UI script on both slices.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift test"
swift test 2>&1 | tail -3

Scripts/bundle.sh

APP_BIN=build/ViVuView.app/Contents/MacOS/ViVuView
rm -rf build/smoke
# The scripts expect the Vietnamese interface whatever the machine's language.
for script in Tests/Scripts/*.txt; do
    echo "==> script $script (arm64)"
    "$APP_BIN" -AppleLanguages "(vi)" --script "$script" > /dev/null
    echo "==> script $script (x86_64 via Rosetta)"
    arch -x86_64 "$APP_BIN" -AppleLanguages "(vi)" --script "$script" > /dev/null
done
# Languages (docs/UI_SPEC.md §12): one the app lacks falls back to English; a shipped one is used.
echo "==> language fallback and German"
"$APP_BIN" -AppleLanguages "(pl)" --script Tests/Scripts/lang/fallback-en.txt > /dev/null
"$APP_BIN" -AppleLanguages "(de)" --script Tests/Scripts/lang/de.txt > /dev/null
echo "==> all checks passed"
