[简体中文](README.md) | [English](README.en.md)

# NekoPlayer

支持 Android、Windows 和 Linux 的音乐播放器，接入网易云与酷狗音乐曲库，并提供账号社区与歌曲分享。

## 跨平台版本

Android 与 Flutter 桌面端共用账号、云端同步、评论与社区能力。`desktop_flutter/` 是 1.2.0 起的正式桌面端，面向 Windows / Linux 的 x86_64、ARM64；原 Compose `desktop/` 已停止功能更新。本地构建使用 `deploy/` 中的低占用脚本，不自动上传或发布。

## 桌面版（1.2.0）

- Windows x64 / ARM64 提供 EXE 安装包；Linux x64 / ARM64 提供 DEB、RPM 与 tar.gz 便携包，基于 Flutter，无需 Java 运行时。
- 支持本地与在线音乐、平台账号、下载、评论、MV、动态歌词、音频缓存、云同步、专业 DSP 音效、系统媒体控制、桌面歌词与系统托盘。
- 新增社区、歌曲分享和 `nekoplayer://` 协议注册；再次打开链接时会转交给已运行的窗口，保持单实例。
- 安装包未配置 Windows 代码签名，系统可能提示未知发布者。
- [桌面端说明](desktop_flutter/README.md)。浮动歌词、悬浮窗音效等设备专属功能仍以 Android 版本为准。

## 特性

### 播放功能
- 🎵 在线播放网易云与酷狗音乐曲库
- 💾 智能缓存，节省流量
- 📥 本地下载，离线播放
- 🎚️ 按歌曲查询实际音质与账户权限：优先默认音质，否则选最高可播放档位；下载单独核验可下载档位，排除试听链接
- 原生 Kotlin 接口直连网易云与酷狗，音乐接口无需在手机内运行 Node.js 或依赖自建音乐 API 代理
- ⏭️ 播放模式切换（顺序/循环/随机/单曲循环）
- ⏩ 播放速度调节（0.5x - 2.0x）

### 音效（v1.0.8）
- **系统音效**：按当前设备音频会话的实际能力显示均衡器、低音增强、环绕、混响和响度控制。
- **专业音效**：本地 C++ DSP，支持单/双声道 PCM16、10 段 EQ、混响空间与阻尼调节。
- **预设**：21 组 EQ 预设，以及按参数文档实现的 20 组签名母带（惜、次元、跨界系列）和母带混合比例。
- 专业链按 EQ 与低音的组合频响预留增益余量，使用带峰值保持的声道联动限幅，减少增强预设的持续削波与低频失真；母带染色补偿驱动增益并阻断直流。
- 播放中切换引擎保持播放器与队列；专业引擎初始化或处理失败时提示错误并原样播放。
- 另外 14 组基础/声境母带等待原始源码接入，暂不开放；不提供真实 AI 推理、杜比解码或 24-bit 升格。

缓冲区、JNI 与 DSP 自动化测试已通过；**真机播放和不同设备系统音效仍需验收**。详见[技术规格与验证状态](docs/AUDIO_EFFECTS_SPEC_PROGRESS.md)。

### 界面设计
- 🎨 Material Design 3 设计语言
- 🌃 全局壁纸与动态模糊背景
- 💿 唱片旋转动画与歌词视图切换
- 🎭 可调节的控件透明度
- ♿ 完整的无障碍支持（TalkBack）
- 🌐 多语言界面：支持简体中文、繁體中文、English、日本語，默认跟随系统，可在「设置」中切换

### 歌词功能
- 📜 滚动歌词显示
- 🎤 逐字高亮（卡拉OK模式）
- 🌐 翻译歌词支持
- 🎈 悬浮歌词窗口
- 📱 双行/单行显示切换

### 个性化
- 🖼️ 自定义全局背景壁纸
- 🎨 封面/壁纸双背景源
- 🌫️ 可调节模糊强度与遮罩透明度
- 🎛️ 细粒度的界面控件透明度设置

### 账户功能
- 👤 网易云账户登录；酷狗支持验证码与酷狗 App 扫码登录
- 酷狗原版/概念版独立保存会话与设备 Cookie；扫码轮询仅在确认授权后完成登录
- 酷狗短信发送及令牌刷新使用证书匹配的 HTTPS 登录域名；区分安全连接、DNS、超时和业务错误
- 酷狗歌曲保留 hash 和来源，播放、歌词与离线索引按音乐源解析
- ☁️ 云端同步播放历史、收藏、自建歌单、网易云 Cookie，以及酷狗原版/概念版完整 Cookie 与当前平台；本机已有登录优先，空白设备登录本站后自动恢复
- 🔐 Cookie 管理
- 「设置 → 账户信息 → 管理网易云 / 酷狗 Cookie」支持网易云及酷狗；酷狗账号页也提供入口。酷狗原版/概念版可分别查看、复制、保存和清除 Cookie，导入需包含有效格式的 token、userid
- 📜 播放历史记录

