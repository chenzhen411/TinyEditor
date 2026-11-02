# 发行签名状态与后续步骤

2026-10-31：仓库已改为 public，以不带登录凭据的 GitHub API 确认源码和 v1.0.4 安装包可公开访问。对全部本地可达历史的 209 个 Git blob 检查了常见私钥、访问令牌格式及证书凭据文件名，未发现匹配项。此为定向检查，并非对所有秘密格式的保证。实际结果见 publication-results.json。

2026-11-02：当前 v1.0.5 / build 6 已设为 GitHub 正式 Release 与 Latest，继续使用 ad hoc 本地签名，未经过 Apple 公证。此次提升仅修改发行标记和文档，未替换应用、DMG 或校验和。GitHub 的正式发行标记与 Apple 签名、公证状态相互独立，验证结果见 evidence/1.0.5-stable-release.json。

## 尚缺的条件

2026-10-31 的本机用户及系统钥匙串检查返回 `0 valid identities found`；项目所有者当时确认没有 Apple Developer 账号。此后未执行 Developer ID 签名或提交 Apple 公证。

正式面向站外分发的签名需要：

1. 加入 [Apple Developer Program](https://developer.apple.com/programs/enroll/)，完成账号身份、协议及会员手续。
2. 按 [Apple 官方证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)创建 Developer ID Application 证书，并将证书与对应私钥保存在本机钥匙串。普通开发证书或自签名证书不能替代此发行证书。
3. 为 `notarytool` 准备 Apple 允许的公证认证方式，将凭据保存在本机钥匙串。不要把密码、私钥、API key 或证书导出包提交到仓库或发送到聊天中。

## 凭据就绪后的发行流程

当前 `scripts/build.sh` 明确生成 ad hoc 包，不能把它的输出直接标为正式签名包。准备 Developer ID 发行时，应在 `/tmp` 的独立暂存目录处理并保留现有下载包，全部验证成功后再发布：

1. 以 Release 构建，使用 Developer ID Application 身份签名，启用 hardened runtime 并添加安全时间戳。TinyEditor 的预览使用系统 WebKit 辅助进程，不预先添加 JIT 或关闭库校验等宽松权限。
2. 严格核对签名、Developer ID 证书链、TeamIdentifier、runtime 标记和时间戳；运行隔离 AppKit/WebKit 回归，保护现有用户文档。
3. 将 ZIP 通过 `xcrun notarytool submit` 提交 Apple，核实状态为 Accepted；失败时保留诊断记录，不能发布为已公证。
4. 对应用执行 `xcrun stapler staple` 与 `xcrun stapler validate`；再次严格检查代码签名，并通过 `spctl --assess --type execute` 验证 Gatekeeper 接受。
5. 对已附公证票据的应用生成 DMG 和 SHA-256，挂载及安装复制验证后上传 GitHub Release，并更新其签名、公证说明。原有 ad hoc 包须继续保持准确说明。

以上是待执行流程，不是已完成的签名或公证证据。Apple 要求见 [公证前准备](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)与[公证工作流](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

2026-10-31 分发格式调整：当前公开下载改用 DMG，正式公证时仍可使用临时 ZIP 作为 Apple 提交载体，临时文件不作为 GitHub 分发附件。签名、公证状态不会因封装为 DMG 而改变。
