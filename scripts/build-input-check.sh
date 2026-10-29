#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

# Optional acceptance driver, never included in TinyEditor.app or its distribution ZIP.
# Build BEFORE granting access. Rebuilding an ad hoc binary invalidates its old grant.
STAGING=$(mktemp -d /tmp/TinyEditor-input-check.XXXXXX)
DRIVER="$STAGING/TinyEditorInputCheck.app"
DESTINATION="$PWD/artifacts/TestSupport/TinyEditorInputCheck.app"
mkdir -p "$DRIVER/Contents/MacOS" "$(dirname "$DESTINATION")"
cat > "$DRIVER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>top.moriarty.TinyEditor.InputCheck</string>
<key>CFBundleName</key><string>TinyEditor Input Check</string>
<key>CFBundleDisplayName</key><string>TinyEditor Input Check</string>
<key>CFBundleExecutable</key><string>InputCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
CLANG_MODULE_CACHE_PATH=/tmp/tinyeditor-module-cache swiftc -O \
  -module-cache-path /tmp/tinyeditor-module-cache scripts/cg-input.swift \
  -o "$DRIVER/Contents/MacOS/InputCheck"
codesign --force --sign - "$DRIVER"
ditto --norsrc --noextattr "$DRIVER" "$DESTINATION"
sleep 1
xattr -d com.apple.FinderInfo "$DESTINATION" 2>/dev/null || true
codesign --verify --strict --verbose=2 "$DESTINATION"
# Temporary-directory apps are not reliably resolved by TCC through Launch Services.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINATION"
echo "$DESTINATION"
echo 'This build does not change system permissions. Authorize through the native UI only with explicit user consent.'
