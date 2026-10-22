# 未来画布 · Flutter AI Studio

面向 macOS、Windows、iOS、Android 的独立创作客户端，使用 Forui、Riverpod、GoRouter、Dio、Drift 和 Forui 内置 Lucide 图标，接入现有 Go 服务。

提供注册、邮箱验证、密码/验证码及桌面扫码登录、忘记密码、灵感探索、图片与参考图创作、视频生成、流式 AI 聊天、模型中心、创作广场、作品与收藏、素材和个人设置。macOS/Windows 固定使用侧栏与多面板，窄窗折叠侧栏并按工作区需要横向滚动；手机使用底部导航与纵向布局，支持明暗/系统主题。3D 页面和入口已移除。

模型、媒体与个人接口统一经项目服务器代理。平台渠道来自真实模型目录且只读；个人渠道按账号保存在当前设备的系统安全存储中，不同步到服务器既有个人渠道配置。新生成图片与新收藏按站点、账号及日期保存在本设备文件夹，Drift 仅保存图片索引和设备偏好，图片不上传服务器；云端历史独立保留，视频、聊天与主动上传的素材沿用服务器存储。

AI 生图可切换批量模式：每行一条提示词，或导入 UTF-8 TXT，统一模型/画幅/质量/每项数量与可选参考图，逐项执行，失败继续、不自动重试。可停止后续任务，保存失败仅重试落盘。队列与未保存结果仅在当前运行中保留，请保持应用运行。个人设置可查看目录，Mac/Windows 可选择外置盘并打开文件夹；默认使用应用文档目录，已有图片不自动搬移或删除。新图片仅本机保存需当前后端已有的 `detail.resultStorage: browser` 不归档协议，服务端仅保留无媒体任务核对资料；这一协议值沿用服务端命名，并不表示原生客户端使用浏览器存储。

内置蓝紫应用图标、三张创作入口装饰图和桌面开屏透明标志，由 GPT 图片生成制作；装饰图不作为公开作品或生成结果展示。macOS/Windows 冷启动播放可跳过的品牌动画，遵循减少动态效果设置，设计与资源见 [开屏说明](design/desktop-launch.md)。图片/视频参数草稿仅在当前账号的运行内存中保留。

邀请页读取真实 AFF 规则、邀请记录与收益，积分沿用后端的注册并验证邮箱结算，仅下载或安装不发奖。桌面头像旁提供更新按钮，真实新版显示红点，可检查版本、查看日志并打开 Sparkle/WinSparkle 签名安装窗口；无有效更新配置时提供真实下载入口。更新清单默认读取 `https://image.iyuns.com/client-updates/latest/flutter-release.json`，历史更新日志使用本站 `/client-updates/`；构建时仍可通过 `--dart-define=APP_UPDATE_MANIFEST_URL=https://你的更新清单地址` 覆写清单入口。手机「扫码登录」可确认本人网页或桌面客户端的二维码，站点未提供真实能力时不可用，小程序扫码保留。网页 `/download` 展示真实截图、安装包与发行说明。

## 快速开始

要求 Flutter 3.47+、Dart 3.13+，Forui 固定 0.27.5，依赖版本见 `pubspec.lock`。本机外盘环境已安装 Flutter、Xcode、Ruby 3.4.11 与 CocoaPods 1.16.2：

```bash
cd /Volumes/mac/tihu/huabu/flutter
source /Volumes/mac/developer/huabu-flutter-env.sh
flutter pub get
flutter run -d macos
```

macOS 的 `media_kit` 视频原生依赖需要 CocoaPods。上述环境入口提供外盘 Ruby/Gem/PATH、`PUB_CACHE`、`DEVELOPER_DIR`、`TMPDIR`、`CP_HOME_DIR` 与 `CP_CACHE_DIR`；Gem、CocoaPods 仓库和下载缓存位于 `/Volumes/mac/developer`，项目构建产物位于外盘项目目录。它不修改系统 Ruby 或全局终端配置。系统 Command Line Tools 与 CoreSimulator 服务仍使用系统位置。

Android SDK、Temurin 17 JDK 及构建缓存也使用外盘环境；用户确认许可后 API 36、构建工具、NDK 与 CMake 已安装。Android 长期发布签名通过 `HUABU_ANDROID_KEY_PROPERTIES` 加载，不放入项目或普通数据库。各平台资源包命令、签名要求和发布资料生成见 [打包说明](scripts/README.md)，输出位于 `build/packages/<客户端版本>/`。

默认连接 `https://image.iyuns.com`。升级后首次进入新站点需要重新登录，登录会话与本设备个人渠道仍按站点和账号隔离。连接其他已部署的项目服务器：

```bash
flutter run -d macos --dart-define=API_BASE_URL=https://你的项目域名
```

