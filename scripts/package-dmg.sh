#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$#" -ne 1 ] || [ ! -d "$1/Contents/MacOS" ]; then
  echo 'Usage: scripts/package-dmg.sh /absolute/path/TinyEditor.app' >&2
  exit 1
fi
source_app="$1"
architecture="$(lipo -archs "$source_app/Contents/MacOS/TinyEditor")"
case "$architecture" in
  arm64|x86_64) ;;
  'arm64 x86_64'|'x86_64 arm64') architecture=universal ;;
  *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
staging="$(mktemp -d /tmp/TinyEditor-dmg.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/content" artifacts
ditto --norsrc --noextattr "$source_app" "$staging/content/TinyEditor.app"
codesign --verify --deep --strict --verbose=2 "$staging/content/TinyEditor.app"
ln -s /Applications "$staging/content/Applications"
cat > "$staging/content/安装说明.txt" <<'EOF'
TinyEditor 安装说明

1. 如已运行旧版，请保存文档并按 ⌘Q 正常退出。
2. 将 TinyEditor.app 拖入 Applications（应用程序）。更新时可先备份旧版应用。
3. 从“应用程序”打开 TinyEditor，然后推出磁盘映像。

需要 macOS 13 或以上，处理器架构以 DMG 文件名为准。
本应用使用 ad hoc 本地签名，未进行 Developer ID 签名或 Apple 公证。
源码、下载与命令安装说明：https://github.com/chenzhen411/TinyEditor
EOF
filename="TinyEditor-macOS-${architecture}.dmg"
hdiutil create -volname TinyEditor -srcfolder "$staging/content" -fs HFS+ -format UDZO "$staging/$filename"
hdiutil verify "$staging/$filename"
mv "$staging/$filename" "artifacts/$filename"
(cd artifacts && shasum -a 256 "$filename" > SHA256SUMS.txt)
echo "Packaged: artifacts/$filename"
