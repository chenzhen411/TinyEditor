# TinyEditor 本机验证

本次实现与图标均在当前 Mac 独立生成，没有从另一台 Mac 取得代码或应用资源。环境为 macOS 27.2（26B123）、Apple Silicon arm64、Swift 6.4，应用最低部署版本为 macOS 13。

验证分为自动数据检查、实际 AppKit/WebKit 集成检查、真实 GUI 操作、性能实测和未验证兼容范围。不存在“全部人工验收通过”的声明。

当前版本 1.0.2 / build 3：76 项集成检查正常退出；完整单/多标签真实拖放矩阵与标签样式验收见 [1.0.2 回归记录](DRAG-REGRESSION-1.0.2.md) 和 real-drag-results.json。既有启动测量为历史数据，本轮性能以最新 integration-results.json 为准。

## 自动证据

- `core-results.json`：核心数据保护与随机增量行索引，9 个用例、3,061 条断言。
- `integration-results.json`：原生编辑/保存/撤销、源码模式、离线渲染、系统剪贴板、窗口间文档移动、超长行分页、组合文本、并发 IPC、不同安装路径。
- `prototype-results.json`：第一阶段关键原型结果；后续以最终集成报告为准。
- `launch-results.json`：新 GUI 进程启动、首次就绪、主进程 RSS 和新 WebKit 辅助进程。
- `distribution-results.json`：发布架构、最低系统、签名、ZIP、离线资源和文件摘要。
- [真实 GUI 记录](GUI-VALIDATION.md)：鼠标/键盘实测及工具受限项目。

## 需求到证据

| # | 验收要求 | 实际证据与边界 |
|---|---|---|
| 1 | 四种格式输入、高亮、保存、撤销、重开 | 集成 native-*-edit/undo/redo/save-reopen；代码块高亮计数。源码词法高亮按可见范围实现；四种高亮配色未逐一人工截图 |
| 2 | Markdown 默认预览与未保存切换 | markdown-default-preview / markdown-memory-latest；GUI 输入并切换可见 |
| 3 | 各类预览原文复制 | preview-copy-*、CRLF 全选、精确普通文本子串；语法选区保守扩展完整源码块 |
| 4 | 实际剪贴板纯文本 | 原生读取 NSPasteboard 类型，仅 UTF-8 纯文本及 macOS NSStringPboardType 纯文本别名；GUI pbpaste 与原文逐字节相同 |
| 5 | 手动格式覆盖与记忆 | Core 路径偏好与重命名迁移；1.0.2 真实选择 .txt 为 JSON 后跨窗、撤销/重做保留；全新进程重开手动模式未单独人工验证 |
| 6 | 四种源码行号、预览隐藏 | native-*-gutter；GUI 源码与预览实际画面 |
| 7 | 行号滚动、折行、编辑、撤销、底部 | 1,500 次随机编辑与全量行索引/换行类型比较；原生编辑撤销；GUI 底部无竖线。长距离滚动/折行细节待补人工 |
| 8 | 标签切换无白屏和跳动 | 同一窗口先准备目标视图，稳定文档切换；GUI 点击检查，未录制高帧率视频 |
| 9 | 侧边栏窗口状态隔离 | sidebar-window-state；GUI 展开后切换标签仍为 220 pt。拖动调宽/滚动选择保留待补人工 |
| 10 | 四种跨窗组合 | 1.0.2 使用真实 CGEvent/AppKit 拖放完成 1→1、1→多、多→1、多→多；事件和逐步 UUID 快照见回归记录 |
| 11 | 所有区域拖入、拆窗、Escape | 正文、预览、统一标题/工具栏、侧边栏、状态栏、标签间放下；第二/第三标签拆窗、重排、窗口外/预览上 Escape 均实测通过 |
| 12 | 拖后原文、修改、撤销 | 真实快照逐字段核对；最终构建跨窗后实际 ⌘Z/⌘⇧Z 清除/恢复修改标记及原文，手动 JSON 保留 |
| 13 | 后续标签命中 | 第二标签关闭提示对应 source.txt，取消保留；第三标签精确移除其 UUID，第二/第三标签均真实拆窗 |
| 14 | 未激活标签菜单正确 | GUI 未激活 Markdown 另存为名称正确；保存/重命名/关闭均捕获被点击文档对象；后几项未逐个人工覆盖 |
| 15 | 关闭其他取消 | GUI 实际保存提示可见，取消后两个标签保留 |
| 16 | 真实重命名、保留修改、目标冲突 | Core 检查原路径消失，新路径磁盘原内容不变，内存编辑/文档/UndoManager 身份不变；同名拒绝；后续新路径保存 |
| 17 | 未保存文档命名 | Core 新文档 suggestedName；保存面板使用 doc.name；首次面板未另作人工测试 |
| 18 | 缩放与预览 | GUI ⌘= 显示 107%，预览同步；共用同组动作，支持 +、=、−、0；缩小/重置未分别截图 |
| 19 | 三种主题与系统变化 | 1.0.2 真实选择浅色、深色、跟随系统，标签/正文/侧边栏/状态同步，原文不变；系统外观定时变化未触发实测 |
| 20 | 编码/BOM/换行 | Core 五种编码无损往返，LF/CRLF/CR 与混合索引；二进制/非法内容拒绝 |
| 21 | 外部变化与保存前检查 | external-clean-reload / external-dirty-conflict；Core 外部原子替换与拒绝覆盖；另存为同冲突路径拒绝 |
| 22 | 恢复草稿与隔离 | Core 草稿落盘、恢复为新文档、resolved；测试自有偏好与最近记录使用 /tmp JSON 存储；原生面板导航由系统管理 |
| 23 | 重复、不同路径、并发启动 | 8 个真实子进程并发请求，标签数精确增加 8；复制到不同安装目录后转交新窗口成功 |
| 24 | 后台窗口定位 | targetWindow 使用 keyWindow、lastWindow 与现存窗口回退；IPC 请求实际加入现有窗口。后台 Dock/Finder 全路径人工复核未完成 |
| 25 | 1/10/30 MB 多行与 10 MB 单行 | 最终集成报告 performance，分别记录建模、首次显示、编辑、撤销与批量 RSS |
| 26 | 中文、emoji、组合输入 | native-marked-text-start/commit、paged-unicode-cross-page-undo/redo；GUI 中文 emoji 显示/粘贴。真实输入法候选待补 |
| 27 | Release 签名/依赖/ZIP | distribution-results；本机 ad hoc 签名，无 Developer ID/公证；macOS 13 最低部署标记不代表已在 13 实机测试 |

