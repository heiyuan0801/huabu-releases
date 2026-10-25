# 未来画布客户端发行

本仓库编译和发行独立 Flutter AI 创作客户端，支持 macOS、Windows、Android，并提供供开发者签名的 iOS 归档。

当前版本：[0.1.7+8](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.7)。[官网软件下载](https://image.iyuns.com/download)，[本站更新资料与历史版本](https://image.iyuns.com/client-updates/)。GitHub 正式发行和本站镜像均已更新，14 项公开资源及 22 项本站 HTTP 检查通过。

本版新增独立批量生图工作台及图片画布，支持提示词清单编辑、文字/图片节点、连线和生成结果回填。画布结构按账号保存，原图仅在本机按账号和日期存储。画布修改需手动保存；队列与未保存结果仅在当前应用进程中保留，请自行备份图片。

客户端源码在 `client/`。GitHub Actions 执行静态分析、测试以及 macOS、Windows、iOS 和 Android 验证构建；正式 Android 包使用本机固定发行签名，不上传私钥。发行分支为 `codex/client-release/0.1.7`，发布标签为 `client-v0.1.7`。

macOS 提供通用 DMG / ZIP，Windows 提供 x64 安装器 / 完整便携 ZIP，Android 提供固定签名 APK / AAB。iOS 未签名归档不能直接安装；macOS 尚未完成 Developer ID 公证，Windows 尚未配置 Authenticode。更新签名不替代操作系统发行身份签名。macOS 辅助功能自动化输入的调试异常、真实跨版本安装及各平台业务仍需验收。

GitHub 首发，服务器每 5 分钟检查一次发行，完整文件通过 SHA256 和更新签名校验后原子切换本站入口；失败保留上一版，历史包不自动删除。用户下载和更新优先使用本站，GitHub 保留备用下载。