### 社区与歌曲分享（1.2.0）
- 💬 一对一私信：文字与歌曲卡片，打开会话时实时推送，其余时间每 10 秒同步；断线后按消息序列补齐。
- 👥 关注 / 粉丝、关注动态、用户搜索与公开主页；可设置私信接收范围（所有人 / 仅关注的人）并拉黑用户。
- 🔔 Android 登录后运行可关闭的后台消息推送前台服务，应用在后台时显示系统通知；桌面端运行期间保持实时连接并使用系统通知。
- 🔗 生成公开歌曲分享链接，网页、Android、桌面端均可查看；未登录也能播放网易云歌曲。
- 🎛️ 分享时可选择携带分享者、留言、封面、专辑、歌词片段和播放进度；未选中的字段不会出现在接口与分享页。
- 📲 Android 支持 `nekoplayer://share|chat|user` 与 `https://player.nekoh2o.top/s/...` 深链；桌面安装包注册自定义协议并保持单实例转发。
- 🌐 网页播放器的分享页提供网页播放、复制链接、系统分享和「在 NekoPlayer 中打开」。

### 歌曲评论（1.0.9）
- 播放页提供网易云、酷狗、本站三个评论入口；跨平台同名歌曲先选择对应版本。
- 网易云与本站支持分页、楼层回复、发送、点赞/取消点赞和删除本人评论；操作需登录对应站点。
- 酷狗支持分页查看、发送和楼层回复。**酷狗点赞与删除尚缺已验证的接口协议，当前不开放这两项操作**。
- 本站评论使用独立 SQLite 数据库；账号身份由服务端验证，删除本人评论后保留已有楼层回复。

### 高级功能
- ⏰ 定时关闭
- 🔋 电池优化豁免申请
- 🎧 从最近任务划掉界面时，正在播放的后台会话继续运行，非播放会话安全退出
- 📁 自定义下载目录（支持 MediaStore 与 SAF）
- 🗂️ 缓存与下载管理

## 系统要求

- Android 7.0 (API 24) 或更高版本
- 建议 Android 10+ 以获得最佳存储体验

## 构建

### 前置要求
- JDK 17
- Android SDK
- Android NDK 与 CMake 3.22.1
- 使用仓库提供的 Gradle Wrapper

### 编译步骤

```bash
# 克隆仓库
git clone https://github.com/H2Omeow/NekoPlayer.git
cd NekoPlayer

# 编译 Debug 版本
./gradlew assembleDebug

# 编译 Release 版本（需要配置签名）
./gradlew assembleRelease
```

### Release 签名配置

正式签名通过以下环境变量注入：

```properties
KEYSTORE_FILE=/path/to/your/keystore.jks
KEYSTORE_PASSWORD=your_store_password
KEY_ALIAS=your_key_alias
KEY_PASSWORD=your_key_password
```

未配置时本地 release 使用 debug 签名。GitHub Actions 从仓库 Secrets 读取正式签名，推送 `v*` 标签自动构建并更新 Release。

### 桌面端构建

Flutter 桌面端使用仓库内的低占用脚本，需要 Flutter SDK、CMake、Ninja、GTK 3 与同架构 libmpv：

```bash
# 设置 Flutter SDK 路径
export FLUTTER_BIN=/path/to/flutter

./deploy/flutter-low-resource.sh analyze
./deploy/flutter-low-resource.sh test
./deploy/flutter-low-resource.sh build linux --release

# 生成 DEB / RPM / tar.gz（RPM 需要 rpmbuild）
cd desktop_flutter
python3 tool/package_release.py linux-x64 --bundle build/linux/x64/release/bundle
```

Windows 安装包由 GitHub Actions 构建；本地要求与打包说明见 [desktop_flutter/README.md](desktop_flutter/README.md)。

## 下载

前往 [Releases](../../releases) 页面下载最新版本。

## 技术栈

- **语言**: Kotlin + C++（JNI 音效处理）
- **UI 框架**: Jetpack Compose
- **播放器**: Media3 (ExoPlayer)
- **网络**: Retrofit + OkHttp
- **图片加载**: Coil
- **异步**: Coroutines + Flow
- **依赖注入**: 手动依赖注入
- **持久化**: DataStore + SharedPreferences

## 架构

- **MVVM 架构模式**
- **单 Activity 多 Composable 设计**
- **Repository 层数据抽象**
- **Media3 MediaSession 后台播放**

## 许可证

仓库尚未声明整体授权许可证。原生音乐接口参考项目的 MIT 许可全文随 APK 打包于 app/src/main/assets/licenses/，请同时遵循这些许可。

## 隐私说明

