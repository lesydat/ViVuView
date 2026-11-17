#!/usr/bin/env bash
# Refreshes Resources/Localizable.xcstrings from the String(localized:) calls in the sources, the way Xcode does:
# the compiler emits .stringsdata, xcstringstool merges them. New strings appear without translation; add the
# text for every language in the catalog (any editor, or Xcode); the list of missing ones is printed. docs/TECH_SPEC.md §1.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf build/strings && mkdir -p build/strings
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/build/strings" > /dev/null
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata build/strings/*.stringsdata
python3 - <<'PY'
import json
# Must match LANGUAGES in Scripts/bundle.sh (Vietnamese is the source language: keys are Vietnamese).
langs = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt-BR", "ru", "it"]
path = "Resources/Localizable.xcstrings"
d = json.load(open(path))
keys = [k for k in d["strings"] if k]
# Vietnamese is the source language, but it still needs its own table: with English as the development region,
# a key missing from vi.lproj would show in English. Copy each key as its Vietnamese value.
added = 0
for k in keys:
    locs = d["strings"][k].setdefault("localizations", {})
    if "vi" not in locs:
        locs["vi"] = {"stringUnit": {"state": "translated", "value": k}}
        added += 1
if added:
    json.dump(d, open(path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
    print(f"{added} Vietnamese values copied from keys")
print(f"{len(keys)} strings")
for lang in langs:
    todo = [k for k in keys if lang not in d["strings"][k].get("localizations", {})]
    print(f"  {lang}: {len(todo)} missing")
    for k in todo: print(f"    missing {lang}:", k)
PY