`API_BASE_URL` 填站点 origin，不含 `/api`。iOS/Android 使用 `flutter devices` 返回的模拟器或真机 ID；Windows 需在 Windows 主机准备 Flutter 与 Visual Studio C++ 桌面工具后执行 `flutter run -d windows`。Apple 真机和分发需要开发团队与签名，Android 分发需要发布签名。项目未放宽平台网络安全配置。

## 验收状态与文档

本机图片归档与逐项批量生图为本轮新增代码，已补充隔离测试但按项目约定未执行检查、测试或构建，也未发布；目录权限、真实生成和跨平台验收见 [待测试文档](../docs/content/docs/progress/pending-test.mdx)。下方通过记录对应此前版本。

桌面开屏当前仅本地预览：macOS Release 编译与原生浅色进入真实首页通过，语义断言/首帧 Esc 焦点问题已修复，13 项开屏 Widget 测试通过。最终焦点修复版 macOS Release 编译、分析与深色原生启动均通过；快捷键恢复仅完成 Widget 验证，Windows 原生和系统级减少动态效果仍待验收，本轮不改版本或发布。

本站发行镜像已部署，默认清单为 `https://image.iyuns.com/client-updates/latest/flutter-release.json`，历史目录为 `/client-updates/`，网页公开统一读取，GitHub 保留备用。每 5 分钟检查已实际运行成功；这是检查间隔，非下载完成时限，每轮一次、不并发，失败保旧且不自动清历史。过渡版 [client-v0.1.5](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.5)（`0.1.5+6`）已发布，分析与 27 项更新专项通过，四平台构建和 14 项资源已核对；线上镜像已切换为 `0.1.5+6` 且保留 `0.1.4`，最终独立外网 61 次匿名 HTTP 请求与游客真实版本/日志冷刷新核验通过；整包摘要/签名在导入时验证，HTTP 采用 HEAD/Range 与清单读取。Mac `0.1.5+6` 已实际运行，明暗更新弹窗正确读取本站版本/日志、手动刷新、历史双版本日志/下载、长日志滚动与 Esc 关闭均通过；真实登录账号、移动真机、跨版本替换及正式平台签名仍待验收；旧客户端无法访问 GitHub 时需先从官网安装一次过渡版。

客户端 `0.1.4+5` 此前已公开发布为 [client-v0.1.4](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.4)，GitHub 四平台构建、14 项资源与签名更新资料核对通过。更新弹窗按参考图适配桌面横向与手机紧凑布局，macOS Release 已编译运行并检查明暗主题、真实新版日志、长日志滚动和 Esc 关闭；Flutter 静态分析无问题，全量 148 项与更新专项 27 项测试通过。真实下载进度、暂停继续和自动安装选择尚未接入，现有签名更新仍通过原生窗口完成；真机和实际跨版本安装仍需验收，iOS 未签名归档不作为安装包。

客户端 `0.1.3+4` 默认连接 `https://image.iyuns.com`，自定义服务器与按站点隔离的会话保留，首次使用新域名需重新登录。Flutter 静态分析和全量 148 项测试通过；GitHub 四平台构建与 [client-v0.1.3](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.3) 正式发行已完成，14 项资源摘要、下载地址及桌面更新签名已核对，完整设备验收见 [待测试文档](../docs/content/docs/progress/pending-test.mdx)。

历史版本客户端 `0.1.2+3` 对应根项目 `v0.19.1`，当时已公开发布为 [client-v0.1.2](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.2)：macOS ZIP/DMG、Windows x64 安装器/ZIP、Android 四 APK/AAB，以及供开发者签名导出的 iOS unsigned archive；14 项资源大小/摘要、下载地址、发行清单与签名更新源已核对。本轮全量 Flutter 148 项、Go 扫码专项、后端隔离合成扫码 28 场景及 Web Vite 构建通过。新版 Mac 已启动，用户处理钥匙串后账号恢复且头像旁更新按钮可见。网页和最小扫码后端已更新到生产，数据/配置保留检查通过；下载页初始化读取悬挂已修复并上线，生产游客两次冷刷新、平台入口/日志和真实 App 二维码加载检查通过，完整真机与业务验收见待测试文档。

模拟平台测试不等于原生验收。Windows ARM64、Authenticode 和实际安装/运行，Mac Developer ID/公证，iOS 团队签名与正式安装渠道仍待完成；本机没有可用的 iOS Simulator 运行时。真实手机相机权限、扫码确认/拒绝与跨版本更新、注册/邮件/密码修改、AFF 到账和收费创作仍需人工联调。后端仅扩展用户批准的既有扫码模式，不创建新账号系统或积分规则。

- [API 接口说明](../docs/api-reference.md) · [设计与结构](DESIGN.md)
- [待测试事项](../docs/content/docs/progress/pending-test.zh-CN.mdx) · [后续待办](../docs/content/docs/progress/todo.zh-CN.mdx)
- [Forui 官方文档](https://forui.dev/docs) · [Flutter 平台开发](https://docs.flutter.dev/install)
