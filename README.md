# 未来画布客户端发行

本仓库编译和发行独立 Flutter AI 创作客户端，支持 macOS、Windows、Android，并提供供开发者签名的 iOS 归档。

当前版本：[0.1.6+7](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.6)。[官网软件下载](https://image.iyuns.com/download)，[本站更新资料与历史版本](https://image.iyuns.com/client-updates/)。

本版新增本机图片按账号和日期归档、自选外置盘目录、逐项批量生图、桌面品牌开屏和 Windows 安装桌面快捷方式。图片请自行备份，批量队列及未保存结果只在当前运行中保留。

客户端源码在 `client/`。GitHub Actions 执行静态分析、测试以及 macOS、Windows、iOS 和 Android 验证构建；正式 Android 包使用本机固定发行签名，不上传私钥。发布分支 `codex/client-release/0.1.6` 与 `client-v0.1.6` 标签保存安装包、摘要及签名更新资料，14 项公开资源已核对。

macOS 提供通用 DMG / ZIP，Windows 提供 x64 安装器 / 完整便携 ZIP，Android 提供固定签名 APK / AAB。iOS 未签名归档不能直接安装；macOS 尚未完成 Developer ID 公证，Windows 尚未配置 Authenticode。更新签名不替代操作系统发行身份签名，真实跨版本安装与业务功能继续按客户端待验收清单核对。

GitHub 首发，服务器每 5 分钟检查一次发行，完整文件通过 SHA256 和更新签名校验后原子切换本站入口；失败保留上一版，历史包不自动删除。来源清单保留在 [GitHub Releases](https://github.com/heiyuan0801/huabu-releases/releases)，用户下载和更新优先使用本站。
