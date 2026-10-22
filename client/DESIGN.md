# 设计与架构

移动端依据用户授权的 Stitch 项目「AI 生图微信小程序 UI」`12705101780884876511`，只读获取现有页面与主题。桌面端依据用户提供的深色创作工作台图片。参考中的模拟余额、会员、模型速度和生成进度不作为真实业务数据。

浅色采用冷白与低饱和靛紫，深色采用碳黑、分层卡片和紫色强调。全局颜色、字体、间距、圆角、阴影和动效位于 `lib/core/theme.dart`；Plus Jakarta Sans 随应用打包，中文使用平台字体回退，字体许可见 `assets/fonts/OFL.txt`。控件优先使用锁定版本 Forui 0.27.5 的按钮、输入框、选择器、卡片、提示、弹窗、导航及内置 Lucide 图标。

布局按平台决定：macOS/Windows 保持侧栏、多面板和鼠标键盘操作，窄窗折叠侧栏，图片等工作区保留桌面面板并横向滚动；手机采用五项底部导航、触控与纵向排列，其他功能从探索入口进入。不会因为桌面窗口变窄就切为手机底栏。首页按可用宽度调整内容密度和瀑布流列数，模型列表按需构建并允许内容自然高度；共享缩略图按显示宽度 × 设备像素比解码，详情尊重原始比例。页面与卡片动效尊重系统减少动画偏好。Ctrl/⌘ + 1–5 切换桌面导航前五项，Ctrl/⌘ + K 聚焦搜索，Ctrl/⌘ + Enter 提交图片创作；桌面保留单一主题快捷入口，macOS/Windows 标题栏跟随应用主题，Windows 最小窗口为 720×480，runner 编译配置 `/utf-8` 以保留中文标题编码，Windows 标题栏与实际运行仍待验收，原生编译已在公开 CI 通过。

`assets/branding/` 内置 GPT 图片生成制作的蓝紫应用图标与图片/视频/聊天入口装饰图。`app-icon.png` 用于通用品牌及 Windows/iOS/Android，macOS 使用带透明外缘的圆角 `app-icon-macos.png`，四平台图标由 `flutter_launcher_icons` 配置生成。三张 `studio-*.png` 仅作装饰，不混入真实作品列表、任务结果或账号数据。

## 模块

| 目录 | 职责 |
| --- | --- |
| `lib/app` | 应用装配、GoRouter、平台导航与工作台布局 |
| `lib/core/api` | Dio、Cookie、同源代理、账号取消范围与版本化服务器存储 |
| `lib/core/models.dart` | 账号、作品、素材、模型、任务与文件结构 |
| `lib/core/repository.dart` | 作品、素材和独立收藏文件，实际图片保存与恢复去重 |
| `lib/core/providers.dart` | Riverpod 会话、目录、服务数据、设备主题与内存草稿 |
| `lib/core/database.dart` | Drift 本设备主题和按账号保存的默认图片模型偏好 |
| `lib/core/widgets.dart` | 加载/失败/空状态、代理图片、作品卡片、复制、导出和确认操作 |
| `lib/features/generation` | 图片协议、任务上下文、创作状态与保存重试 |
| `lib/features/video` | 视频协议、任务查询、服务器文件、原生预览与导出 |
| `lib/features/chat` | Responses/Gemini 流式协议、会话与独立服务器聊天存储 |
| `lib/features/catalog` / `channels` | 真实模型目录、设备默认模型、系统安全存储私有渠道与统一请求目标 |
| `lib/features/explore` / `community` | 灵感、创作广场阅读/点赞/收藏与提示词复用 |
| `lib/features/auth` | 注册、邮箱验证、账号及桌面二维码登录、找回密码及图形验证码 |
| `lib/features/web_login` | 手机相机扫码、本站协议校验、账号确认与拒绝 |
| `lib/features/affiliate` | 真实 AFF 活动规则、邀请链接/邀请码、邀请与收益记录 |
| `lib/features/updates` | 版本清单、软件下载与桌面签名更新 |
| `scripts` | 平台资源包、校验摘要与发布清单/appcast 生成 |
| 其余 `lib/features` | 作品、素材与账号设置 |

UI 使用全局 Riverpod 状态，业务请求和存储放在对应服务或仓库，不为页面层层传递全局配置。

## 账号与存储

登录沿用 `huabu_session` Cookie 与账号请求头，系统安全存储保管会话。macOS 使用系统钥匙串选项，切换开发构建可能需要用户确认系统钥匙串访问；正式稳定签名仍待发布验收。iOS 的权限与签名仍需真机验收。Drift 不保存凭据、作品或对话。账号切换取消旧请求、清理内存图片与页面状态；多步骤操作在后续请求前核对入口账号范围，页面或账号切换后忽略迟到结果。离线退出只在本机安全会话清理成功后退出，并说明服务器注销尚未确认；登录写入或退出清理安全存储失败不得提示成功。

