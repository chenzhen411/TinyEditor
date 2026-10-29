# TinyEditor

面向本地文本文件的轻量原生 macOS 编辑器。当前版本 **1.0.2**：简洁平直标签，修复关闭与侧边栏操作，完成跨窗口真实拖放验收。应用名 **TinyEditor**，无空格。最低 macOS 13；本次构建为 **Apple Silicon / arm64**。

- TXT、Markdown、JSON、YAML；标题栏手动选择格式并按文件路径记忆。
- AppKit 原生纯文本编辑、撤销/重做、查找/替换、逻辑行号与自动换行。
- 多窗口、多标签、标签重排/拆窗/合并、共享最近文件列表与独立窗口侧边栏。
- Markdown 默认预览，离线表格、任务列表、代码高亮、Mermaid、KaTeX 和经过过滤的 HTML。
- 预览复制映射回源码，保留 Markdown 语法、转义、实体、围栏与换行。语法选区会扩展到完整源码块；普通文本支持精确子串。
- UTF-8、UTF-8 BOM、UTF-16 LE/BE BOM、GB18030 无损读写；原子保存、外部修改保护、本地恢复草稿。
- 浅色、深色、跟随系统；全局字号缩放。无账号、无云同步，运行时不需要 Node、npm 或网络。

## 运行与安装

从 [GitHub Releases](https://github.com/chenzhen411/TinyEditor/releases) 下载 `TinyEditor-macOS-arm64.zip`，解压后将 `TinyEditor.app` 放到“应用程序”，双击运行。项目内也提供 `artifacts/TinyEditor.app`。Finder 可用“打开方式”打开文本文件，也可将文件拖到 Dock 图标。

本次应用采用 **ad hoc 本地签名**，没有 Developer ID 签名及 Apple 公证。跨机器下载时 macOS 可能要求通过系统提供的打开流程确认。

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

输出 `artifacts/TinyEditor.app`、`TinyEditor-macOS-arm64.zip` 和 `SHA256SUMS.txt`。脚本使用当前机器架构，当前为 arm64；在本机验证 macOS 13 部署标记。先在 `/tmp` 本地目录打包并签名，避免文件提供程序附加的 Finder 元数据影响签名，再复制到项目。对受限执行环境需允许系统图标工具、签名和文件协调服务运行。

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

Mermaid tiny 官方精简版不包含 mindmap、architecture 及 Mermaid 内嵌 KaTeX；文档级数学公式由独立 KaTeX 支持。渲染失败时保留可复制的原文。JSON/YAML 是词法高亮，**不是完整语法检查**。

本次实际运行环境为 macOS 27.2 arm64；macOS 13–26、Intel 和 Universal 尚未实机验收。没有自动设置为默认编辑器，也不清空用户偏好、最近记录、草稿或系统缓存。
