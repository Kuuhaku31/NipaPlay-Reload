#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_NATIVE_DIR="$(dirname "$SCRIPT_DIR")"
NIPAPLAY_ROOT="$(cd "${CPP_NATIVE_DIR}/.." && pwd)"
ERIKA_ROOT="${ERIKA_ROOT:-${NIPAPLAY_ROOT}/third_party/erika}"
ERIKA_NATIVE_PROFILE="${ERIKA_NATIVE_PROFILE:-lgpl}"
HOST_JOBS="$(sysctl -n hw.ncpu)"

# Xcode Run Script 阶段的 PATH 不会继承 shell 配置，显式补上 Homebrew 路径
# 让 Apple Silicon (/opt/homebrew) 和 Intel (/usr/local) 都能找到 cmake 等工具
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

# Map Xcode configuration to CMake build type
if [ "${CONFIGURATION}" = "Debug" ]; then
    CMAKE_BUILD_TYPE="Debug"
else
    CMAKE_BUILD_TYPE="Release"
fi

BUILD_DIR="${DERIVED_SOURCES_DIR:-${CPP_NATIVE_DIR}/build_macos}"

cmake -S "${CPP_NATIVE_DIR}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" \
    -DNP_LIB_TYPE=SHARED \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"

cmake --build "${BUILD_DIR}" -j"${HOST_JOBS}"

if [ ! -f "${ERIKA_ROOT}/Cargo.toml" ]; then
    echo "error: Erika source not found at ${ERIKA_ROOT}. Run git submodule update --init third_party/erika." >&2
    exit 1
fi

if [ "${CONFIGURATION}" = "Debug" ]; then
    ERIKA_CARGO_PROFILE="debug"
    ERIKA_CARGO_ARGS=()
else
    ERIKA_CARGO_PROFILE="release"
    ERIKA_CARGO_ARGS=(--release)
fi

echo "Building Erika C API from ${ERIKA_ROOT} (${ERIKA_CARGO_PROFILE})"
ERIKA_FFMPEG_HEADERS="${ERIKA_ROOT}/third_party/dist/${ERIKA_NATIVE_PROFILE}/ffmpeg/include/libavformat/avformat.h"
if [ ! -f "${ERIKA_FFMPEG_HEADERS}" ]; then
    echo "Erika native dependencies not found; building ${ERIKA_NATIVE_PROFILE} dependency profile"
    (cd "${ERIKA_ROOT}" && cargo run -p xtask -- deps build --profile "${ERIKA_NATIVE_PROFILE}" --jobs "${HOST_JOBS}")
fi

(cd "${ERIKA_ROOT}" && ERIKA_NATIVE_PROFILE="${ERIKA_NATIVE_PROFILE}" cargo build -p erika_capi "${ERIKA_CARGO_ARGS[@]}")

# 复制 dylib 到 Frameworks
cp "${BUILD_DIR}/libnipaplay_native.dylib" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"

ERIKA_DYLIB="${ERIKA_ROOT}/target/${ERIKA_CARGO_PROFILE}/liberika_capi.dylib"
ERIKA_BUNDLED_DYLIB="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/liberika_capi.dylib"
if [ ! -f "${ERIKA_DYLIB}" ]; then
    echo "error: ${ERIKA_DYLIB} was not produced by Erika build." >&2
    exit 1
fi

cp "${ERIKA_DYLIB}" "${ERIKA_BUNDLED_DYLIB}"
install_name_tool -id "@rpath/liberika_capi.dylib" "${ERIKA_BUNDLED_DYLIB}"

# Code sign the dylib (required for macOS app notarization)
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libnipaplay_native.dylib"

codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "${ERIKA_BUNDLED_DYLIB}"
