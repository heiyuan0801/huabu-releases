# Flutter 资源包

所有输出放在已忽略的 `flutter/build/packages/<pubspec版本>/`，不上传、不发布，也不生成或保存签名密钥。

## macOS / iOS / Android

在 `flutter/` 内执行：

```sh
bash scripts/package-release.sh macos
bash scripts/package-release.sh android
bash scripts/package-release.sh ios
```

macOS 生成包含完整 `.app` 的 ZIP 和带 Applications 快捷方式的 DMG。Android 生成 universal APK、三个 ABI 的 split APK 及 AAB。Release 构建通过 `HUABU_ANDROID_KEY_PROPERTIES` 指定外置盘私有 `key.properties` 使用正式签名；签名配置和 keystore 不进入仓库，缺少配置时应停止构建。universal APK 作为统一下载入口，split APK 按设备 ABI 选择，AAB 供应用市场上传。iOS 生成未签名 Release `xcarchive.zip`，需要 Apple 开发者团队和证书在 Xcode 中签名导出才能安装。

split APK 使用 Flutter 官方 `force-version-code-ignoring-abi=true` 参数，与 universal/AAB 统一为 `pubspec.yaml` 的 buildNumber，保证后续可切换到通用 APK 更新，不被 Android 视为降级。发布后始终保持相同 applicationId、签名密钥和递增 buildNumber。

脚本存在时会读取 `/Volumes/mac/developer/huabu-flutter-env.sh`；其他机器可以通过 `HUABU_TOOLCHAIN_ENV` 指定自己的环境脚本。首次 Android 构建前需要 SDK、JDK，以及由开发者自行阅读并接受所需 SDK 协议；脚本不接受协议。

平台名后可传 `--package-only`，只打包已有产物；此时应先确保产物包含最新源码并与 `pubspec.yaml` 版本一致。其余参数传给 Flutter build，例如已配置的更新源 `--dart-define`。不要将密钥放进 Dart define 或命令历史。

## Windows

Windows 主机需要 Flutter 和含 Desktop development with C++ 的 Visual Studio：

```powershell
./scripts/package-windows.ps1 -Arch x64
```

脚本生成包含 EXE、DLL、data 的完整便携 ZIP。若已安装 Inno Setup 6 并能找到 `ISCC.exe`，同时生成每用户安装 EXE，供实际安装和 WinSparkle 更新使用。未安装 Inno Setup 时只生成 ZIP，并明确提示没有自动更新安装器。`-PackageOnly` 可打包已经构建的 bundle。ARM64 构建需相应 Windows ARM64 工具链。

Windows 构建前可将 `WS_DSA_PUBLIC_KEY` 设为已生成的 DSA **公钥 PEM 文件路径**，脚本只把公钥复制为工程更新资源；不生成、读取或复制私钥。使用 WinSparkle 官方 `sign_update.bat` 签名实际安装 EXE，私钥保留在开发者的安全位置，签名输出另存为公开的签名文本文件。

## GitHub Release 发布资料

先完成对应版本构建和打包，随后从实际存在的资源包生成本地发布 JSON 和签名 appcast：

```sh
python3 scripts/generate-release-metadata.py \
  --release-url https://github.com/heiyuan0801/huabu-releases/releases/tag/CLIENT_TAG \
  --notes-file /path/to/release-notes.txt \
  --sign-update macos/Pods/Sparkle/bin/sign_update
```

公开发行仓库已选 `heiyuan0801/huabu-releases`；示例 `CLIENT_TAG` 必须换成该客户端实际发布的 tag。生成内容位于 `build/packages/<版本>/release/`。脚本不创建 tag、不上传或发布；此时 JSON 中的地址只是待发布地址。`flutter-release.json` 严格使用客户端 schemaVersion 1，包含实际版本、buildNumber、notes，以及仅可安装资源的 downloads 和有真实签名的 appcasts。

Mac appcast 使用完整 ZIP；通过 Sparkle 官方工具在钥匙串账号 `chat.weilai.huabuApp.updates` 中签名和验证，核对 ZIP 的实际版本、公钥和签名长度。不会导出私钥。省略 `--sign-update` 则不生成 Mac 自动更新入口。

Windows 仅在指定 `--windows-installer` 实际 setup EXE 后添加下载入口；同时指定 `--windows-signature-file` 和 `--windows-public-key`，且通过 OpenSSL 验证官方 WinSparkle DSA 签名后，才添加自动更新 feed。指定的 EXE 必须位于本版本 packages 目录内，便携 ZIP 不会冒充安装器。

Android 默认不进入正式下载清单。正式签名的可安装 APK 通过 `--android-apk` 明确选择，并以 `apksigner` 验证；debug 签名 APK 拒绝进入正式清单。AAB 和未签名 iOS xcarchive 都不会作为安装入口。`release-artifacts.json` 单独记录所有本地产物、SHA256 和测试/未签名状态，供发布前核对。iOS 正式安装渠道尚需另行配置，appcasts 只对受支持的桌面端生成。

实际发布时将生成的 `flutter-release.json`、appcast XML 和对应可分发安装包放入同一个 GitHub Release，并将经核验的安装包与签名更新资料同步到本站镜像。客户端默认从 `https://image.iyuns.com/client-updates/latest/flutter-release.json` 检查更新，`https://image.iyuns.com/client-updates/` 提供历史日志；`--dart-define=APP_UPDATE_MANIFEST_URL=https://你的更新清单地址` 可覆写清单入口。镜像清单的下载与 appcast 地址应指向同一实际版本，改写 appcast 的包地址时保留原包字节与签名。修改安装包后必须重新打包、签名并生成资料。

## 正式分发与更新

目前本地打包不等于已签名发布。macOS 需要 Developer ID 签名、公证及 Sparkle 更新签名；Windows 需要安装 EXE、推荐 Authenticode 签名及 WinSparkle 更新签名；Android 需要长期固定的正式 keystore；iOS 需要 App Store/TestFlight 或有授权的分发方式。

使用实际托管的 HTTPS 包地址和更新 XML（appcast），按所选更新库官方工具签名后发布。不得用占位地址、SHA256 校验值或 ZIP 文件冒充有效安装器/更新签名。SHA256SUMS 仅供资源包完整性核对。
