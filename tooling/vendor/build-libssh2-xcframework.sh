#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/LibSSH2"
BUILD_DIR="$ROOT_DIR/.build/vendor-libssh2"

OPENSSL_VERSION="3.5.6"
OPENSSL_SHA256="deae7c80cba99c4b4f940ecadb3c3338b13cb77418409238e57d7f31f2a3b736"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"

LIBSSH2_VERSION="1.11.1"
LIBSSH2_SHA256="d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7"
LIBSSH2_URL="https://libssh2.org/download/libssh2-${LIBSSH2_VERSION}.tar.gz"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

download_and_verify() {
  local url="$1"
  local sha256="$2"
  local output="$3"

  if [[ ! -f "$output" ]]; then
    curl -fsSL "$url" -o "$output"
  fi

  local actual
  actual="$(shasum -a 256 "$output" | awk '{print $1}')"
  if [[ "$actual" != "$sha256" ]]; then
    echo "Checksum mismatch for $output" >&2
    echo "expected: $sha256" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

sdk_path() {
  xcrun --sdk "$1" --show-sdk-path
}

build_openssl_slice() {
  local name="$1"
  local configure_target="$2"
  local sdk="$3"
  local arch="$4"
  local min_version="$5"

  local src="$BUILD_DIR/src/openssl-${OPENSSL_VERSION}"
  local work="$BUILD_DIR/build/openssl-$name"
  local prefix="$BUILD_DIR/install/openssl-$name"

  rm -rf "$work" "$prefix"
  mkdir -p "$(dirname "$work")" "$(dirname "$prefix")"
  cp -R "$src" "$work"

  pushd "$work" >/dev/null
  export CROSS_TOP
  export CROSS_SDK
  CROSS_TOP="$(xcrun --sdk "$sdk" --show-sdk-platform-path)/Developer"
  CROSS_SDK="$(basename "$(sdk_path "$sdk")")"
  case "$sdk" in
    iphoneos)
      export CFLAGS="-arch $arch -mios-version-min=$min_version"
      ;;
    iphonesimulator)
      export CFLAGS="-arch $arch -mios-simulator-version-min=$min_version"
      ;;
    *)
      echo "Unsupported SDK: $sdk" >&2
      exit 1
      ;;
  esac

  ./Configure "$configure_target" no-shared no-tests no-apps no-dso no-engine "--prefix=$prefix"
  make -j"$(sysctl -n hw.ncpu)"
  make install_sw
  popd >/dev/null
}

build_libssh2_slice() {
  local name="$1"
  local sdk="$2"
  local arch="$3"
  local min_version="$4"

  local src="$BUILD_DIR/src/libssh2-${LIBSSH2_VERSION}"
  local build="$BUILD_DIR/build/libssh2-$name"
  local prefix="$BUILD_DIR/install/libssh2-$name"
  local openssl="$BUILD_DIR/install/openssl-$name"
  local combined="$BUILD_DIR/slices/$name"

  rm -rf "$build" "$prefix" "$combined"
  mkdir -p "$(dirname "$build")" "$(dirname "$prefix")"
  mkdir -p "$build" "$combined/lib" "$combined/include"

  env -u CFLAGS cmake -S "$src" -B "$build" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$min_version" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCRYPTO_BACKEND=OpenSSL \
    -DOPENSSL_ROOT_DIR="$openssl" \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl/lib/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$openssl/lib/libssl.a" \
    -DOPENSSL_INCLUDE_DIR="$openssl/include" \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DLIBSSH2_BUILD_DOCS=OFF \
    -DENABLE_ZLIB_COMPRESSION=OFF

  cmake --build "$build" --config Release --parallel
  cmake --install "$build"

  libtool -static \
    -o "$combined/lib/libquietterm-libssh2.a" \
    "$prefix/lib/libssh2.a" \
    "$openssl/lib/libcrypto.a"

  cp "$prefix/include/libssh2.h" "$combined/include/libssh2.h"
  cp "$prefix/include/libssh2_publickey.h" "$combined/include/libssh2_publickey.h"
  cp "$prefix/include/libssh2_sftp.h" "$combined/include/libssh2_sftp.h"
  cat > "$combined/include/module.modulemap" <<'MODULEMAP'
module CQuietTermLibSSH2 [system] {
  header "libssh2.h"
  export *
}
MODULEMAP
}

