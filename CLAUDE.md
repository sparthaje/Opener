# Building Opener

This machine has **no Xcode** — builds go through `swiftc`/`clang` directly. Do **not** invoke `xcodebuild`.

## Pitfall: Info.plist

`Opener/Info.plist` contains Xcode build variables (`$(EXECUTABLE_NAME)`, `$(PRODUCT_BUNDLE_IDENTIFIER)`, …) that only `xcodebuild` resolves. Copying it as-is into the bundle leaves the variables as literal strings and macOS refuses to launch the app ("may be damaged or incomplete"). Always write a **resolved** Info.plist into the bundle (the script below does this).

## Build script

```bash
set -e
cd "$(dirname "$0")"

# 1. Bundle layout
rm -rf build/Opener.app
mkdir -p build/Opener.app/Contents/MacOS build/Opener.app/Contents/Resources

# 2. Resolved Info.plist (DO NOT cp the source one)
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
  -framework Cocoa -framework Carbon -framework ApplicationServices -framework IOKit \
  -Lbuild/obj -lISS \
  -o build/Opener.app/Contents/MacOS/Opener \
  Opener/AppDelegate.swift Opener/MonitorConfig.swift

# 6. Launch
open build/Opener.app
```

Save it as `build.sh`, `chmod +x build.sh`, run `./build.sh`.

## Source layout

- `Opener/AppDelegate.swift` — settings parsing, hotkey dispatch, overlay panel.
- `Opener/MonitorConfig.swift` — display-UUID + monitor-config helpers.
- `Opener/ISS/` — vendored from `example/InstantSpaceSwitcher`. Provides instant Mission Control space switching by posting Dock-swipe `CGEvent`s.
  - `ISS.c`, `include/ISS.h` — C engine. Public Swift-callable surface includes `iss_init`, `iss_destroy`, `iss_switch_to_space_on_display(uuid, index)`.
  - `Opener-Bridging-Header.h` — Swift bridging import.

## `.opener_settings` format

Line-based, lives at `~/.opener_settings`. Pre-section content keeps the legacy meaning (line 1 = hotkey, line 2 = `true|false` panel toggle, then `letter:value` bindings). New section header `[monitor:<configID>]` scopes its bindings to that monitor configuration. The active section's bindings shadow globals for the same letter.

A monitor configuration is the sorted, `+`-joined list of all attached displays' `CGDisplayCreateUUIDFromDisplayID` strings. When Opener launches into a config it has not seen, it appends a commented template section automatically.

Binding values:
- `letter:/abs/path` — open via `NSWorkspace`.
- `letter:space:<displayUUID>:<index0Based>` — switch to that space on that display via ISS. Cursor is briefly warped to the target display while the gesture posts.
