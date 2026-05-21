#!/usr/bin/env bash
# Builds MacResourceWidget.app and packages it into a drag-to-install DMG.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MacResourceWidget"
APP_BUNDLE="${APP_NAME}.app"
VOL_NAME="Mac Resource Widget"
DMG="${APP_NAME}.dmg"

# 1. Build the .app
./build.sh

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "✗ ${APP_BUNDLE} not found — build failed"
    exit 1
fi

# 2. Stage a folder with the app and an /Applications shortcut
echo "▶ Staging DMG contents..."
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp -R "${APP_BUNDLE}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

# 3. Build a compressed DMG
echo "▶ Creating ${DMG}..."
rm -f "${DMG}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGE}" \
    -ov -format UDZO \
    "${DMG}" >/dev/null

echo "✓ Built ${DMG}"
echo ""
echo "Distribute this file. To install, the user opens it and drags"
echo "${APP_BUNDLE} onto the Applications shortcut."
echo ""
echo "Note: the app is ad-hoc signed (no Apple Developer ID), so on first"
echo "launch macOS Gatekeeper will block it. The user must right-click the"
echo "app → Open, or allow it under System Settings → Privacy & Security."
