# NekoPlayer 1.2.0

账户中心升级为音乐社区，并加入可跳转客户端的歌曲分享链接。

## 社区与账号

- 网页播放器、Android、Flutter 桌面端新增「社区」：一对一私信（文字与歌曲卡片）、关注 / 粉丝、关注动态、用户搜索和公开主页。
- 私信默认每 10 秒同步；打开会话时使用实时推送。消息按序列补齐，断线后自动重连。
- Android 新增可关闭的后台私信推送前台服务：登录后保持实时连接，应用在后台时显示系统通知，点击进入对应会话或分享。
- 桌面端登录期间保持实时连接，系统通知可点击打开对应会话。
- 可在个人资料中设置私信接收范围（所有人 / 仅关注的人），支持拉黑。

## 歌曲分享

- 歌曲卡片、播放器与全屏播放器新增分享入口，可生成公开分享链接；未登录也可查看和播放网易云歌曲。
- 分享时可选择携带分享者、留言、封面、专辑、歌词片段和播放进度；关闭的字段不会出现在接口和分享页中。
- 分享页提供网页播放、复制链接、系统分享，以及「在 NekoPlayer 中打开」。
- Android 支持 `nekoplayer://share`、`nekoplayer://chat`、`nekoplayer://user` 与 `https://player.nekoh2o.top/s/...` 深链；Linux DEB / RPM 与 Windows 安装包注册 `nekoplayer://` 协议，桌面端保持单实例并把链接转交给已运行的窗口。

## 安装

- Android：下载 APK 覆盖安装，保持原签名；包含 ARMv7、ARM64、x86、x64。
- Windows：按架构选择 `windows-x64-setup.exe` 或 `windows-arm64-setup.exe`，无需另装 Java。安装包未配置 Windows 代码签名，系统可能提示未知发布者。
- Linux：选择对应架构的 DEB / RPM，或解压 tar.gz 运行 `NekoPlayer`。需要 glibc 2.35+、GTK3、libmpv、libsecret、libepoxy、GnuTLS；DEB / RPM 声明了运行依赖。便携包在 Ubuntu / Debian 上可先安装 `libgtk-3-0 libmpv2 libsecret-1-0 libepoxy0 libgnutls30`（Ubuntu 22.04 使用 `libmpv1`）。

## 说明

- 分享只保存歌曲标识与元数据，不包含音频文件；接收端使用自己的账号解析播放。部分音源可能要求登录对应平台账号。
- Android 厂商的后台限制可能终止常驻连接；重新打开应用后会自动恢复。可随时在「设置 → 社区 → 后台消息推送」关闭。
- 网页播放器目前只能直接播放网易云歌曲，其他音源分享会提示在客户端中打开。

下载后可通过 `SHA256SUMS` 校验文件完整性。
