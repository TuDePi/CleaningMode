#!/bin/bash
set -e

echo "Compiling CleaningMode..."
swiftc MacVipe.swift -o CleaningMode -framework AppKit -framework CoreGraphics

# Create .app bundle
APP="CleaningMode.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp CleaningMode "$APP/Contents/MacOS/"
cp AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" << 'PLIST'
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

# Create DMG installer
echo "Creating DMG..."
DMG_FINAL="CleaningMode.dmg"
STAGING="dmg_staging"
VOL_NAME="CleaningMode"

rm -f "$DMG_FINAL"
rm -rf "$STAGING"

# Prepare staging folder
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp cleaningmode_dmg.png "$STAGING/.background/background.png"

# Create writable DMG
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "CleaningMode_rw.dmg"

# Mount
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "CleaningMode_rw.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')
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
hdiutil convert "CleaningMode_rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"

# Cleanup
rm -f "CleaningMode_rw.dmg"
rm -rf "$STAGING"

echo "Done!"
echo "  App:  open CleaningMode.app"
echo "  DMG:  CleaningMode.dmg"
