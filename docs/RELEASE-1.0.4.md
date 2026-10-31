TinyEditor 1.0.4（build 5），Apple Silicon / arm64，最低部署 macOS 13。

按参考图重做标签外观：活动标签使用独立圆角卡片，非活动标签融入背景；左侧文件图标及标题、右侧关闭按钮，新建按钮紧跟标签。浅色与深色分别适配，标签栏仍随正文避让侧边栏。

83 项原生集成检查正常退出；真实鼠标检查了双标签切换、侧边栏联动、第二标签关闭，复核浅色与深色截图。详见 docs/TABS-1.0.4.md。本轮未重跑完整真实跨窗拖拽矩阵。

本地 ad hoc 签名，未公证。此前系统输入测试驱动权限保持撤销状态。

2026-10-31 起改用 `TinyEditor-macOS-arm64.dmg` 分发，替换本版本原 ZIP 附件。镜像包含应用、Applications 快捷入口和安装说明；校验和在 `SHA256SUMS.txt`。挂载后应用及复制安装后的严格签名、离线资源、镜像完整性均已检查。应用仍为 v1.0.4 / build 5，功能未变。

使用 curl 下载：

```sh
curl -fL --retry 3 -o TinyEditor-macOS-arm64.dmg https://github.com/chenzhen411/TinyEditor/releases/download/v1.0.4/TinyEditor-macOS-arm64.dmg
curl -fL --retry 3 -o SHA256SUMS.txt https://github.com/chenzhen411/TinyEditor/releases/download/v1.0.4/SHA256SUMS.txt
shasum -a 256 -c SHA256SUMS.txt
open TinyEditor-macOS-arm64.dmg
```

保存文档并正常退出旧版，再将镜像中的 TinyEditor.app 拖入 Applications。完整命令安装流程见 [README](https://github.com/chenzhen411/TinyEditor#使用-curl-下载并安装)。