系统安全存储读取返回 `PlatformException` 时，登录会话和本机渠道停止自动重试、保留错误并提供手动重读；其他读取沿用 Riverpod 原有策略。该边界经用户确认，未清除现有凭据或放宽钥匙串访问。系统安全窗口由用户自行处理，签名变化导致的系统授权不由应用绕过。

macOS/Windows 登录表单提供手机 App 扫码，站点实际启用时也提供小程序扫码；二维码由 `qr_flutter` 生成，不启用电脑相机。复用 `/auth/wechat-qr` 的 `app/wechat` 模式、Origin 与临时 Cookie 绑定，严格核对站点、模式、编号和二维码内容，沿用 5 分钟有效期及每次状态请求结束后 2 秒查询。确认后只调用一次 consume，必须收到本次新的会话 Cookie 且安全存储写入成功，才激活账号；关闭、切换方式或账号后停止旧请求，未知结果不自动重试。

iOS/Android 的「扫码登录」只扫描当前 API 站点根路径、唯一 `app_login` 参数，不访问二维码 URL，也不接受外站或小程序二维码。登录中的用户先核对站点和当前账号，再主动确认本人网页或桌面客户端；确认只表示授权，创建二维码的客户端消费后才完成登录。`mobile_scanner` 相机权限只在手机页主动扫描时申请，后台/离页停止并释放；授权校验绑定具体扫码会话，不新建、绑定或合并账号。

注册、登录和找回密码共用账号页面与现有 `/auth/*` 接口。注册要求主动勾选协议、两次密码一致及邀请码核验，创建账号不等于登录成功；按实际 `emailSent` 提示检查邮箱或重发，再以验证码完成邮箱验证与登录。登录返回 `202 / verificationRequired` 时进入验证流程，不冒充已登录。找回密码发送 `purpose: reset` 验证码，服务端确认更新后清理旧会话并返回登录；安全存储清理失败单独提示，不虚报密码提交失败。图形验证码和邮件服务可用性以站点配置为准，操作后刷新验证码，页面/账号切换取消请求并忽略迟到结果，不新增客户端发送倒计时或自动重试。

个人渠道整份配置仅保存在当前设备的系统安全存储，存储键按站点 origin 和账号隔离。密钥编辑不回显已有值，留空保留原密钥，不进入普通数据库或日志；配置不会覆盖 Web 既有的服务器 `ai_config_store`。平台渠道只从 `/catalog/models` 归纳，不提供虚构管理接口。模型中心支持分类、搜索、详情以及真实默认图片模型偏好。

平台目录与本设备个人目录分开读取，一方读取失败时可继续使用另一方真实目录，并立即提示失败来源；401/403、账号切换与取消不得降级为可用目录。两方失败显示错误，不能冒充空目录。目录与渠道读取失败不覆盖原配置。

图片、聊天、视频共用 `ModelApiTarget`：平台请求走 `/platform/{provider}`，个人请求走 `/proxy`；个人鉴权只在请求头中，密钥不进入 URL。跨源媒体下载不转发原渠道密钥。平台模型积分以服务端为准，个人渠道由接口提供方计费，不显示模拟会员或购买入口。

服务器是账号内容的权威来源。作品共用 Web 的 `image_generation_logs` / `image_files`，素材共用 `app_state / infinite-canvas:asset_store`；已有 `team:` 文件沿用原权限。收藏先复制实际图片到独立账号文件，再写 `artwork_favorites`，不会依赖原作者文件的持续可见性。视频使用 `video_generation_logs` / `media_files`；文字会话单独使用 `app_state / infinite-canvas:ai_chat_store`，不覆盖图片聊天或画布会话。

读取失败与真实空数据分开，版本冲突不自动覆盖服务器；图片/视频日志结构损坏时拒绝覆盖。附件先保存再写索引，保存失败仅重试保存；同一图片任务恢复按字节摘要去重补存。桌面导出到文件选择器指定位置，移动端调用系统分享，不模拟直接写入相册。

图片与视频参数、提示词和参考素材在当前账号的运行内存中保留，切页可继续编辑，切换账号清空，不承诺重启恢复。生成操作保持固定可达；批量图片以紧凑缩略图切换预览，未保存结果仍可查看。参数只展示当前协议实际发送的字段，不用通用界面暗示上游支持能力。

## 已实现协议与范围

