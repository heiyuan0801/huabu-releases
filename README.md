# 未来画布客户端下载

本仓库保存独立 Flutter 客户端构建文件，并编译、发行未来画布 AI 创作客户端安装包、更新清单及签名更新源。安装包以 [Releases](https://github.com/heiyuan0801/huabu-releases/releases) 中实际提供的文件为准。

客户端更新清单：[flutter-release.json](https://github.com/heiyuan0801/huabu-releases/releases/latest/download/flutter-release.json)。

邀请奖励沿用服务端规则：受邀用户完成注册并验证邮箱后，按站点公开规则获得积分；下载或安装软件不发放积分。

`client/` 使用 Flutter 3.47.7、Forui、Riverpod、GoRouter、Dio、Drift 与系统安全存储。它连接既有站点 API；本仓库不包含后端、账号数据或私有签名密钥。

推送客户端构建文件后，Windows 工作流编译完整 x64 应用和安装器，保存在 Actions 构建产物中。其他平台可在相应主机进入 `client/`，使用 `scripts/package-release.sh macos|android|ios` 打包。Android 正式发行需要通过 `HUABU_ANDROID_KEY_PROPERTIES` 指定安全保存的签名配置，iOS 需要 Apple 分发签名才能导出可安装包。

`Build client platforms` 工作流同时验证 macOS Release、iOS 未签名归档和 Android Debug 编译，仅保存在 Actions 产物中。Android Debug 是测试包，不进入软件下载或更新清单；正式 Android 包和桌面更新签名在持有固定密钥的主机完成，密钥不上传本仓库。

发布时将已验证的安装包、清单、签名 appcast 和 `SHA256SUMS` 放入 `payload/`，更新 `release-notes.md`，提交并推送对应的 `client-v<版本号>` 标签。本仓库的 GitHub Actions 核对文件摘要和版本后，创建公开 Release 并上传真实文件。工作流使用仓库自动提供的 `GITHUB_TOKEN`。超出 Git 单文件限制的安装包在提交时拆分，发布工作流还原并校验后上传完整文件。
