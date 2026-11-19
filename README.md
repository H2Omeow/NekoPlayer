[简体中文](README.md) | [English](README.en.md)

# NekoPlayer

面向 Android、Windows 与 Linux 的音乐与视频播放器。音乐侧接入网易云、酷狗及聚合音源，视频侧直连 B 站；同时提供账号同步、社区、文件云存储与管理后台。

当前版本 **1.4.4**（Android `versionCode 32`）。桌面端自 1.2.0 起使用 Flutter 实现，原 Compose `desktop/` 不再更新功能。

## 平台与产物

| 平台 | 产物 | 说明 |
| --- | --- | --- |
| Android 7.0+（API 24） | `NekoPlayer-vX.Y.Z.apk` | Media3 / ExoPlayer，支持后台播放与系统媒体控制 |
| Windows x64 / ARM64 | `*-windows-*.setup.exe` | Flutter 桌面端，安装包未做代码签名，系统可能提示未知发布者 |
| Linux x64 / ARM64 | `.deb` / `.rpm` / `.tar.gz` | 依赖 GTK 3、libmpv；AMD64 与 ARM64 分别构建 |

每个 Release 附带 `SHA256SUMS`，下载后可用于校验完整性。

## 功能

### 视频（B 站）

- 独立视频页：搜索、推荐、热门、分类筛选、无限滚动；支持直接粘贴 BV 号。
- 播放页：16:9 播放器、清晰度切换、倍速、全屏、进度记忆、相关推荐、评论、简介。
- 弹幕：滚动/顶部/底部三种模式，按播放进度渲染；可调字号、速度、透明度、显示区域、同屏密度、描边与阴影，支持彩色弹幕、屏蔽词与合并重复。
- 账号：App 扫码、网页登录、Cookie 导入三种 B 站登录方式；登录后可发弹幕、点赞、投币、收藏与关注。
- 播放失败时自动重取直链并逐级降低清晰度；媒体请求携带 `Referer`、`Origin`、桌面 User-Agent 与初始 `Range` 头。

### 音乐

- 在线播放网易云与酷狗曲库，支持本地下载、缓存、播放队列、播放模式与倍速。
- 音源分组：酷狗、酷我、网易、QQ、咪咕、B 站可单独切换，歌曲卡片显示来源。
- 歌词：滚动、逐字高亮、翻译、悬浮歌词与桌面歌词。
- 音效：系统音效按设备音频会话能力显示；专业音效为本地 C++ DSP，含 10 段 EQ、混响与 20 组签名母带预设。
- 账户：网易云登录、酷狗验证码与 App 扫码登录，原版/概念版会话独立保存。

### 云存储

- 文件直传对象存储（S3 兼容，私有桶 + 预签名），超过 5MB 自动分片，支持失败中止与重传；服务端不落盘。
- 额度：免费用户 3.25G 存储、每月 3.25G 流量、50 份文件；视频 ≤50MB、图片 ≤5MB、音乐 ≤25MB、自定义文件 ≤1G（占 5 份）。
- 赞赏用户：32.5G 存储、每月 50G 流量，不限份数与单文件大小，文件不参与过期清理。
- 分享：应用内分享（下载扣分享者一半流量）或直链分享（免登录下载，扣全额流量），可选 1/7/30 天有效期。
- 云存储需要先绑定森空岛账号，支持扫码、手机验证码、手机密码与网页登录兜底。
- 免费用户连续 180 天未登录会清理上传文件（歌单、收藏、播放记录不受影响），清理前 7 天站内信提醒。

### 社区

- 一对一私信（文字与歌曲卡片）、关注与粉丝、关注动态、用户搜索与公开主页。
- 会话与主页显示在线状态（15 秒心跳，70 秒窗口）。
- 公开歌曲分享页支持网页播放与深链跳转；文件可一键分享给好友。
- 私信接收范围、拉黑、消息推送与未读统计。

### 同步

- 云端同步播放历史、收藏、自建歌单、网易云 Cookie，以及酷狗原版/概念版完整 Cookie 与当前平台。
- 本机已有登录优先；空白设备登录后自动恢复。
- Cookie 与同步数据加密保存到服务端；同步接口使用分区乐观锁，冲突返回 409。

## 下载

前往 [Releases](../../releases) 获取最新版本。历史版本按标签归档。

## 构建

### Android

前置：JDK 17、Android SDK、NDK 与 CMake 3.22.1，使用仓库自带 Gradle Wrapper。

```bash
./gradlew assembleDebug
./gradlew assembleRelease   # 需注入签名环境变量
```

签名通过环境变量注入：`KEYSTORE_FILE`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`；未配置时 release 使用 debug 签名。推送 `v*` 标签会触发 GitHub Actions 全平台构建并发布。

### 桌面端（Flutter）

需要 Flutter SDK、CMake、Ninja、GTK 3 与同架构 libmpv：

```bash
export FLUTTER_BIN=/path/to/flutter
./deploy/flutter-low-resource.sh analyze
./deploy/flutter-low-resource.sh test
./deploy/flutter-low-resource.sh build linux --release
```

打包 DEB/RPM/tar.gz 见 [desktop_flutter/README.md](desktop_flutter/README.md)。

### 测试

```bash
./gradlew :app:testDebugUnitTest :app:lintDebug
node --test deploy/*.test.*
```

设置 `NATIVE_API_SMOKE=1` 可额外运行不发送短信与评论的公开接口联通测试。

## 服务端

账号中心、云同步、社区、云存储与 B 站代理均部署在自有服务器，客户端不内置上游密钥。部署方式、环境变量与校验步骤见 [docs/SERVER_DEPLOY.md](docs/SERVER_DEPLOY.md)。

## 技术栈

Kotlin + Jetpack Compose，Media3 / ExoPlayer，Retrofit + OkHttp，Coil，Coroutines/Flow，DataStore，手动依赖注入；音效为 C++ DSP（JNI）。桌面端为 Flutter + media_kit，服务端为 Node.js 24（`node:sqlite`）。

## 隐私与数据

- 登录账户中心后，播放记录、收藏、歌单与 Cookie 会加密保存到本站服务器，用于跨设备同步。
- 云存储文件保存在对象存储，元数据与额度记录保存在服务端数据库；管理后台的写操作会记录审计日志。
- 社区私信、关注关系与分享记录保存在服务端；公开主页只展示昵称、头像与简介。
- 分享链接按发送时选择的字段公开展示，不包含音频文件；删除分享或撤回消息后链接随即失效。
- 网易云与酷狗 Cookie 加密保存用于多端同步；B 站登录态仅保存在本机。
- 本站不保证数据的绝对安全；如不希望数据上传，请不要登录或使用同步、社区与云存储功能。

## 已知限制

- 未登录 B 站时清晰度上限为 720P；1080P 及以上需要登录。
- 桌面安装包未做 Windows 代码签名。
- 酷狗评论的点赞与删除缺少已验证的接口协议，暂不开放。
- 服务端接口依赖上游站点，可能随时调整；应用保留真实错误信息。

## 致谢

- [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)
- [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi)
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [Material Design 3](https://m3.material.io/)、[Jetpack Compose](https://developer.android.com/jetpack/compose)、[Media3](https://developer.android.com/guide/topics/media/media3)

## 许可证与免责声明

仓库尚未声明整体授权许可证；原生音乐接口参考项目的 MIT 许可全文随 APK 打包于 `app/src/main/assets/licenses/`。本项目仅供学习交流，音乐与视频版权归各平台及原作者所有，请支持正版。

## 贡献

欢迎提交 Issue 与 Pull Request；涉及服务端接口的改动请附验证方式。
