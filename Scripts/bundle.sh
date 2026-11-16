#!/usr/bin/env bash
# Build ViVuView as a universal (arm64 + x86_64) release .app in build/ViVuView.app.
# See docs/TECH_SPEC.md §1.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ViVuView"
BUNDLE_ID="app.vivuview.ViVuView"
VERSION="0.1.0"
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
# Vietnamese and English strings (String Catalog → .lproj), docs/TECH_SPEC.md §1.
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/Licenses"
cp Vendor/licenses/*.txt "$APP/Contents/Resources/Licenses/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>vi</string>
    <key>CFBundleLocalizations</key><array><string>vi</string><string>en</string></array>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
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
