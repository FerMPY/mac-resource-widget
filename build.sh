#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MacResourceWidget"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build"

echo "▶ Building Swift package (release)..."
swift build -c release --arch arm64

BIN_PATH=$(swift build -c release --arch arm64 --show-bin-path)
EXEC="${BIN_PATH}/${APP_NAME}"

if [[ ! -x "${EXEC}" ]]; then
    echo "✗ Build failed — executable not found at ${EXEC}"
    exit 1
fi

echo "▶ Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${EXEC}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

# Regenerate icon if missing
if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "▶ Generating AppIcon.icns..."
    swift Scripts/make_icon.swift
fi
cp Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

echo "▶ Ad-hoc code signing..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✓ Built ${APP_BUNDLE}"
echo ""
echo "Run it:    open ./${APP_BUNDLE}"
echo "Install:   mv ${APP_BUNDLE} /Applications/"
