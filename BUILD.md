# Building Opener without Xcode

This project has no Xcode installed — it builds with `swiftc` directly.

## Pitfall: Info.plist

**Do NOT copy `Opener/Info.plist` into the app bundle.** The source plist contains
Xcode build variables (`$(EXECUTABLE_NAME)`, `$(PRODUCT_BUNDLE_IDENTIFIER)`, etc.)
that are only resolved by `xcodebuild`. Copying it as-is into the `.app` bundle
leaves the variables as literal strings, and macOS will refuse to launch the app
with "may be damaged or incomplete."

Instead, write a resolved Info.plist with hardcoded values into the bundle. See
the build section in README.md for the full script.

## Build command

```bash
# 1. Create bundle structure
mkdir -p build/Opener.app/Contents/MacOS build/Opener.app/Contents/Resources

# 2. Write resolved Info.plist (DO NOT cp from source)
cat > build/Opener.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>LSUIElement</key>
	<true/>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Opener</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.sparthaje.Opener</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Opener</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2019 sparthaje. All rights reserved.</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# 3. Build icons
mkdir -p build/Opener.iconset
cp Opener/Assets.xcassets/AppIcon.appiconset/icon_*.png build/Opener.iconset/
cp Opener/Assets.xcassets/AppIcon.appiconset/Icon1024.png build/Opener.iconset/icon_512x512@2x.png
iconutil -c icns build/Opener.iconset -o build/Opener.app/Contents/Resources/AppIcon.icns

# 4. Compile
swiftc -swift-version 5 -parse-as-library -framework Cocoa -framework Carbon \
  -target arm64-apple-macosx11.0 -module-cache-path build/cache \
  -o build/Opener.app/Contents/MacOS/Opener Opener/AppDelegate.swift Opener/WindowOverlay.swift

# 5. Launch
open build/Opener.app
```
