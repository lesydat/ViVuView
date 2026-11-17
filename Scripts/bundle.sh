#!/usr/bin/env bash
# Build ViVuView as a universal (arm64 + x86_64) release .app in build/ViVuView.app.
# See docs/TECH_SPEC.md §1.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ViVuView"
BUNDLE_ID="app.vivuview.ViVuView"
VERSION="0.2.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
MIN_MACOS="14.0"
ARCH_FLAGS=(--arch arm64 --arch x86_64)

# Static libtiff / libjpeg-turbo / zstd (no-op when Vendor/ is current).
Scripts/build-libtiff.sh

echo "==> swift build (release, universal)"
swift build -c release "${ARCH_FLAGS[@]}" --product "$APP_NAME"
swift build -c release "${ARCH_FLAGS[@]}" --product vivu-bench
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
# CFBundleDocumentTypes comes from FormatCatalog, the same list the app and the Formats tab use.
DOC_TYPES="$("$BIN_DIR/vivu-bench" doc-types)"

APP="build/$APP_NAME.app"
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
# SwiftPM records the deployment target as the SDK version (LC_BUILD_VERSION sdk 14.0) although it compiles
# against the current SDK. AppKit reads that number to decide the look: with 14.0 the app gets the old
# compatibility appearance (flat traffic lights, old controls). Record the SDK actually used.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/$APP_NAME.tmp" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null
mv "$APP/Contents/MacOS/$APP_NAME.tmp" "$APP/Contents/MacOS/$APP_NAME"
if [[ "$(otool -l "$APP/Contents/MacOS/$APP_NAME" | awk '/LC_BUILD_VERSION/{f=1} f&&/sdk/{print $2; exit}')" != "$SDK_VERSION" ]]; then
    echo "error: SDK version not recorded" >&2
    exit 1
fi
# Strings for every language (String Catalog → .lproj), docs/TECH_SPEC.md §1, UI_SPEC §12. The source strings
# are Vietnamese; English is the development region, so a system language the app lacks falls back to English.
# LANGUAGES must match AppLanguage.all in Sources/ViVuView/Settings.swift.
LANGUAGES=(en vi zh-Hans zh-Hant ja ko fr de es pt-BR ru it)
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
for lang in "${LANGUAGES[@]}"; do
    # Every language, Vietnamese included, needs its own table: a missing one falls back to English.
    if [[ ! -f "$APP/Contents/Resources/$lang.lproj/Localizable.strings" ]]; then
        echo "error: no strings compiled for $lang" >&2
        exit 1
    fi
done
LOCALIZATIONS="$(printf '<string>%s</string>' "${LANGUAGES[@]}")"
# App icon: Resources/AppIcon.icon (Icon Composer format, made from Resources/Logo.svg) → Assets.car for
# Liquid Glass on macOS 26+, plus AppIcon.icns for macOS 14–15.
ICON_TMP="$(mktemp -d)"
xcrun actool Resources/AppIcon.icon --compile "$ICON_TMP" --platform macosx --minimum-deployment-target "$MIN_MACOS" \
    --app-icon AppIcon --target-device mac --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null
cp "$ICON_TMP/Assets.car" "$ICON_TMP/AppIcon.icns" "$APP/Contents/Resources/"
rm -rf "$ICON_TMP"
mkdir -p "$APP/Contents/Resources/Licenses"
cp Vendor/licenses/*.txt "$APP/Contents/Resources/Licenses/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array>$LOCALIZATIONS</array>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>CFBundleDocumentTypes</key>
    $DOC_TYPES
</dict>
</plist>
PLIST
plutil -lint -s "$APP/Contents/Info.plist"

echo "==> codesign (ad-hoc)"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "==> architectures: $ARCHS"
for arch in arm64 x86_64; do
    if [[ " $ARCHS " != *" $arch "* ]]; then
        echo "error: $arch slice missing" >&2
        exit 1
    fi
done

# Only system libraries may be linked dynamically (docs/TECH_SPEC.md §11.6).
NON_SYSTEM="$(otool -L "$APP/Contents/MacOS/$APP_NAME" | grep -E '^[[:space:]]' | awk '{print $1}' \
    | grep -vE '^(/usr/lib/|/System/Library/)' || true)"
if [[ -n "$NON_SYSTEM" ]]; then
    echo "error: non-system libraries linked:" >&2
    echo "$NON_SYSTEM" >&2
    exit 1
fi
echo "==> linked libraries: system only"

echo "==> done: $APP"
