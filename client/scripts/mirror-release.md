# 客户端发行镜像

`mirror-release.py` 由服务器主动读取公开 GitHub Releases，不使用 GitHub PAT、账号 Cookie、SSH 私钥或更新私钥。Python 3.10 及以上环境使用单独虚拟环境安装 `mirror-release-requirements.txt`。固定核验当前正式发行的 14 项资源，不镜像草稿、预发行版或不完整附件。

```sh
python3 mirror-release.py \
  --repository heiyuan0801/huabu-releases \
  --destination /var/lib/huabu-client-updates/public \
  --public-base-url https://image.iyuns.com/client-updates \
  --macos-public-key /opt/huabu-client-updates/macos-update.pub \
  --windows-public-key /opt/huabu-client-updates/windows-update.pem
```

Mac 公钥文件可为 Sparkle `SUPublicEDKey` 的 Base64 文本或 Ed25519 PUBLIC KEY PEM；Windows 使用客户端已内置的 DSA PUBLIC KEY PEM。工具拒绝私钥内容，不生成或读取私钥。DSA 校验沿用现有 WinSparkle 0.8.1 的双 SHA1 协议，不更换签名方案。

默认读取 GitHub 最新正式发行。`--tag client-v0.1.4` 可补齐指定历史版本，但不会把 latest 降级。按已确认规则由 systemd 每 5 分钟执行；每轮不自动重试、不新增网络超时、不删除历史版本。不能将工具启动成功视为同步成功；单进程文件锁阻止任务重入。

## 离线首次导入

`--source-dir /path/to/verified-packages` 完全不请求网络。该目录必须放有公开 GitHub Releases API 响应的 `github-release.json`，保留 tag、正式发行状态及 14 项附件的 `id/name/state/size/digest/browser_download_url`，不能用自行填写的摘要代替。安装包、JSON、两份 XML 和原始 SHA256SUMS 可以位于其子目录，但每个文件名只能出现一次。现有本地 packages 目录还需补入实际发行的 SHA256SUMS 与 API 快照。

网络模式把来源信息保存在每个版本目录的 `source/github-release.json`，省略变化的下载计数；原 JSON、XML 与 SHA256SUMS 同样保存在 `source/`。GitHub 附件必须全部为 uploaded，逐一校验 API SHA256、长度与原始 SHA256SUMS，然后使用公钥验证 Mac ZIP 和 Windows 安装器签名。服务器只重写镜像 JSON/XML 的 URL，保持安装包字节与签名不变，并为镜像生成新的 SHA256SUMS。

生产首次从 GitHub 下载完整发行时曾只有约 8–15 KB/s，因此使用 Mac 已核验的同一正式发行资源离线初始化。遇到类似网络情况，可在网络正常的机器取得真实 GitHub API 快照与全部 14 项原始资源，再传到服务器的非公开暂存目录；使用 `--source-dir` 执行上述完整校验后才切换 latest，不能直接复制未核验文件到 `public/` 或自行改写摘要。首次导入完成后，后续检查仍由 GitHub 优先的计划任务执行。

## 静态目录与切换

```text
/var/lib/huabu-client-updates/public/
  releases/client-v0.1.4/       # 校验完的只读文件及来源记录
  latest -> releases/client-v0.1.4
  index.html -> latest/index.html
  flutter-release.json -> latest/flutter-release.json
  appcast-macos.xml -> latest/appcast-macos.xml
  appcast-windows.xml -> latest/appcast-windows.xml
  history.html                 # 所有已镜像版本的本站下载入口与日志
```

目标目录是专用公开静态目录，不要指向现有网站根目录。staging 和锁放在目标目录的父目录，不能暴露到 Nginx 公共路径。完成全部校验后，将 staging 原子重命名为版本目录，写好安全转义的日志页面，再原子替换 latest 符号链接；同 tag 不同内容拒绝覆盖。失败不会切换 latest，已完成的只读版本可在下一次执行继续核验并激活。历史日志单独原子更新，不改写旧版本的文件。

Nginx 需直接静态提供上述目录，保留 HEAD/Range 支持。latest 入口和 history.html 禁止缓存，不允许找不到的安装包回退为网站 HTML。不能把目录重定向回 GitHub，或放入仅在构建时复制的 Web 镜像中。所有镜像链接使用 `--public-base-url` 的 HTTPS 地址。

页面复用同源 `/downloads/app-icon.png` 品牌图标，不把 PNG 加入发行资源。部署的公开入口为 `/client-updates/`，仅公开 `public/`，不得暴露父目录中的 staging、锁和服务端配置。

## systemd 与 Nginx 部署

安装脚本、依赖文件与两份公钥到 `/opt/huabu-client-updates/`，在其 `venv/` 安装 requirements。创建无登录权限的专用用户和组 `huabu-updates`；将同目录的 `huabu-client-updates.service`、`huabu-client-updates.timer` 安装至 `/etc/systemd/system/`。服务使用 `StateDirectory=huabu-client-updates` 创建可写状态目录，代码、虚拟环境和公钥仍由管理员维护，不能放入公开目录。

先完成首次离线导入或手动执行 service 并核对本站文件，再启用已确认的每 5 分钟任务：

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now huabu-client-updates.timer
sudo systemctl status huabu-client-updates.timer
sudo journalctl -u huabu-client-updates.service
```

timer 使用 `OnCalendar=*-*-* *:0/5:00` 和 `Persistent=true`；5 分钟是检查间隔，不是同步完成时限，不能据此终止仍在下载或验证的任务。单进程锁阻止重入，单轮失败退出后保留旧版本，不在脚本内重试。网络问题修复后可手动启动 service 或等待下一轮。历史目录不会自动清理。

当前生产采用外层域名 Nginx 直接静态 alias 到 `/var/lib/huabu-client-updates/public/`，与业务前端镜像及数据库独立；仅将下面的位置配置合并到既有站点 `server` 内：

```nginx
location = /client-updates {
    return 301 /client-updates/;
}
location ^~ /client-updates/ {
    alias /var/lib/huabu-client-updates/public/;
    index index.html;
    autoindex off;
    add_header Cache-Control "no-cache";
}
```

普通 Web 构建、重建容器和更新源码不得清空或覆盖 `/var/lib/huabu-client-updates/`，也不能用构建时静态快照替换运行中的 latest。备份与恢复镜像目录时保留历史文件、权限及符号链接。

若选择由容器内 Nginx 提供资源，项目 Compose 的 `app` 服务可只读挂载 `${HUABU_CLIENT_UPDATES_DIR:-../client-updates}/public:/data/client-updates:ro`；设置 `HUABU_CLIENT_UPDATES_DIR=/var/lib/huabu-client-updates` 并使用 `/data/client-updates/` alias。此方式是可选接入，不是当前生产公开入口的依赖；无论采用哪种方式，都只公开 `public/`，不挂载或暴露包含锁和 staging 的父目录。

当前 appcast 只签安装包，未启用 Sparkle `SURequireSignedFeed`；未来启用 feed 签名时，必须在镜像 URL 改写后签署 XML，不得继续复用原 feed 签名。工具没有验证平台发行身份或公证，也不会把未签名 iOS 归档加入安装入口。
