# Developer ID 签名与自动发布

Sumi 仅支持 Apple Silicon，直接分发 `.app` ZIP，不经过 Mac App Store，因此使用 **Developer ID Application** 证书。应用与 Tinymist helper 都开启 hardened runtime、使用安全时间戳，再提交 Apple 公证，装订票据并通过 Gatekeeper 校验后才能产出发布 ZIP。

## 一次性配置

本机 Xcode 登录账号不等同于 GitHub runner 持有凭据。需要为 `fenjin-ai/sumi` 配置：

| GitHub 配置 | 内容 |
|---|---|
| Secret `SIGNING_CERTIFICATE_P12` | 含 Developer ID Application 私钥的 `.p12`，Base64 编码 |
| Secret `SIGNING_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| Secret `APP_STORE_CONNECT_PRIVATE_KEY` | 专用于发布的 App Store Connect Team API `.p8` 私钥 |
| Secret `APP_STORE_CONNECT_KEY_ID` | API Key ID |
| Secret `APP_STORE_CONNECT_ISSUER_ID` | Team API Issuer ID |
| Variable `APPLE_TEAM_ID` | 证书对应的开发者 Team ID |

证书可通过 Xcode → Settings → Apple Accounts → 团队 → Manage Certificates → Developer ID Application 创建。API Key 在 App Store Connect → Users and Access → Integrations 创建，使用满足公证需求的最低权限。私钥只能下载一次，应直接存入密码管理器或受保护的文件；不要贴到 Issue、PR 或聊天中。

使用 `gh secret set --repo fenjin-ai/sumi NAME` 的标准输入配置秘密，避免命令行参数或日志展开秘密值。证书和私钥不属于源码或构建 artifact。

## 验证与发布

1. 普通 CI 只构建临时签名开发包，不接触发布凭据。
2. 在 main 手动触发 Release workflow，可验证完整签名/公证并下载 artifact，不创建公开 Release。
3. 更新 `Resources/Info.plist` 的版本号和构建号，将已验证的提交合入 main。
4. 推送与版本一致的标签，例如 `v0.2.0`。流水线检查标签指向 main 已包含的提交，通过功能测试和 80% 覆盖率门槛，再签名、公证、装订并发布。

任何缺失凭据、无效证书、Team 不匹配、公证未通过或超时都会阻止公开发布，不会降级成临时签名包。临时钥匙串、证书与 API 私钥在脚本退出时清理。GitHub 保留公证提交结果，便于查询 Apple 处理状态；私钥不上传为 artifact。

开发构建：`scripts/build.sh release`。正式发布步骤：`scripts/release.sh`，需要上表环境变量；本机临时材料保存在外置 SSD。

参考：[Apple 公证工作流](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)、[Apple API Key](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)、[GitHub 证书安装](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。