require_tool curl
require_tool cmake
require_tool make
require_tool libtool
require_tool lipo
require_tool xcodebuild

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/downloads" "$BUILD_DIR/src" "$BUILD_DIR/slices" "$VENDOR_DIR"

download_and_verify "$OPENSSL_URL" "$OPENSSL_SHA256" "$BUILD_DIR/downloads/openssl-${OPENSSL_VERSION}.tar.gz"
download_and_verify "$LIBSSH2_URL" "$LIBSSH2_SHA256" "$BUILD_DIR/downloads/libssh2-${LIBSSH2_VERSION}.tar.gz"

tar -xzf "$BUILD_DIR/downloads/openssl-${OPENSSL_VERSION}.tar.gz" -C "$BUILD_DIR/src"
tar -xzf "$BUILD_DIR/downloads/libssh2-${LIBSSH2_VERSION}.tar.gz" -C "$BUILD_DIR/src"

build_openssl_slice "ios-arm64" "ios64-xcrun" "iphoneos" "arm64" "18.0"
build_openssl_slice "sim-arm64" "iossimulator-arm64-xcrun" "iphonesimulator" "arm64" "18.0"
build_openssl_slice "sim-x86_64" "iossimulator-x86_64-xcrun" "iphonesimulator" "x86_64" "18.0"

build_libssh2_slice "ios-arm64" "iphoneos" "arm64" "18.0"
build_libssh2_slice "sim-arm64" "iphonesimulator" "arm64" "18.0"
build_libssh2_slice "sim-x86_64" "iphonesimulator" "x86_64" "18.0"

rm -rf "$BUILD_DIR/slices/sim-universal"
mkdir -p "$BUILD_DIR/slices/sim-universal/lib" "$BUILD_DIR/slices/sim-universal/include"
lipo -create \
  "$BUILD_DIR/slices/sim-arm64/lib/libquietterm-libssh2.a" \
  "$BUILD_DIR/slices/sim-x86_64/lib/libquietterm-libssh2.a" \
  -output "$BUILD_DIR/slices/sim-universal/lib/libquietterm-libssh2.a"
cp -R "$BUILD_DIR/slices/sim-arm64/include/." "$BUILD_DIR/slices/sim-universal/include"

rm -rf "$VENDOR_DIR/CQuietTermLibSSH2.xcframework"
xcodebuild -create-xcframework \
  -library "$BUILD_DIR/slices/ios-arm64/lib/libquietterm-libssh2.a" -headers "$BUILD_DIR/slices/ios-arm64/include" \
  -library "$BUILD_DIR/slices/sim-universal/lib/libquietterm-libssh2.a" -headers "$BUILD_DIR/slices/sim-universal/include" \
  -output "$VENDOR_DIR/CQuietTermLibSSH2.xcframework"

find "$VENDOR_DIR/CQuietTermLibSSH2.xcframework" -type f -print0 \
  | sort -z \
  | xargs -0 shasum -a 256 > "$VENDOR_DIR/CHECKSUMS.txt"

cat > "$VENDOR_DIR/README.md" <<README
# CQuietTermLibSSH2

This XCFramework is generated by \`tooling/vendor/build-libssh2-xcframework.sh\`.

- libssh2: ${LIBSSH2_VERSION}
- OpenSSL: ${OPENSSL_VERSION} LTS
- Crypto backend: OpenSSL libcrypto statically linked into \`libquietterm-libssh2.a\`
- Source checksums are pinned in the build script.
- Generated framework checksums are recorded in \`CHECKSUMS.txt\`.

Rebuild from the repository root:

\`\`\`sh
tooling/vendor/build-libssh2-xcframework.sh
\`\`\`
README

echo "Built $VENDOR_DIR/CQuietTermLibSSH2.xcframework"
