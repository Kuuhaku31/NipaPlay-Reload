#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CPP_NATIVE_DIR="$(dirname "$SCRIPT_DIR")"
NIPAPLAY_ROOT="$(cd "${CPP_NATIVE_DIR}/.." && pwd)"
KUROKO_ROOT="${KUROKO_ROOT:-${NIPAPLAY_ROOT}/third_party/kuroko}"
KUROKO_NATIVE_PROFILE="${KUROKO_NATIVE_PROFILE:-lgpl}"
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

if [ ! -f "${KUROKO_ROOT}/Cargo.toml" ]; then
    echo "error: Kuroko source not found at ${KUROKO_ROOT}. Run git submodule update --init third_party/kuroko." >&2
    exit 1
fi

if [ "${CONFIGURATION}" = "Debug" ]; then
    KUROKO_CARGO_PROFILE="debug"
    KUROKO_CARGO_ARGS=()
else
    KUROKO_CARGO_PROFILE="release"
    KUROKO_CARGO_ARGS=(--release)
fi

echo "Building Kuroko C API from ${KUROKO_ROOT} (${KUROKO_CARGO_PROFILE})"
KUROKO_FFMPEG_HEADERS="${KUROKO_ROOT}/third_party/dist/${KUROKO_NATIVE_PROFILE}/ffmpeg/include/libavformat/avformat.h"
if [ ! -f "${KUROKO_FFMPEG_HEADERS}" ]; then
    echo "Kuroko native dependencies not found; building ${KUROKO_NATIVE_PROFILE} dependency profile"
    (cd "${KUROKO_ROOT}" && cargo run -p xtask -- deps build --profile "${KUROKO_NATIVE_PROFILE}" --jobs "${HOST_JOBS}")
fi

(cd "${KUROKO_ROOT}" && KUROKO_NATIVE_PROFILE="${KUROKO_NATIVE_PROFILE}" cargo build -p kuroko_capi "${KUROKO_CARGO_ARGS[@]}")

# 复制 dylib 到 Frameworks
cp "${BUILD_DIR}/libnipaplay_native.dylib" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/"

KUROKO_DYLIB="${KUROKO_ROOT}/target/${KUROKO_CARGO_PROFILE}/libkuroko_capi.dylib"
KUROKO_BUNDLED_DYLIB="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libkuroko_capi.dylib"
if [ ! -f "${KUROKO_DYLIB}" ]; then
    echo "error: ${KUROKO_DYLIB} was not produced by Kuroko build." >&2
    exit 1
fi

cp "${KUROKO_DYLIB}" "${KUROKO_BUNDLED_DYLIB}"
install_name_tool -id "@rpath/libkuroko_capi.dylib" "${KUROKO_BUNDLED_DYLIB}"

# Code sign the dylib (required for macOS app notarization)
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" \
    "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/libnipaplay_native.dylib"

codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "${KUROKO_BUNDLED_DYLIB}"