- 图片：OpenAI、Gemini、Ark JSON 图片协议及已有 Muse/Grok 适配；参考图与参数取决于所选模型。标准异步仅在渠道提供对应 `/images/*/async` 时显式启用，查询沿用 Web 的 3 秒间隔和 30 分钟期限。
- 聊天：OpenAI Responses SSE 与 Gemini `streamGenerateContent`，支持图片输入、Markdown、会话历史与停止接收。连接中断保留收到的文字，只有真实终态才报告完成；停止接收不代表上游已取消或退款。
- 视频：Muse、Grok、Ark/Seedance 与 OpenAI 兼容协议，使用实际任务创建、查询、媒体下载、原生播放和服务器保存；支持哪些参考媒体由现有协议校验。查询沿用 Web 的 Seedance 5 秒、其余 2.5 秒及最多 120 次边界，不自动重新生成。
- 个人设置：真实昵称/头像、积分、每日签到、兑换码、明暗/系统主题和客户端版本；界面语言当前为中文。
- 邀请：读取 `/affiliate/program`、`/affiliate`、`/affiliate/referrals`、`/affiliate/earnings`，展示实际活动状态、注册/验证统计、奖励与分成、分页记录。链接指向当前站点 `/register?ref=邀请码`，安装客户端后也可手动填邀请码；已有账号不能补绑邀请。奖励沿用后端注册并验证邮箱规则，仅下载或安装不触发积分，本客户端不自行结算或增加余额。

按用户要求删除 3D 路由、侧栏/探索入口、作品分类及页面源码，客户端不再展示 3D 功能。

任务登记与真实模型请求分开，通过任务 ID 关联。恢复读取实际 `generation_contexts`，缺失的图片上下文由用户补充；未知结果不推断失败或退款，也不重发生成。分批中途停止、流式中断、视频查询耗尽与保存失败都需按真实任务记录核对。

自定义 Firefly、图片 SSE、无限画布、团队管理仍未接入本客户端；正式签名、商店分发与更新安装仍需对应平台验收。本轮未新增请求超时、自动重试或业务边界值。Stitch 凭据不进入代码、文档、配置或日志。

## 软件下载与更新

Flutter 客户端独立使用 `pubspec.yaml` 的 `0.1.2+3`，根项目此次提升为 `v0.19.1`，两者各自管理版本。默认从公开发行仓库 `heiyuan0801/huabu-releases` 的 `releases/latest/download/flutter-release.json` 读取 schemaVersion 1 清单，允许通过 `APP_UPDATE_MANIFEST_URL` 设置真实 HTTPS 发布源。清单只包含语义化版本、递增 buildNumber、说明和四平台实际 downloads/appcasts 地址；不允许 URL 凭据或片段。桌面头像旁的更新按钮检查真实版本，新版本红点只依据实际版本/构建号比较；Forui 详情弹窗展示 Markdown 更新日志与发行历史。个人设置与邀请页复用清单；读取失败、未发布 404、格式异常和当前平台未发布均保留明确状态，不推断已是最新版。

网页 `/download` 使用真实客户端截图与平台入口。游客读取本站已核对发行快照，已登录用户通过既有同源服务器代理检查官方最新清单；失败保留已确认资料并标明来源。无真实安装包的平台不可下载，iOS 未签名 archive 不作为用户安装包；不使用模拟账号、生成结果或计划功能冒充界面截图。

macOS/Windows 通过 `auto_updater` 接入 Sparkle/WinSparkle。只有当前安装包配置更新公钥且发布清单提供 appcast 时，才显示「更新并安装」，用户点击后打开原生更新窗口完成检查、下载和安装确认，并反馈真实状态；没有有效配置时回到下载入口。macOS Sparkle 公钥嵌入 Info.plist，使用受限的沙盒更新 helper 配置并关闭原生自动检查/自动安装与 profile 上报；Windows DSA 公钥作为 runner 资源并检查是否存在；签名私钥不进入客户端、源码或文档。更新请求使用独立 Dio，不携带账号 Cookie 或个人模型凭据，不自动触发下载或重启。Android 当前打开可安装 APK 下载，安装由系统确认；iOS 前往 App Store/TestFlight 等已配置安装渠道，不承诺应用自行替换安装包。

`scripts/package-release.sh` 在对应主机构建 macOS ZIP/DMG、Android 各 ABI APK/AAB 与 iOS 未签名 xcarchive；Windows PowerShell 脚本生成完整 bundle ZIP，并在有 Inno Setup 时生成安装 EXE。`generate-release-metadata.py` 按实际存在的资源、实际版本与验证过的签名生成本地 JSON/appcast 和 SHA256 产物清单，不自行上传或创建 tag。Mac 使用 Sparkle 官方工具在系统安全存储中签名与验证 ZIP；WinSparkle 更新必须是真实安装 EXE 及匹配 DSA 签名，便携 ZIP 不冒充安装器。Android debug 签名只能本地测试，未签名 iOS archive 不能安装，两者不会自动进入正式下载清单。更改资源后需要重新打包、签名并生成发布资料；按用户确认，公开发行仓库同时保存独立 Flutter 客户端源码与构建工作流，Windows 直接从此公开仓库编译；Go 后端、Web/小程序与账号数据、私钥和本机签名配置不发布。

