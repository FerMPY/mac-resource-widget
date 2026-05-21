#!/usr/bin/env bash
# Builds the app and packages it into a styled, drag-to-install DMG.
set -euo pipefail

cd "$(dirname "$0")"

APP_BUNDLE="Mac Resource Widget.app"
VOL_NAME="Mac Resource Widget"
DMG="MacResourceWidget.dmg"
BG_SRC="Resources/dmg-background.tiff"

# Force-detach any leftover volumes from earlier runs (or the user opening
# a previous DMG), so the new image mounts under the exact expected name.
detach_stale() {
    for v in "/Volumes/${VOL_NAME}"*; do
        [[ -e "$v" ]] || continue
        hdiutil detach "$v" -force >/dev/null 2>&1 || true
    done
}

# 1. Build the app
./build.sh
[[ -d "${APP_BUNDLE}" ]] || { echo "✗ ${APP_BUNDLE} not found — build failed"; exit 1; }

# 2. Regenerate the DMG background if missing
if [[ ! -f "${BG_SRC}" ]]; then
    echo "▶ Generating DMG background..."
    swift Scripts/make_dmg_background.swift
fi

# 3. Stage the DMG contents
echo "▶ Staging DMG contents..."
STAGE="$(mktemp -d)"
RW_DIR="$(mktemp -d)"
trap 'detach_stale; rm -rf "${STAGE}" "${RW_DIR}"' EXIT
cp -R "${APP_BUNDLE}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"
cp "${BG_SRC}" "${STAGE}/.background.tiff"

# 4. Create a read-write DMG
detach_stale
RW_DMG="${RW_DIR}/rw.dmg"
hdiutil create -srcfolder "${STAGE}" -volname "${VOL_NAME}" \
    -fs HFS+ -format UDRW -ov "${RW_DMG}" >/dev/null

# 5. Mount it and read back the real device + mount point.
# (Not -nobrowse: Finder must see the volume to style it via AppleScript.)
echo "▶ Styling DMG window..."
ATTACH="$(hdiutil attach "${RW_DMG}" -noautoopen -noverify)"
DEVICE="$(echo "${ATTACH}" | grep -E '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="$(echo "${ATTACH}" | sed -nE 's/.*(\/Volumes\/.*)$/\1/p' | head -1)"
VOL="$(basename "${MOUNT}")"

# Hide the background file so it never shows as an item.
chflags hidden "${MOUNT}/.background.tiff"

# Give Finder a moment to register the freshly mounted volume.
sleep 2

# 6. Lay out the window with Finder
osascript <<EOF
tell application "Finder"
    tell disk "${VOL}"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 548}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background.tiff"
        set position of item "${APP_BUNDLE}" of container window to {155, 175}
        set position of item "Applications" of container window to {445, 175}
        -- Tuck the (hidden) background file away. Wrapped in try because
        -- Finder omits it when hidden files aren't being shown.
        try
            set position of item ".background.tiff" of container window to {300, 300}
        end try
        update without registering applications
        delay 3
        close
    end tell
end tell
EOF

sync
sleep 1

# Strip macOS bookkeeping folders so the volume is clean even when the
# user has "show hidden files" enabled.
rm -rf "${MOUNT}/.fseventsd" "${MOUNT}/.Trashes" "${MOUNT}/.TemporaryItems" 2>/dev/null || true
sync

# 7. Detach and compress
hdiutil detach "${DEVICE}" -force >/dev/null
rm -f "${DMG}"
hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG}" >/dev/null

echo "✓ Built ${DMG}"
echo ""
echo "To install, the user opens ${DMG} and drags the app onto Applications."
echo ""
echo "Note: the app is ad-hoc signed (no Apple Developer ID), so first launch"
echo "is blocked by Gatekeeper — right-click the app → Open to allow it."
