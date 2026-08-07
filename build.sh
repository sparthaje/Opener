#!/bin/bash
set -e
cd "$(dirname "$0")"

# 1. Bundle layout
rm -rf build/Opener.app
mkdir -p build/Opener.app/Contents/MacOS build/Opener.app/Contents/Resources

# 2. Resolved Info.plist (DO NOT cp the source one — it has unresolved Xcode vars)
cat > build/Opener.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>LSUIElement</key><true/>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>Opener</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>com.sparthaje.Opener</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>Opener</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHumanReadableCopyright</key><string>Copyright © 2019 sparthaje. All rights reserved.</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# 3. Icon
mkdir -p build/Opener.iconset
cp Opener/Assets.xcassets/AppIcon.appiconset/icon_*.png build/Opener.iconset/ 2>/dev/null || true
cp Opener/Assets.xcassets/AppIcon.appiconset/Icon1024.png build/Opener.iconset/icon_512x512@2x.png 2>/dev/null || true
iconutil -c icns build/Opener.iconset -o build/Opener.app/Contents/Resources/AppIcon.icns 2>/dev/null || true

# 4. Compile ISS C target -> static archive
mkdir -p build/obj
clang -c -fobjc-arc -O2 \
  -target arm64-apple-macosx11.0 \
  -IOpener/ISS/include \
  -o build/obj/ISS.o \
  Opener/ISS/ISS.c
ar rcs build/obj/libISS.a build/obj/ISS.o

# 5. Compile Swift, importing the bridging header, linking ISS + frameworks
swiftc -swift-version 5 -parse-as-library \
  -target arm64-apple-macosx11.0 \
  -module-cache-path build/cache \
  -import-objc-header Opener/ISS/Opener-Bridging-Header.h \
  -IOpener/ISS/include \
  -F/System/Library/PrivateFrameworks \
  -framework Cocoa -framework Carbon -framework ApplicationServices -framework IOKit -framework SkyLight \
  -Lbuild/obj -lISS \
  -o build/Opener.app/Contents/MacOS/Opener \
  Opener/AppDelegate.swift Opener/MonitorConfig.swift \
  Opener/WindowRouting.swift Opener/MonitorSelectionOverlay.swift

# 6. Launch
open build/Opener.app
