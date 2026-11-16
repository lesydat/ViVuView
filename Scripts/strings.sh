#!/usr/bin/env bash
# Refreshes Resources/Localizable.xcstrings from the String(localized:) calls in the sources, the way Xcode does:
# the compiler emits .stringsdata, xcstringstool merges them. New strings appear without translation; add the
# English text in the catalog (any editor, or Xcode). docs/TECH_SPEC.md §1.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/strings && mkdir -p build/strings
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/build/strings" > /dev/null
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata build/strings/*.stringsdata
python3 - <<'PY'
import json
d = json.load(open("Resources/Localizable.xcstrings"))
todo = [k for k, v in d["strings"].items() if k and "en" not in v.get("localizations", {})]
print(f"{len(d['strings'])} strings, {len(todo)} without English")
for k in todo: print("  missing en:", k)
PY
