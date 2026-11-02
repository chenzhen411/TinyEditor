TinyEditor 1.0.5（build 6），Apple Silicon / arm64，最低部署 macOS 13。

正式 Release（Latest）。2026-11-02 从预发布提升为正式发行，沿用原有 DMG 和校验和；应用内容、签名及既有验证结果保持不变。

新增 Shell（.sh）和 SQL（.sql）源码支持：按扩展名自动识别，标题栏可手动选择并按文件路径记忆；提供行号、轻量词法高亮和原生文本编辑。Shell 高亮常见关键字、变量、字符串及注释；SQL 高亮常见关键字、参数、数字、引号标识符和行/块注释。文件始终保存为原始纯文本。

3,089 条核心断言、97 项原生集成检查通过。覆盖两种新格式的编辑、撤销/重做、保存重开与高亮；另验证 .sh 保存后保留可执行权限和 CRLF。真实鼠标/键盘复核了两种模式的显示、Shell 编辑保存，以及 .txt 手动选择 SQL 后关闭重开恢复。

仅提供 DMG 安装包和 SHA256SUMS.txt，挂载、安装复制、严格代码签名及离线资源检查通过。本地 ad hoc 签名，未进行 Developer ID 签名或 Apple 公证。

```sh
curl -fL --retry 3 -o TinyEditor-macOS-arm64.dmg https://github.com/chenzhen411/TinyEditor/releases/download/v1.0.5/TinyEditor-macOS-arm64.dmg
curl -fL --retry 3 -o SHA256SUMS.txt https://github.com/chenzhen411/TinyEditor/releases/download/v1.0.5/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
open TinyEditor-macOS-arm64.dmg
```

保存文档并正常退出旧版后，将应用拖入 Applications。完整命令安装流程见 [README](https://github.com/chenzhen411/TinyEditor#使用-curl-下载并安装)。两种新模式均为词法着色，不提供脚本执行、数据库连接或完整语法校验；复杂 here-document、所有 SQL 方言和超长跨屏词法单元不保证完整解析。
