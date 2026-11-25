#!/bin/zsh
# Builds Notchcord.app.
#   ./build.sh                 release build into build/Notchcord.app
#   ./build.sh --install       ...and copy it to /Applications
#   ./build.sh --install --open
#   ./build.sh --debug ...     debug build (Web Inspector + debug bridge)
#   ./build.sh --zip           ...and create build/Notchcord.zip for distribution
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release; INSTALL=0; OPEN=0; ZIP=0
for a in "$@"; do
  case $a in
    --debug) CONFIG=debug ;;
    --install) INSTALL=1 ;;
    --open) OPEN=1; INSTALL=1 ;;
    --zip) ZIP=1 ;;
    *) echo "unknown option: $a"; exit 1 ;;
  esac
done

VERSION=$(cat VERSION 2>/dev/null || echo 1.0.0)
swift build -c $CONFIG --arch arm64 --arch x86_64
BIN=$(swift build -c $CONFIG --arch arm64 --arch x86_64 --show-bin-path)/Notchcord

APP=build/Notchcord.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notchcord"

if [[ ! -f build/AppIcon.icns ]]; then
  ICONSET=build/AppIcon.iconset; rm -rf $ICONSET; mkdir -p $ICONSET
  swift tools/icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Notchcord</string>
  <key>CFBundleDisplayName</key><string>Notchcord</string>
  <key>CFBundleIdentifier</key><string>io.github.notchcord</string>
  <key>CFBundleExecutable</key><string>Notchcord</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

codesign --force --deep -s - "$APP"
echo "built: $APP ($CONFIG, v$VERSION)"

if (( ZIP )); then
  rm -f build/Notchcord.zip
  ditto -c -k --keepParent "$APP" build/Notchcord.zip
  echo "zip: build/Notchcord.zip"
fi

if (( INSTALL )); then
  pkill -x Notchcord 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Notchcord.app
  cp -R "$APP" /Applications/Notchcord.app
  echo "installed: /Applications/Notchcord.app"
  (( OPEN )) && open /Applications/Notchcord.app
fi
exit 0
