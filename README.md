# TinyEditor

面向本地文本文件的轻量原生 macOS 编辑器。当前版本 **1.0.5**：新增 Shell（`.sh`）和 SQL（`.sql`）的自动识别、手动格式选择与词法高亮。应用名 **TinyEditor**，无空格。最低 macOS 13；本次构建为 **Apple Silicon / arm64**。

仓库现已公开：[chenzhen411/TinyEditor](https://github.com/chenzhen411/TinyEditor)。现有 Release 为预发布包，采用 ad hoc 签名；Developer ID 正式签名与 Apple 公证尚未完成，所需条件见 [签名发行说明](docs/SIGNING.md)。

- TXT、Markdown、JSON、YAML、Shell、SQL；标题栏手动选择格式并按文件路径记忆。
- AppKit 原生纯文本编辑、撤销/重做、查找/替换、逻辑行号与自动换行。
- 多窗口、多标签、标签重排/拆窗/合并、共享最近文件列表与独立窗口侧边栏。
- Markdown 默认预览，离线表格、任务列表、代码高亮、Mermaid、KaTeX 和经过过滤的 HTML。
- 预览复制映射回源码，保留 Markdown 语法、转义、实体、围栏与换行。语法选区会扩展到完整源码块；普通文本支持精确子串。
- UTF-8、UTF-8 BOM、UTF-16 LE/BE BOM、GB18030 无损读写；原子保存、外部修改保护、本地恢复草稿。
- 浅色、深色、跟随系统；全局字号缩放。无账号、无云同步，运行时不需要 Node、npm 或网络。

## 运行与安装

从 [GitHub Releases](https://github.com/chenzhen411/TinyEditor/releases/tag/v1.0.5) 下载 `TinyEditor-macOS-arm64.dmg`，打开后将 `TinyEditor.app` 拖入 `Applications`。如已安装旧版，先保存文档并按 ⌘Q 正常退出。项目内也提供 `artifacts/TinyEditor.app`。Finder 可用“打开方式”打开文本文件，也可将文件拖到 Dock 图标。

本次应用采用 **ad hoc 本地签名**，没有 Developer ID 签名及 Apple 公证。跨机器下载时 macOS 可能要求通过系统提供的打开流程确认。

### 使用 curl 下载并安装

以下命令适用于 Apple Silicon，安装至 `/Applications/TinyEditor.app`。如已有同名应用，先将其移动到用户目录的安装备份中，保留偏好、最近记录和恢复草稿。如果“应用程序”目录不可写，请使用上面的 Finder 拖入方式，由系统处理权限。

```sh
(
  set -e
  if [ "$(uname -m)" != arm64 ]; then
    echo '此安装包适用于 Apple Silicon。' >&2
    exit 1
  fi
  if pgrep -x TinyEditor >/dev/null; then
    echo '请先保存文档并按 ⌘Q 退出 TinyEditor，再运行安装命令。' >&2
    exit 1
  fi
  tinyeditor_tmp="$(mktemp -d)"
  tinyeditor_url='https://github.com/chenzhen411/TinyEditor/releases/download/v1.0.5'
  curl -fL --retry 3 "$tinyeditor_url/TinyEditor-macOS-arm64.dmg" -o "$tinyeditor_tmp/TinyEditor-macOS-arm64.dmg"
  curl -fL --retry 3 "$tinyeditor_url/SHA256SUMS.txt" -o "$tinyeditor_tmp/SHA256SUMS.txt"
  (cd "$tinyeditor_tmp" && shasum -a 256 -c SHA256SUMS.txt)
  tinyeditor_mount="$tinyeditor_tmp/volume"
  mkdir "$tinyeditor_mount"
  hdiutil attach -readonly -nobrowse -mountpoint "$tinyeditor_mount" "$tinyeditor_tmp/TinyEditor-macOS-arm64.dmg"
  trap 'hdiutil detach "$tinyeditor_mount" >/dev/null 2>&1 || true' EXIT
  codesign --verify --deep --strict "$tinyeditor_mount/TinyEditor.app"
  if [ -e /Applications/TinyEditor.app ]; then
    tinyeditor_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/TinyEditor.app/Contents/Info.plist)"
    [ "$tinyeditor_id" = top.moriarty.TinyEditor ] || exit 1
    tinyeditor_backup="$HOME/Library/Application Support/TinyEditor/InstallBackups/$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$tinyeditor_backup"
    mv /Applications/TinyEditor.app "$tinyeditor_backup/TinyEditor.app"
    echo "旧版已备份至：$tinyeditor_backup/TinyEditor.app"
  fi
  ditto "$tinyeditor_mount/TinyEditor.app" /Applications/TinyEditor.app
  codesign --verify --deep --strict /Applications/TinyEditor.app
  open /Applications/TinyEditor.app
)
```

下载文件保留在命令创建的临时目录；DMG 会自动推出。此流程不删除隔离标记，也不修改系统安全设置。

```sh
open artifacts/TinyEditor.app
# 命令行复用同一主进程
artifacts/TinyEditor.app/Contents/MacOS/TinyEditor --new-tab /absolute/path/file.md
artifacts/TinyEditor.app/Contents/MacOS/TinyEditor --new-window
```

远程图片默认关闭，可在“显示 → 允许远程图片”开启。本地图片限制在文档目录下，支持位图；为约束读取范围，不内嵌本地 SVG。尚未保存的文档无法解析相对资源。

冲突发生时可以保留当前编辑并另存为其他文件，或重新载入磁盘版本；保留后不能直接覆盖冲突文件。重命名移动原文件，不会先保存当前编辑。

## 构建

需要 macOS 与 Swift 5.9+ / Command Line Tools。普通构建无需下载依赖：所有预览资源已提交。

```sh
./scripts/build.sh
```

输出 `artifacts/TinyEditor.app`、`TinyEditor-macOS-arm64.dmg` 和 `SHA256SUMS.txt`，不再生成 ZIP 分发包。脚本使用当前机器架构，当前为 arm64；在本机验证 macOS 13 部署标记。先在 `/tmp` 本地目录打包并签名，避免文件提供程序附加的 Finder 元数据影响签名，再复制到项目。对受限执行环境需允许系统图标工具、签名和磁盘映像服务运行。

此机器只有 Command Line Tools。Swift 6.4 的默认构建后端在当前受限环境生成 dSYM 失败，因此脚本明确使用 SwiftPM native 后端；该选项已被此工具链标为 deprecated，未来工具链移除时需迁移构建入口。

更新离线库时才需要 Node/npm：

```sh
npm ci --prefix scripts --ignore-scripts
node scripts/vendor.mjs
./scripts/build.sh
```

固定版本与校验摘要在 `scripts/package-lock.json`，许可证在 `Resources/THIRD_PARTY_NOTICES.md`。本机图标源文件为 `Resources/Icons/TinyEditor.svg`，可重复生成脚本为 `scripts/icon.swift`。

## 验证

```sh
./scripts/test-core.sh
python3 scripts/test-integration.py
python3 scripts/measure-startup.py
python3 scripts/verify-distribution.py
```

集成检查将创建隔离测试窗口，完成后检查正常退出。测试前先正常退出当前 TinyEditor，保护未保存内容；整个过程不改变 bundle ID。核心检查无需完整 Xcode；另保留 `Tests/TinyEditorTests` 供有 XCTest 的完整 Xcode 环境运行。

自动状态检查、真实 GUI 操作、性能口径和未验证范围详见 [验证记录](docs/VALIDATION.md)，架构见 [ARCHITECTURE.md](docs/ARCHITECTURE.md)。不要把自动文档移动检查当作全部鼠标拖放组合已验收。

1.0.2 的四种跨窗口组合、正文/预览/工具栏/侧边栏/状态栏放下、拖出拆窗、重排及 Escape 已使用用户授权的真实系统事件验收，见 [交互回归记录](docs/DRAG-REGRESSION-1.0.2.md)。独立输入测试驱动不随应用分发，临时系统权限已撤销。

1.0.3 将标签栏、正文和状态栏放在同一个右侧文档区域；侧边栏展开、收起或调宽时三者同步调整。验证见 [侧边栏布局记录](docs/LAYOUT-1.0.3.md)。

## 快捷键

| 功能 | 快捷键 |
|---|---|
| 新建窗口 / 标签 | ⌘N / ⌘T |
| 打开 / 关闭标签 | ⌘O / ⌘W |
| 保存 / 另存为 | ⌘S / ⌘⇧S |
| 撤销 / 重做 | ⌘Z / ⌘⇧Z |
| 查找 / 替换 | ⌘F / ⌥⌘F |
| Markdown 预览 / 编辑 | ⌘⇧P |
| 最近文件侧边栏 | ⌃⌘S |
| 复制整个文档源码 | ⌘⇧C |
| 放大 / 缩小 / 重置 | ⌘+（兼容 ⌘=） / ⌘− / ⌘0 |
| 上一个 / 下一个标签 | ⌘⇧[ / ⌘⇧] |
| 退出 | ⌘Q |

## 大文件与范围

多行文件使用 TextKit 1 非连续排版和可见范围词法高亮。超过 100,000 UTF-16 单元的逻辑行采用约 32,768 单元的原生分段视图，避免整条巨型段落阻塞编辑。条带显示当前位置，可前后翻段；查找/替换、保存、全选复制针对完整原文，跨段撤销保留。鼠标连续选择局限于当前分段。列号以 UTF-16 位置计数。

Mermaid tiny 官方精简版不包含 mindmap、architecture 及 Mermaid 内嵌 KaTeX；文档级数学公式由独立 KaTeX 支持。渲染失败时保留可复制的原文。JSON、YAML、Shell 和 SQL 使用轻量词法高亮，**不是完整语法检查**。Shell 支持常见控制关键字、变量、字符串、注释；SQL 支持常见关键字、数字、参数、引号标识符及行/块注释。高亮按可见范围及有限上下文工作，不保证复杂 Shell here-document、所有 SQL 方言或超长跨屏词法单元的完整解析。

本次实际运行环境为 macOS 27.2 arm64；macOS 13–26、Intel 和 Universal 尚未实机验收。没有自动设置为默认编辑器，也不清空用户偏好、最近记录、草稿或系统缓存。

1.0.4 按参考图重做圆角标签，浅色/深色分别适配；真实点击与回归范围见 [标签样式记录](docs/TABS-1.0.4.md)。

1.0.5 新增 `.sh` / `.sql` 源码模式，保留原文、换行、撤销和按路径记忆的格式覆盖，详见 [Shell/SQL 验证记录](docs/SHELL-SQL-1.0.5.md)。
