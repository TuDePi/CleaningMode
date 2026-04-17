#!/bin/bash
set -e

# ── Notarization credentials ──────────────────────────────────────────────────
# Fill these in before building. The .p8 file should be in this folder.
SIGN_IDENTITY="Developer ID Application: YOUR_NAME (YOUR_TEAM_ID)"
NOTARY_KEY_ID="YOUR_KEY_ID"           # e.g. ABC123DEF4
NOTARY_ISSUER_ID="YOUR_ISSUER_ID"     # e.g. 69a6de7e-xxxx-xxxx-xxxx-xxxxxxxxxxxx
NOTARY_KEY_PATH="./AuthKey_${NOTARY_KEY_ID}.p8"
# ──────────────────────────────────────────────────────────────────────────────

echo "Compiling CleaningMode..."
swiftc MacVipe.swift -o CleaningMode -framework AppKit -framework CoreGraphics

# Build in /tmp to avoid iCloud fileprovider adding xattrs
BUILD_DIR="/tmp/cleaningmode_build_$$"
mkdir -p "$BUILD_DIR"

APP_NAME="CleaningMode.app"
APP_TMP="$BUILD_DIR/$APP_NAME"
APP="$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP_TMP/Contents/MacOS"
mkdir -p "$APP_TMP/Contents/Resources"
ditto --norsrc --noextattr --noacl CleaningMode "$APP_TMP/Contents/MacOS/CleaningMode"
ditto --norsrc --noextattr --noacl AppIcon.icns "$APP_TMP/Contents/Resources/AppIcon.icns"

cat > "$APP_TMP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.cleaningmode.app</string>
    <key>CFBundleName</key>
    <string>CleaningMode</string>
    <key>CFBundleExecutable</key>
    <string>CleaningMode</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Clean up raw binary
rm -f CleaningMode


# Copy entitlements to build dir
cp entitlements.plist "$BUILD_DIR/entitlements.plist"

# Sign the app in /tmp (no iCloud interference)
echo "Signing..."
codesign --force --options runtime --timestamp \
  --entitlements "$BUILD_DIR/entitlements.plist" \
  --sign "$SIGN_IDENTITY" \
  "$APP_TMP/Contents/MacOS/CleaningMode"

codesign --force --options runtime --timestamp \
  --entitlements "$BUILD_DIR/entitlements.plist" \
  --sign "$SIGN_IDENTITY" \
  "$APP_TMP"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_TMP"

# Move signed app back to project folder
ditto --norsrc --noextattr --noacl "$APP_TMP" "$APP"

# Create DMG installer
echo "Creating DMG..."
DMG_FINAL="CleaningMode.dmg"
STAGING="dmg_staging"
VOL_NAME="CleaningMode"

rm -f "$DMG_FINAL"
rm -rf "$STAGING"

# Prepare staging folder in /tmp (avoid iCloud xattrs on staged files)
STAGING="$BUILD_DIR/staging"
mkdir -p "$STAGING/.background"
ditto --norsrc --noextattr --noacl "$APP_TMP" "$STAGING/CleaningMode.app"
ln -s /Applications "$STAGING/Applications"
ditto --norsrc --noextattr --noacl cleaningmode_dmg.png "$STAGING/.background/background.png"

# Create writable DMG
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$BUILD_DIR/CleaningMode_rw.dmg"

# Mount
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$BUILD_DIR/CleaningMode_rw.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOL_NAME"

sleep 2

# Apply Finder settings
osascript -e "
tell application \"Finder\"
    tell disk \"$VOL_NAME\"
        open
        delay 2
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 200, 900, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set text size of viewOptions to 12
        set background picture of viewOptions to file \".background:background.png\"
        set position of item \"CleaningMode.app\" of container window to {125, 170}
        set position of item \"Applications\" of container window to {375, 170}
        delay 1
        close
        open
        delay 1
        close
    end tell
end tell
"

sync
sleep 2

# Unmount
hdiutil detach "$DEVICE"

# Compress to final DMG
hdiutil convert "$BUILD_DIR/CleaningMode_rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"

# Cleanup build dir
rm -rf "$BUILD_DIR"

# Sign the DMG
echo "Signing DMG..."
codesign --sign "$SIGN_IDENTITY" "$DMG_FINAL"

# Notarize
echo "Notarizing (this takes a minute)..."
xcrun notarytool submit "$DMG_FINAL" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$NOTARY_KEY_ID" \
  --issuer "$NOTARY_ISSUER_ID" \
  --wait

# Staple
echo "Stapling..."
xcrun stapler staple "$DMG_FINAL"
xcrun stapler staple "$APP"

echo "Done!"
echo "  App:  open CleaningMode.app"
echo "  DMG:  CleaningMode.dmg (notarized)"