- 本应用在用户通过 SSO 账户中心登录后，会将用户的播放记录、收藏、歌单等数据保存到本站服务器
- 社区私信、关注关系与分享记录保存在本站服务器；公开主页只展示昵称、头像和简介，不展示邮箱、第三方绑定或令牌
- 分享链接按发送时选择的字段公开展示，不包含音频文件；删除分享或撤回消息后，链接与卡片随即失效
- **网易云 Cookie 与酷狗原版/概念版登录 Cookie 会加密保存到云端**，用于多端同步；网易云和酷狗原生接口由 App 使用对应凭据访问，聚合音源统一经本站代理访问
- 本站不保证数据绝对安全（如服务器遭到入侵等不可控因素）
- 使用本站的云端同步功能即默认接受上述风险
- 如不希望数据上传至服务器，请勿登录账户或使用云端同步与社区功能

## 免责声明

本项目仅供学习交流使用，音乐版权归网易云音乐及原作者所有。请支持正版音乐。

## 贡献

欢迎提交 Issue 和 Pull Request。

## 酷狗 API 部署

1.0.8 使用服务端 API。原版与概念版需要不同进程，平台由启动参数决定。

在 KuGouMusicApi 目录运行；现有原版端口保持 4000：

    HOST=127.0.0.1 pm2 start app.js --name KuGouMusicApi-lite -- --platform=lite --port=4001
    pm2 save

将 deploy/kugou-platform-router.cjs 复制到 API 目录为 platform-router.cjs，在 server.js 创建 Express 应用后、解析请求体和缓存中间件之前加入：

    if (process.env.platform !== 'lite') app.use(require('./platform-router.cjs')());

原 /kgapi/ 代理地址保持有效：platform=0 使用原版，platform=1 转发到本机概念版 4001。4001 只监听回环地址。更新上游 API 后需确认此路由仍安装。路由回归可运行 node --test deploy/kugou-platform-router.test.cjs。

将 deploy/kugou-search.cjs 复制为 API 的 module/search.js 后重启两个酷狗进程。歌曲搜索使用带 Web 签名的 HTTPS 公共目录入口，修复 Android 搜索返回业务错误 152；返回歌曲仍由各平台登录会话验证播放和下载权限。

验证码安全验证、短信限流和账号会员权限以酷狗服务端结果为准；应用不会将接口错误当作登录成功。旧收藏若未保存酷狗 hash，需要重新搜索添加。

## 原生接口与本站评论部署

1.0.9 将现有音乐接口移植到 Kotlin/OkHttp，包含网易云 weapi/eapi 与酷狗原版/概念版签名、设备注册和会话隔离。参考 NeteaseCloudMusicApi 4.32.0、KuGouMusicApi 1.6.2，以及 KuGouMusicApi b624d645 的评论发送/回复实现。本站登录、云同步和本站评论仍需本站服务器。

本站 Node.js 服务需要 Node 24（node:sqlite）。将 deploy/site-comments.mjs 放到服务目录，创建 Express 应用并安装现有会话中间件后、SPA 兜底路由之前调用：

    import { installSiteComments } from './site-comments.mjs';
    installSiteComments(app, { dataRoot, resolveUser, jsonParser: express.json({ limit: '16kb' }) });

resolveUser(req) 必须验证请求的 Bearer JWT 并返回 { user: { id, username } }；无效凭据返回 null。写操作只接受经过验证的 Bearer 身份。数据库位于 dataRoot/comments/comments.sqlite，备份时保留数据库及 WAL 或使用 SQLite 一致性备份。

测试：node --test deploy/*.test.*；Android 回归：./gradlew :app:testDebugUnitTest :app:lintDebug。设置 NATIVE_API_SMOKE=1 可额外运行不发送短信/评论的公开接口联通测试。网易云游客注册有时返回 code=400，上游 Node 模块亦复现，随后原生重测成功；应用保留真实错误，不生成假登录状态。扫码确认、真实账号评论写入、会员歌曲及 Android 真机播放仍需按对应账户与设备验收。

## 致谢

- [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)
- [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi)
- [Material Design 3](https://m3.material.io/)
- [Jetpack Compose](https://developer.android.com/jetpack/compose)
- [Media3](https://developer.android.com/guide/topics/media/media3)
- [Coil](https://coil-kt.github.io/coil/)

## 音源与 MV（1.1.0-pre）

- 音乐页新增独立的 **音源** 分组，可单独切换酷狗、酷我、网易、QQ、咪咕和 B 站，并在歌曲卡片显示来源。
- 音源地址只保存在本站服务端，客户端不会内置上游接口；必须登录本站账号，所有请求使用短期密钥、随机数和 HMAC 签名。
- 全站共享每日 10,000 次音乐链接额度；歌词和 MV 不占额度。本站统计页展示今日总量、剩余额度和用户调用次数。
- 网易云、酷狗和音源均提供 MV 搜索与播放入口。
