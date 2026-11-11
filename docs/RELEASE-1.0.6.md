TinyEditor 1.0.6（build 7），适用于 Apple Silicon / arm64，最低要求 macOS 13。

- 最近文件分两行显示文件名和路径。两行超宽时随侧边栏宽度重新截断，路径优先保留所在目录，便于区分同名文件。
- 悬停提示提供完整的文件名和路径。
- 侧边栏顶部可按文件名或完整路径实时筛选，搜索不区分大小写。

27 项针对性原生检查通过，覆盖两种栏宽下的布局、双行显示和搜索。实际窗口验证了按文件名与路径搜索、打开正确的同名文件以及清空筛选。悬停提示的文本已核对，弹出行为待鼠标实测。详见 [验证记录](https://github.com/chenzhen411/TinyEditor/blob/v1.0.6/docs/VALIDATION.md#v106-最近文件侧边栏2026-11-11)。

下载 DMG 后，将 TinyEditor.app 拖入 Applications。发布附件包含 DMG 和 SHA256SUMS.txt。安装包使用 ad hoc 本地签名，未经过 Apple 公证。[命令行下载和安装](https://github.com/chenzhen411/TinyEditor#使用-curl-下载并安装)
