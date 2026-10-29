TinyEditor 首个本机验证版本，Apple Silicon / arm64，最低部署 macOS 13。

原生 TXT / Markdown / JSON / YAML 编辑、多窗口多标签、离线 Markdown/Mermaid/KaTeX、源码范围复制、编码保留、安全保存、重命名、恢复草稿与每用户单实例。

应用约 5.6 MB，ZIP 约 2.3 MB。3,061 条核心断言与 65 项集成检查通过，测试进程正常退出。10 MB 多行首次显示约 426 ms；30 MB 约 1.02 s；10 MB 超长单行采用原生分段视图，约 149 ms。

签名为 ad hoc，没有 Developer ID 签名及公证。实机验证平台是 macOS 27.2 arm64。完整真实鼠标跨窗口拖放矩阵、真实输入法候选、macOS 13–26 与 Intel/Universal 仍待补测，因此标记为预发布版本。

超长行鼠标连续选择限于当前分段；完整原文保存/全选复制/查找替换/跨段撤销保留。Mermaid tiny 不包含部分官方精简版排除的图表类型；本地图片只读取文档目录内位图。

请解压 ZIP 后将 TinyEditor.app 放入“应用程序”。源码构建：`./scripts/build.sh`。详细验证、内存与性能口径见仓库 docs/VALIDATION.md。
