# NekoPlayer 1.2.3

修复 1.2.2 动态歌词帧率限制导致的只显示第一帧或空白，并记住桌面端主窗口大小。

## 桌面端

- 修复动态歌词打开后长时间空白或停在第一帧：帧率限制改为每个动画回调独立计帧，不再互相抢占；应用内嵌视图和浏览器打开的页面均会持续刷新。
- 主窗口关闭时保存窗口大小和最大化状态，Windows 与 Linux 重启后恢复；Linux 在调整大小后也会自动保存，异常退出后可恢复。
- 1.2.2 的动态歌词画质（渲染比例、帧率、效果）和性能档位继续可用。

## Android

- 版本号同步为 1.2.3，功能与 1.2.2 相同。

## 安装

- Android：下载 APK 覆盖安装，保持原签名；包含 ARMv7、ARM64、x86、x64。
- Windows：按架构选择 `windows-x64-setup.exe` 或 `windows-arm64-setup.exe`，无需另装 Java。
- Linux：选择对应架构的 DEB / RPM，或解压 tar.gz 运行 `NekoPlayer`。DEB / RPM 已声明 `libgtk-layer-shell0` / `gtk-layer-shell` 依赖；使用 tar.gz 时请自行安装，否则 Wayland 下悬浮歌词无法保存位置。

下载后可通过 `SHA256SUMS` 校验文件完整性。
