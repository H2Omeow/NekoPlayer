# NekoPlayer 1.2.4-fix

修复 Windows 端在屏幕阅读器、教学白板、录屏 / 自动化工具等无障碍客户端访问窗口时，Flutter 引擎无障碍桥接空指针导致的闪退。

## 桌面端

- 修复 Windows 端连接无障碍（UIA / MSAA）客户端后 `flutter_windows.dll` 访问冲突崩溃的问题。该问题由 Flutter 3.47.7 引擎在 `AccessibilityBridge::CreateRemoveReparentedNodesUpdate` 中解引用空的 AXNode 父节点引起（flutter/flutter#175041），并非应用逻辑错误。
- 默认不再向 Windows 提供 UIA 根对象和 MSAA 客户端对象，避免引擎启用存在缺陷的无障碍桥接；应用启动、播放和其他功能不受影响。
- 这也会让 Windows 读屏软件无法识别 Flutter 界面。如需读屏等无障碍访问，可在启动前设置环境变量 `NEKOPLAYER_ENABLE_ACCESSIBILITY=1` 恢复旧行为，但仍可能触发上述引擎崩溃。
- 日志会输出 `[a11y]` 前缀说明当前无障碍状态，便于排查。
- Linux 与 Android 版本号同步为 1.2.4-fix，功能与 1.2.4 相同。

## 安装

- Android：下载 APK 覆盖安装，保持原签名；包含 ARMv7、ARM64、x86、x64。
- Windows：按架构选择 `windows-x64-setup.exe` 或 `windows-arm64-setup.exe`，无需另装 Java。
- Linux：选择对应架构的 DEB / RPM，或解压 tar.gz 运行 `NekoPlayer`。DEB / RPM 已声明 `libgtk-layer-shell0` / `gtk-layer-shell` 依赖；使用 tar.gz 时请自行安装，否则 Wayland 下悬浮歌词无法保存位置。

下载后可通过 `SHA256SUMS` 校验文件完整性。
