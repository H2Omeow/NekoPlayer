# NekoPlayer 1.2.4-fix.2

修复 Windows 无障碍导致的持续闪退，补齐 KDE Wayland 图标与网易云搜索封面。

## Windows

- 在 Flutter 视图窗口创建时即安装消息过滤，在引擎收到任何 `WM_GETOBJECT` 前拦截无障碍请求；收起全屏播放器、调整窗口大小等操作不再触发引擎崩溃。
- 为 x64 引擎增加精确的崩溃兜底：若无障碍桥接仍因空父节点触发访问冲突，将跳过出错节点并继续运行；仅在引擎指令特征完全匹配时生效。
- 默认仍关闭 Flutter 无障碍桥接；需要读屏时可设置 `NEKOPLAYER_ENABLE_ACCESSIBILITY=1`，但可能触发上游引擎缺陷。
- 无障碍拦截和兜底状态写入 `native.log`，便于后续诊断。

## Linux

- 修复 KDE Wayland 下托盘图标缺失：不再依赖异步的 StatusNotifier watcher 属性判断，直接创建 AppIndicator；使用安装包内的 PNG 作为托盘图标，Wayland 下不再创建无法嵌入的 GtkStatusIcon。
- Arch PKGBUILD 将 `libayatana-appindicator` 改为必需依赖；DEB / RPM 增加推荐依赖；DEB / RPM / Arch 安装或升级后刷新桌面数据库与图标缓存。
- tar.gz 便携版启动时会自动注册当前用户的 `.desktop` 与图标（可用 `NEKOPLAYER_NO_DESKTOP_INSTALL=1` 关闭），Wayland 任务栏 / 应用菜单可正确显示 NekoPlayer 图标。

## 网易云

- 网易云搜索接口只返回专辑 `picId` 时，本地按官方规则还原封面地址，搜索结果恢复专辑封面；仍兼容接口返回的 `picUrl` / `blurPicUrl` 并自动升级为 HTTPS。

## Android

- 版本号同步为 1.2.4-fix.2，功能与 1.2.4-fix 相同。

## 安装

- Android：下载 APK 覆盖安装，保持原签名；包含 ARMv7、ARM64、x86、x64。
- Windows：按架构选择 `windows-x64-setup.exe` 或 `windows-arm64-setup.exe`，无需另装 Java。
- Linux：选择对应架构的 DEB / RPM，或解压 tar.gz 运行 `NekoPlayer`。DEB / RPM 已声明 `libgtk-layer-shell0` / `gtk-layer-shell` 依赖；使用 tar.gz 时请自行安装，否则 Wayland 下悬浮歌词无法保存位置。KDE Wayland 托盘还需要 `libayatana-appindicator`，使用 tar.gz 时请自行安装。

下载后可通过 `SHA256SUMS` 校验文件完整性。
