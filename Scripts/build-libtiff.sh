#!/usr/bin/env bash
# Builds libtiff (with libjpeg-turbo for JPEG-in-TIFF and zstd for ZSTD-in-TIFF) as universal static
# libraries into Vendor/ (docs/TECH_SPEC.md §1). Run once before building the app; Vendor/ is not committed.
#
#   Scripts/build-libtiff.sh          build if Vendor/lib is missing or the versions changed
#   Scripts/build-libtiff.sh --force  rebuild
#
# Needs: cmake (brew install cmake). Upgrading = change a version and its SHA-256 below.
set -euo pipefail
cd "$(dirname "$0")/.."

TIFF_VERSION=4.7.2
TIFF_SHA256=4996f0c4f93094719b1ca5c6279b20e588773ba8a247533e486416fb662ddb88
JPEG_VERSION=3.2.1
JPEG_SHA256=c27ad72a68da151177929aa969ae773a2da5ac2af9ce946079314fdac8cece7f
ZSTD_VERSION=1.5.7
ZSTD_SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
MIN_MACOS=14.0
ARCHS=(arm64 x86_64)

STAMP="tiff-$TIFF_VERSION jpeg-$JPEG_VERSION zstd-$ZSTD_VERSION macos-$MIN_MACOS"
if [[ "${1:-}" != "--force" && -f Vendor/.stamp && "$(cat Vendor/.stamp)" == "$STAMP" ]]; then
    echo "==> Vendor/ is up to date ($STAMP)"
    exit 0
fi
command -v cmake >/dev/null || { echo "error: cmake not found (brew install cmake)" >&2; exit 1; }

SRC=build/vendor-src
WORK=build/vendor-build
mkdir -p "$SRC"
rm -rf "$WORK"

fetch() {   # url file sha256
    local url=$1 file=$2 sha=$3
    if [[ ! -f "$SRC/$file" ]]; then
        echo "==> downloading $file"
        curl -fsSL -o "$SRC/$file.part" "$url"
        mv "$SRC/$file.part" "$SRC/$file"
    fi
    echo "$sha  $SRC/$file" | shasum -a 256 -c --quiet - || { echo "error: checksum mismatch for $file" >&2; exit 1; }
}

fetch "https://download.osgeo.org/libtiff/tiff-$TIFF_VERSION.tar.xz" "tiff-$TIFF_VERSION.tar.xz" "$TIFF_SHA256"
fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VERSION/libjpeg-turbo-$JPEG_VERSION.tar.gz" \
      "libjpeg-turbo-$JPEG_VERSION.tar.gz" "$JPEG_SHA256"
fetch "https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/zstd-$ZSTD_VERSION.tar.gz" \
      "zstd-$ZSTD_VERSION.tar.gz" "$ZSTD_SHA256"

mkdir -p "$WORK/src"
tar -xf "$SRC/tiff-$TIFF_VERSION.tar.xz" -C "$WORK/src"
tar -xf "$SRC/libjpeg-turbo-$JPEG_VERSION.tar.gz" -C "$WORK/src"
tar -xf "$SRC/zstd-$ZSTD_VERSION.tar.gz" -C "$WORK/src"

# Never pick up Homebrew's copies of these libraries.
COMMON=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=$MIN_MACOS -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local" -DCMAKE_FIND_FRAMEWORK=NEVER)

for arch in "${ARCHS[@]}"; do
    prefix="$PWD/$WORK/install-$arch"
    echo "==> zstd $ZSTD_VERSION ($arch)"
    cmake -S "$WORK/src/zstd-$ZSTD_VERSION/build/cmake" -B "$WORK/zstd-$arch" "${COMMON[@]}" \
        -DCMAKE_OSX_ARCHITECTURES=$arch -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_TESTS=OFF \
        -DZSTD_LEGACY_SUPPORT=OFF -DZSTD_MULTITHREAD_SUPPORT=OFF > "$WORK/zstd-$arch.log"
    cmake --build "$WORK/zstd-$arch" --target install -j 8 >> "$WORK/zstd-$arch.log"

    echo "==> libjpeg-turbo $JPEG_VERSION ($arch)"
    # x86_64 SIMD needs nasm; without it the x86_64 slice builds the portable C code paths.
    simd=ON
    [[ $arch == x86_64 ]] && ! command -v nasm >/dev/null && simd=OFF
    cmake -S "$WORK/src/libjpeg-turbo-$JPEG_VERSION" -B "$WORK/jpeg-$arch" "${COMMON[@]}" \
        -DCMAKE_OSX_ARCHITECTURES=$arch -DCMAKE_SYSTEM_PROCESSOR=$arch -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF -DWITH_TESTS=OFF \
        -DWITH_SIMD=$simd > "$WORK/jpeg-$arch.log"
    cmake --build "$WORK/jpeg-$arch" --target install -j 8 >> "$WORK/jpeg-$arch.log"

    echo "==> libtiff $TIFF_VERSION ($arch)"
    cmake -S "$WORK/src/tiff-$TIFF_VERSION" -B "$WORK/tiff-$arch" "${COMMON[@]}" \
        -DCMAKE_OSX_ARCHITECTURES=$arch -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_PREFIX_PATH="$prefix" \
        -DBUILD_SHARED_LIBS=OFF -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-contrib=OFF -Dtiff-docs=OFF \
        -Dtiff-opengl=OFF -Dcxx=OFF -Dzlib=ON -Dlibdeflate=OFF -Dpixarlog=ON -Djpeg=ON -Dold-jpeg=ON \
        -Djbig=OFF -Dlerc=OFF -Dlzma=OFF -Dwebp=OFF -Dzstd=ON \
        -DJPEG_INCLUDE_DIR="$prefix/include" -DJPEG_LIBRARY="$prefix/lib/libjpeg.a" \
        -DZSTD_INCLUDE_DIR="$prefix/include" -DZSTD_LIBRARY="$prefix/lib/libzstd.a" > "$WORK/tiff-$arch.log"
    cmake --build "$WORK/tiff-$arch" --target install -j 8 >> "$WORK/tiff-$arch.log"
    grep -E "JPEG|ZSTD|zlib" "$WORK/tiff-$arch/libtiff/tif_config.h" | grep define | sed 's/^/    /' | head -6
done

echo "==> universal libraries in Vendor/"
rm -rf Vendor
mkdir -p Vendor/lib Vendor/include Vendor/licenses
for lib in libtiff.a libjpeg.a libzstd.a; do
    lipo -create "$WORK/install-arm64/lib/$lib" "$WORK/install-x86_64/lib/$lib" -output "Vendor/lib/$lib"
    echo "    $lib: $(lipo -archs Vendor/lib/$lib)"
done
cp "$WORK"/install-arm64/include/{tiff.h,tiffio.h,tiffvers.h,tiffconf.h} Vendor/include/
cp "$WORK/src/tiff-$TIFF_VERSION/LICENSE.md" Vendor/licenses/libtiff.txt
cp "$WORK/src/libjpeg-turbo-$JPEG_VERSION/LICENSE.md" Vendor/licenses/libjpeg-turbo.txt
cp "$WORK/src/zstd-$ZSTD_VERSION/LICENSE" Vendor/licenses/zstd.txt
echo "$STAMP" > Vendor/.stamp
echo "==> done: $STAMP"