## 性能口径

文件测试为 Release 构建。openToDisplayMs 从磁盘读取开始，包含解码、文档模型、TextKit/WK 容器创建及窗口 displayIfNeeded；不是仅解码耗时。editToDisplayMs 包含原生一次插入至强制显示；不包含随后异步恢复草稿持久化，也不是硬件输入到屏幕光子延迟。

文件大小使用十进制 MB。RSS 使用 MiB，包含共享驻留页；集成测试是在同一进程连续创建/关闭很多测试文档，RSS 含测试夹具、分配器缓存与前序预览成本，不可当成“新进程只开这一份文件”的占用，也不包含 WebKit 辅助进程。新进程与辅助进程的补充测量在 launch-results.json。

启动样本创建全新 GUI 主进程，但**没有清理系统或文件缓存**。mainToWindowMs 不包括 main 前动态库加载；spawnToReadyObservedMs 从外部创建进程起计，包含渲染与最多约 5 ms 轮询。Markdown ready 等待离线图表完成。不能把这组数据称为清缓存后的硬冷启动。

## 交付边界

- 超长行采用分段原生编辑；完整原文权威模型不变，跨段撤销已验证。鼠标连续选区局限于当前段。
- Mermaid tiny 官方精简版有图表类型范围限制，本地图片仅支持受限目录内位图。
- Markdown 预览性能只测试小型复杂文档；30 MB 测试为源码编辑，多 MB Markdown 渲染尚无性能保证。
- macOS 13–26、Intel、Universal、真实中文输入法候选及完整鼠标跨窗口拖放矩阵仍需补测。
- 不具备 Developer ID 公证。离线资源与 ZIP 可以本机构建复现。

## 1.0.0 本机数值（历史样本）

核心检查 3,061 / 3,061 通过；集成检查 65 / 65 通过，最终验证进程 exitCode=0、normalExit=true。

| 文件 | 读取至首次显示 | 一次插入至显示 | 批量测试主进程 RSS |
|---|---:|---:|---:|
| 1MB-multiline | 147.6 ms | 13.0 ms | 183.4 MiB |
| 10MB-multiline | 426.2 ms | 15.5 ms | 259.9 MiB |
| 30MB-multiline | 1020.7 ms | 15.0 ms | 367.7 MiB |
| 10MB-single | 148.7 ms | 114.8 ms | 377.3 MiB |

三次空文档新进程 spawn→ready 观察值为 784.6 ms / 290.8 ms / 272.7 ms；主进程 RSS 约 101 MiB，不创建 WebKit。

含 Mermaid 的小型 Markdown 新进程就绪约 1224.4 ms，主进程 RSS 109.8 MiB。新增 WebKit GPU/WebContent/Networking 辅助进程合计约 142.0 MiB（共享驻留页可能重复计入），不能仅引用主进程数值代表预览总成本。

ZIP 2,454,828 字节，应用文件合计 5,692,601 字节。解压后的包 codesign --verify --deep --strict 通过；签名为 ad hoc，未公证。SHA-256：`82a911f99add73278e06a085f1f5ffbc00e6f73c2c4ca18f94bb81f02143ca54`。


## 1.0.1 修复与回归

关闭标签和侧边栏普通鼠标点击已通过，详见 [本轮记录](DRAG-REGRESSION-1.0.1.md)。当前集成报告为 73 / 73 通过，正常退出；核心数据检查仍为 3,061 / 3,061 通过。新增检查验证拖动源生命周期、视觉提示穿透和原生按钮行为。跨窗实际放下与拆窗仍等待系统输入授权，不记录为已通过。

| 当前文件样本 | 读取至首次显示 | 一次插入至显示 |
|---|---:|---:|
| 1MB-multiline | 144.9 ms | 15.0 ms |
| 10MB-multiline | 426.5 ms | 15.1 ms |
| 30MB-multiline | 1011.7 ms | 17.6 ms |
| 10MB-single | 146.9 ms | 114.4 ms |

1.0.1（build 2）分发包签名、资源和 ZIP 完整性通过。ZIP 2,467,688 字节；SHA-256 `d6b27fbc8cb3d48b3569579b54e6406bbd826199f4c143a2b361f1b65fca2dbc`。启动 RSS 样本仍为上方明确标注的 1.0.0 历史记录，本次没有把旧启动测量冒充新版本实测。