## 开发环境与验收

本机外盘环境入口为 `/Volumes/mac/developer/huabu-flutter-env.sh`，提供 Flutter/pub 缓存、外盘 Xcode、Ruby 3.4.11、CocoaPods 1.16.2、Gem 和 CocoaPods 缓存路径。`media_kit` 的 macOS 原生依赖需要 CocoaPods；不覆盖系统 Ruby，不修改全局终端配置。系统开发工具服务仍位于系统目录。

上一轮 macOS Debug/Release 均为 ad-hoc 签名，没有 TeamIdentifier，designated requirement 使用不同的 cdhash；重建或切换构建类型可使已有钥匙串条目要求用户再次确认。彼时 Release 包包含 `get-task-allow: true`，未启用 runtime flag，定位为本机验收产物。本轮签名与权限以新资源包检查结果为准。正式发布需固定 bundle ID、Team 与签名身份，配置正式分发签名并验证权限与公证，不放宽系统安全策略；签名要求参考 [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

上一轮已只读核对 macOS 1360×860/最大化窗口、明暗主题和标题栏、真实图库及创作固定操作区，并在用户处理系统钥匙串确认后恢复已有账号；没有填写登录或验证码。原生 720×480 仍仅由 widget 测试覆盖；模拟平台不代表插件或业务已验收，详细记录见待测试。

`0.1.1+2` 发行批次 `flutter analyze --no-pub` 无问题，108/108 集中测试通过（含 GitHub octet-stream 清单解析）。Android SDK/Temurin 17 安装在外盘，API 36、Build Tools 36、NDK 28.2.13676358、CMake 3.22.1 与 platform-tools 37.0.1 就绪；长期 Android 发布签名仅经 `HUABU_ANDROID_KEY_PROPERTIES` 加载，不进入源码/文档。该批四 APK/AAB 的实际版本 `0.1.1/2`、签名和摘要已验证，云端 Android Debug 只用于编译验证，正式下载使用本机稳定签名包。

该批 Mac 最终 x86_64/arm64 Release 为 119.2 MB，ZIP/DMG 与严格签名检查通过；关闭基础权限注入后实际签名无 `get-task-allow`，保留沙盒及两个具名 Sparkle helper 例外，仍为 ad-hoc、未公证。iOS Release archive/ZIP 最低 iOS 15、版本 0.1.1 build 2，品牌启动图提供明暗背景，无默认图警告；unsigned archive 供开发者签名导出，不能安装。公开 Windows CI `38154941380` 成功生成 x64 安装器/完整 ZIP，通过摘要、CRC、资源、版本和内置 DSA 公钥核对；固定 PE 版本 0.1.1.2、字符串 0.1.1+2。公开 Apple/Android CI `38155012443` 也编译成功并产出真实 artifacts。Windows 安装/运行、真机和跨版本更新未验收，iOS Simulator 无可用运行时。

该批 Mac/Windows 签名 appcast 与三平台下载清单已验证，并随 [client-v0.1.1](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.1) 正式发布；13 项资源大小/摘要、默认清单/两个 appcast 与三平台下载 HTTP 均核对通过。

当前 `0.1.2+3` 全量 Flutter 148 项测试通过，包含手机扫码 20 项、桌面扫码 14 项、原有账号流程及更新/安全存储；Go 扫码专项、后端隔离合成扫码 28 场景与 Web Vite 构建通过。新版 Mac 通用架构 ZIP/DMG、Android 长期正式签名四 APK/AAB、iOS 未签名 archive 已构建，公开 Windows x64 与 Apple/Android 编译 CI 全通过。公开 Latest [client-v0.1.2](https://github.com/heiyuan0801/huabu-releases/releases/tag/client-v0.1.2) 的 14 项资源、下载、清单与签名 feed 均核对；iOS archive 只供开发者签名导出。新版 Mac 已启动并恢复已有账号，头像旁更新按钮可见。网页/扫码后端 `v0.19.1` 已部署，App 能力与公开 `0.1.2/3` 快照核对通过，数据和配置保持；下载页在账号初始化完成后才读取快照、查询 key 按用户隔离的修复已上线，Vite 构建和生产游客两次冷刷新通过；平台链接、日志弹窗与真实 App 二维码加载/关闭取消正常，此次浏览器错误/警告日志为空。自动化、构建和 HTTP 检查不代替真机相机、真实扫码与跨版本安装验收；正式功能说明仍等待用户确认。
