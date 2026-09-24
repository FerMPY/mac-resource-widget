#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

EXECUTABLE="MacResourceWidget"          # SwiftPM product / binary name (no spaces)
APP_BUNDLE="Mac Resource Widget.app"    # installed bundle name (with spaces)

# Build each architecture separately and merge them with lipo, so the app
# runs natively on both Apple Silicon and Intel Macs. (This works with just
# the Command Line Tools, unlike a multi-arch `swift build`.)
ARCH_EXECS=()
for ARCH in arm64 x86_64; do
    echo "▶ Building Swift package (release, ${ARCH})..."
    swift build -c release --arch "${ARCH}"
    EXEC="$(swift build -c release --arch "${ARCH}" --show-bin-path)/${EXECUTABLE}"
    if [[ ! -x "${EXEC}" ]]; then
        echo "✗ Build failed — executable not found at ${EXEC}"
        exit 1
    fi
    ARCH_EXECS+=("${EXEC}")
done

echo "▶ Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

lipo -create -output "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE}" "${ARCH_EXECS[@]}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# Regenerate the icon if missing
if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "▶ Generating AppIcon.icns..."
    swift Scripts/make_icon.swift
fi
cp Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "▶ Ad-hoc code signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✓ Built ${APP_BUNDLE}"
echo ""
echo "Run it:    open \"./${APP_BUNDLE}\""
echo "Install:   mv \"${APP_BUNDLE}\" /Applications/"
