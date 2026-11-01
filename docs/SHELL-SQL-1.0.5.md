# Shell / SQL 支持验收（2026-11-01）

v1.0.5 / build 6 增加 Shell 和 SQL 两种格式。Format 追加新枚举值，保留既有 rawValue 及菜单顺序；自动识别 .sh / .sql（不区分大小写），手动选择覆盖后缀并沿用既有按路径保存和重命名迁移机制。应用文件类型声明增加 Shell 与 SQL，SQL 使用本应用导出的纯文本源码 UTI，未将本应用设置为系统默认编辑器。

ScriptHighlighting 对两种模式分别缓存一份合并词法表达式。注释、字符串和引号标识符作为整体消费，避免内部关键字再次被着色。新模式沿用 TextKit 临时前景色、可见范围及有限上下文（至多 100,000 个 UTF-16 单元），不向存储写入富文本属性，不注册高亮撤销。没有新增依赖、解释器或数据库运行时。

## 自动结果

- `./scripts/test-core.sh`：12 个用例 / 3,089 条断言，0 失败。新增扩展名大小写、手动覆盖、UTF-16/emoji 位置、注释与字符串优先级、SQL 大小写和转义引号、未结束块注释、格式偏好落盘与重命名迁移检查。.sh 原子保存后权限仍为 0755，中文/emoji 原文和 CRLF 不变。
- `python3 scripts/test-integration.py`：97 项通过，normalExit=true / exitCode=0。六种源码模式均执行输入、撤销回干净状态、重做、保存重开和逻辑行号检查；Shell / SQL 另检查临时高亮、原文/修改状态/撤销栈不变、格式菜单和无预览切换控件。
- `./scripts/build.sh` 与 `python3 scripts/verify-distribution.py`：Release / arm64 / macOS 13 部署目标；DMG 镜像、挂载后的严格签名、安装复制后的签名、资源引用及测试驱动排除检查通过。实际摘要与大小在 distribution-results.json。

## 真实界面

使用 CUA 的鼠标/键盘与原生截图，测试数据和偏好位于 `/tmp/TinyEditor-105-gui`：

1. 打开 sample.sh 与 query.sql，状态栏分别显示 Shell / SQL；都显示行号，不创建 Markdown 预览。截图可见关键字、字符串、注释及 SQL 参数的区分。
2. sample.sh 输入 `# GUI 编辑验证`，出现修改圆点；⌘Z 撤销后圆点消失；⌘⇧Z 重做，再 ⌘S 保存。磁盘字节读取确认保存包含新增注释。
3. wrong.txt 初始为纯文本；标题栏菜单含 Shell 和 SQL，点击 SQL 后立即对当前原文着色，没有修改圆点。关闭标签后通过原生打开面板重开，标题栏与状态栏仍为 SQL，磁盘内容不变。
4. 正常退出隔离实例，将 DMG 中的同一 v1.0.5 应用安装到 /Applications 并正常打开。旧应用包移入 /tmp 备份；未清空或覆盖用户偏好、最近记录和恢复存储。实测记录见 evidence/1.0.5-shell-sql-gui.json。

此次没有重新授予测试输入驱动权限，也没有重跑完整真实跨窗口拖拽矩阵。macOS 13–26 / Intel / Universal 仍需额外硬件验证。Shell here-document、各 SQL 方言及超长跨屏注释/字符串只提供有限词法上下文，不宣称完整语言解析、语法校验或执行能力。
