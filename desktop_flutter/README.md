[简体中文](README.md) | [English](README.en.md)

# NekoPlayer Flutter 桌面端

1.2.0 起的正式桌面端，面向 Windows / Linux 的 x86_64、ARM64，不支持 32 位。原 `desktop/` Compose 版本已停止功能更新。

已接入本地音乐库、平台账号与系统密钥环、账号音乐库、分类搜索、多音源解析、翻译歌词、评论、MV、下载、音频/歌词离线缓存、手动云同步和旧版备份导入；另有独立播放器背景、原版 C++ DSP、系统媒体控制、桌面歌词与可选托盘。1.2.0 新增私信/关注/动态、歌曲分享链接、`nekoplayer://` 协议注册、单实例链接转发和系统通知；分享链接在未登录时也可播放网易云歌曲。1.2.1 新增实际音质显示、悬浮歌词位置记忆、可配置托盘菜单和播放 / 暂停淡入淡出，并修复 Wayland 悬浮歌词透明与 Linux / Windows 任务栏图标。1.2.2 新增性能与动态歌词画质设置，自动适配 4K / 高缩放设备，并修复 Windows 高缩放下内嵌动态歌词空白。

- 🌐 多语言界面：支持简体中文、繁體中文、English、日本語，默认跟随系统，可在「设置」中切换。

Linux 托盘优先使用系统 Ayatana/AppIndicator，缺少可用托盘时不隐藏主窗口。完整实网播放仍需有效账号权益及设备验证，Windows 和 ARM64 尚未实机验收。配置与原版隔离。

使用 Flutter 3.47.7。在仓库根目录运行，`FLUTTER_BIN` 可指定 SDK 路径：

```sh
./deploy/flutter-low-resource.sh pub get
./deploy/flutter-low-resource.sh analyze
./deploy/flutter-low-resource.sh test
./deploy/flutter-low-resource.sh run -d linux
```

Linux 需要 GTK 3、Clang、CMake、Ninja、pkg-config，以及同架构 libmpv、libsecret、libepoxy 的运行库和开发包；账号存储需要可用且已解锁的 Secret Service 密钥环。Windows 需要 Visual Studio C++ 工具链、CMake 3.31+、7-Zip；Windows 音视频插件固定到官方含 ARM64 支持的 Git 提交，勿直接删除覆盖。专业 DSP 另需同架构 FFmpeg / ffprobe；miniaudio 头文件由 CMake 按固定版本和 SHA256 获取。v1.2.2 的四个原生目标已由 CI 构建，本地仍建议通过 `tool/package_release.py` 打包后做启动验收。Wayland 下要让悬浮歌词保存位置，需要 `gtk-layer-shell`；DEB / RPM 已声明该依赖。

生成 Linux 安装包：

```sh
cd desktop_flutter
python3 tool/package_release.py linux-x64 --bundle build/linux/x64/release/bundle
# 或 linux-arm64
```

DEB / RPM 会安装 `.desktop` 文件、注册 `x-scheme-handler/nekoplayer`，并在安装后更新桌面数据库；Windows 安装包在 HKCU 下注册 `nekoplayer://` 协议，卸载时清理。`x-scheme-handler` 的默认关联由桌面环境或 `xdg-mime` 决定，部分环境首次打开链接时会询问处理方式。

Windows ARM64 还必须设置 `NEKO_WINDOWS_ARM64_ANGLE_DIR`，提供同架构 ANGLE 的 `include/`、`lib/` 导入库与根目录 DLL。已核实上游默认 ANGLE 包仍为 x64，构建会明确阻止混用；缺少 ARM64 依赖时不能宣称支持完成。可用 `python3 desktop_flutter/tool/check_artifact.py <目标> <可执行文件及全部动态库>` 检查实际产物。
