# v1.0.4 DMG 分发验证（2026-10-31）

按用户要求，当前 v1.0.4 / build 5 的应用安装包从 ZIP 改为 DMG。`scripts/build.sh` 通过 `scripts/package-dmg.sh` 生成只读压缩 UDZO 镜像、Applications 快捷入口、中文安装说明及 SHA256SUMS.txt。后续构建不再输出 ZIP 分发包。

## 本机实际检查

- `./scripts/build.sh` 成功；应用 arm64，部署目标 macOS 13.0，ad hoc 签名、未公证。
- `hdiutil verify` 验证镜像完整性成功。
- `python3 scripts/verify-distribution.py`：只读挂载成功；镜像内应用严格代码签名通过；Applications 符号链接指向 /Applications；安装说明存在；离线资源引用与字体文件完整；测试输入驱动未包含在应用内。
- 将挂载应用用 `ditto` 复制到 `/tmp` 隔离安装目录，再次严格验证签名成功。
- 镜像中的 71 个应用文件 SHA-256 与此前 v1.0.4 ZIP 的文件摘要逐项相同；没有修改应用代码或版本。
- DMG：2,702,886 字节；SHA-256：`d4a84a097e5e757032aba5f2efc01eb3ad9ac4867ba5c6f45086476e75d18428`。
- 通过无认证的公开 GitHub Release 地址实际 `curl` 下载 DMG 和 SHA256SUMS.txt；`shasum -a 256 -c` 成功，下载包与本地发布包一致，GitHub 资产摘要一致。本机这次 curl 下载未出现 com.apple.quarantine 属性；未执行删除隔离标记的命令。
- README 安装代码块在隔离目标实际执行，验证了下载、校验、挂载、旧版备份、复制安装和严格签名。测试仅重定向应用/备份位置，跳过正在运行的用户应用检查和最终 GUI 打开；未改动 `/Applications` 中的用户应用或用户偏好。详情见 evidence/1.0.4-dmg-download.json。
- 当前 Release 的应用 ZIP 分发附件已移除，DMG 和校验和保留。GitHub 自动生成的源码归档不属于应用安装包；旧版历史验收记录保持原样。

此次只调整分发方式，没有重跑原生 GUI 集成或跨窗拖拽矩阵。83 项集成检查及真实标签验收为此前同一应用文件的结果。签名方式不因 DMG 封装或 curl 下载发生变化，不声明已经获得 Developer ID 或 Apple 公证。

结果：distribution-results.json；公开下载及隔离命令安装：evidence/1.0.4-dmg-download.json。
