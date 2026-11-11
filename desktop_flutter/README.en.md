[English](README.en.md) | [简体中文](README.md)

# NekoPlayer Flutter Desktop

The official desktop app since 1.2.0, targeting x86_64 and ARM64 on Windows / Linux; 32-bit is not supported. The original Compose `desktop/` version no longer receives feature updates.

The app includes a local music library, platform accounts with the system keyring, account music libraries, categorized search, multi-source resolution, translated lyrics, comments, MVs, downloads, audio/lyrics offline caching, manual cloud sync, and legacy backup import. It also offers a separate player background, the original C++ DSP, system media controls, desktop lyrics, and an optional tray. 1.2.0 adds private messages/following/feed, song share links, `nekoplayer://` protocol registration, single-instance link forwarding, and system notifications; share links can play NetEase Cloud songs even when logged out. 1.2.1 adds the actual audio-quality label, saved floating-lyric position, a configurable tray menu, and play/pause fade, and fixes Wayland lyric transparency and taskbar icons on Linux / Windows. 1.2.2 adds performance and dynamic-lyrics quality settings that adapt to 4K / high-DPI displays, and fixes blank embedded dynamic lyrics under high Windows display scaling.

- 🌐 Multilingual UI: supports 简体中文, 繁體中文, English, and 日本語; defaults to the system language and can be changed in Settings.

On Linux, the tray prefers the system Ayatana/AppIndicator; when no usable tray is available, the main window is not hidden. Full real-network playback still requires valid account entitlements and device verification, and Windows and ARM64 have not yet been verified on physical hardware. Configuration is isolated from the original version.

Uses Flutter 3.47.7. Run from the repository root; `FLUTTER_BIN` can specify the SDK path:

```sh
./deploy/flutter-low-resource.sh pub get
./deploy/flutter-low-resource.sh analyze
./deploy/flutter-low-resource.sh test
./deploy/flutter-low-resource.sh run -d linux
```

Linux requires GTK 3, Clang, CMake, Ninja, pkg-config, and the runtime and development packages for libmpv, libsecret, and libepoxy built for the same architecture; account storage requires an available and unlocked Secret Service keyring. Windows requires the Visual Studio C++ toolchain, CMake 3.31+, and 7-Zip; the Windows audio/video plugin is pinned to an official Git commit that includes ARM64 support, so do not delete or overwrite it directly. The professional DSP also requires FFmpeg / ffprobe built for the same architecture; the miniaudio headers are fetched by CMake at a fixed version and SHA256. The four native targets of v1.2.2 have been built by CI; locally, it is still recommended to package with `tool/package_release.py` and then perform launch acceptance testing. On Wayland, saving the floating-lyric position requires `gtk-layer-shell`; the DEB / RPM packages declare this dependency.

Generate a Linux installer:

```sh
cd desktop_flutter
python3 tool/package_release.py linux-x64 --bundle build/linux/x64/release/bundle
# 或 linux-arm64
```

DEB / RPM installs the `.desktop` file, registers `x-scheme-handler/nekoplayer`, and updates the desktop database after installation; the Windows installer registers the `nekoplayer://` protocol under HKCU and cleans it up on uninstall. The default association for `x-scheme-handler` is determined by the desktop environment or `xdg-mime`; some environments ask how to handle a link the first time it is opened.

Windows ARM64 also requires `NEKO_WINDOWS_ARM64_ANGLE_DIR`, providing same-architecture ANGLE `include/`, `lib/` import libraries, and root-directory DLLs. It has been verified that the upstream default ANGLE package is still x64, and the build explicitly prevents mixing them; support cannot be claimed as complete when ARM64 dependencies are missing. You can use `python3 desktop_flutter/tool/check_artifact.py <target> <executable and all dynamic libraries>` to check the actual artifacts.
