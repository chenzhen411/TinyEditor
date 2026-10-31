#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/tinyeditor-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --build-system native --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security -c release
swift scripts/icon.swift Resources/Icons
iconutil -c icns Resources/Icons/TinyEditor.iconset -o Resources/Icons/TinyEditor.icns
STAGING="$(mktemp -d /tmp/TinyEditor-build.XXXXXX)"
APP="$STAGING/TinyEditor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TinyEditor "$APP/Contents/MacOS/TinyEditor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Icons/TinyEditor.icns "$APP/Contents/Resources/TinyEditor.icns"
ditto Resources/Preview "$APP/Contents/Resources/Preview"
cp Resources/THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
./scripts/package-dmg.sh "$APP"
ditto --norsrc --noextattr "$APP" artifacts/TinyEditor.app
sleep 1
for attempt in {1..20}; do
  xattr -d com.apple.FinderInfo artifacts/TinyEditor.app 2>/dev/null || true
  if codesign --verify --deep --strict --verbose=2 artifacts/TinyEditor.app; then break; fi
  if [ "$attempt" -eq 20 ]; then exit 1; fi
  sleep 0.5
done
du -sh artifacts/TinyEditor.app artifacts/TinyEditor-macOS-*.dmg
