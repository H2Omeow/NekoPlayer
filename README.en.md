[English](README.en.md) | [简体中文](README.md)

# NekoPlayer

A music player for Android, Windows, and Linux that connects to the NetEase Cloud Music and KuGou Music libraries and offers accounts, community, and song sharing.

## Cross-platform versions

Android and the Flutter desktop app share accounts, cloud sync, comments, and community features. `desktop_flutter/` has been the official desktop app since 1.2.0 and targets x86_64 and ARM64 on Windows / Linux; the original Compose `desktop/` app no longer receives feature updates. Local builds use the low-resource scripts in `deploy/` and do not upload or publish automatically.

## Desktop app (1.2.0)

- EXE installers are provided for Windows x64 / ARM64; DEB, RPM, and tar.gz portable packages are provided for Linux x64 / ARM64. Built on Flutter, with no Java runtime required.
- Supports local and online music, platform accounts, downloads, comments, MVs, synced lyrics, audio caching, cloud sync, professional DSP audio effects, system media controls, desktop lyrics, and a system tray.
- Adds community, song sharing, and `nekoplayer://` protocol registration; opening a link again forwards it to the running window and keeps a single instance.
- The installers are not Windows code-signed, so the system may warn about an unknown publisher.
- [Desktop documentation](desktop_flutter/README.en.md). Device-specific features such as floating lyrics and floating-window audio effects are still governed by the Android version.

## Features

### Playback
- 🎵 Stream music from the NetEase Cloud Music and KuGou Music libraries
- 💾 Smart caching to save data
- 📥 Local downloads for offline playback
- 🎚️ Query the actual audio quality and account permissions per song: prefer the default quality, otherwise choose the highest playable tier; downloads separately verify available download tiers and exclude preview links
- Native Kotlin interfaces connect directly to NetEase Cloud and KuGou, so music APIs do not require Node.js on the phone or a self-hosted music API proxy
- ⏭️ Playback mode switching (sequential/loop/shuffle/repeat one)
- ⏩ Playback speed adjustment (0.5x - 2.0x)

### Audio effects (v1.0.8)
- **System audio effects**: Show equalizer, bass boost, surround, reverb, and loudness controls according to the actual capabilities of the current device's audio session.
- **Professional audio effects**: Local C++ DSP supporting mono/stereo PCM16, a 10-band EQ, and reverb space and damping adjustment.
- **Presets**: 21 EQ presets, plus 20 signature masters (Xi, Dimension, and Crossover series) implemented according to the parameter documentation, and master mix ratios.
- The professional chain reserves gain headroom based on the combined frequency response of EQ and bass, and uses channel-linked limiting with peak hold to reduce sustained clipping and low-frequency distortion from boosted presets; master coloration compensates the drive gain and blocks DC.
- Switching engines during playback preserves the player and queue; if the professional engine fails to initialize or process, an error is shown and playback continues unchanged.
- Another 14 basic/soundscape masters are awaiting integration of the original source code and are not yet available; no real AI inference, Dolby decoding, or 24-bit upscaling is provided.

Automated buffer, JNI, and DSP tests have passed; **real-device playback and system audio effects on different devices still require acceptance testing**. See [Technical specification and verification status](docs/AUDIO_EFFECTS_SPEC_PROGRESS.md).

### Interface design
- 🎨 Material Design 3 design language
- 🌃 Global wallpaper and dynamic blur background
- 💿 Rotating album art animation and lyrics view switching
- 🎭 Adjustable control opacity
- ♿ Full accessibility support (TalkBack)
- 🌐 Multilingual UI: supports 简体中文, 繁體中文, English, and 日本語; defaults to the system language and can be changed in Settings

### Lyrics
- 📜 Scrolling lyrics
- 🎤 Word-by-word highlighting (karaoke mode)
- 🌐 Translated lyrics support
- 🎈 Floating lyrics window
- 📱 Two-line/single-line display toggle

### Personalization
- 🖼️ Custom global background wallpaper
- 🎨 Dual background sources: cover/wallpaper
- 🌫️ Adjustable blur strength and overlay opacity
- 🎛️ Fine-grained UI control opacity settings

### Account features
- 👤 NetEase Cloud account login; KuGou supports verification-code login and QR-code login via the KuGou app
- The KuGou original and concept editions store sessions and device cookies independently; QR-code polling completes login only after authorization is confirmed
- KuGou SMS sending and token refresh use certificate-matched HTTPS login domains; secure-connection, DNS, timeout, and business errors are distinguished
- KuGou tracks retain their hash and source, and playback, lyrics, and offline indexing are resolved according to the music source
- ☁️ Cloud sync of playback history, favorites, user-created playlists, NetEase Cloud cookies, and the complete cookies of both the KuGou original and concept editions plus the current platform; existing logins on the local device take precedence, and a blank device automatically restores after logging in to this site
- 🔐 Cookie management
- "Settings → Account info → Manage NetEase Cloud / KuGou cookies" supports NetEase Cloud and KuGou; the KuGou account page also provides an entry point. KuGou original/concept edition cookies can be viewed, copied, saved, and cleared separately; imports must contain a token and userid in valid formats
- 📜 Playback history

### Community and song sharing (1.2.0)
- 💬 One-on-one private messages: text and song cards, pushed in real time while a conversation is open and synchronized every 10 seconds otherwise; after a disconnect, messages are backfilled by sequence.
- 👥 Following / followers, following feed, user search, and public profiles; you can set who can send you private messages (everyone / followed users only) and block users.
- 🔔 On Android after login, a dismissible foreground service for background message push runs and shows system notifications while the app is in the background; the desktop app maintains a real-time connection while running and uses system notifications.
- 🔗 Generate public song share links viewable on the web, Android, and desktop; NetEase Cloud songs can be played even without logging in.
- 🎛️ When sharing, you can choose to include the sharer, message, cover, album, lyric snippet, and playback progress; unselected fields do not appear in the API response or on the share page.
- 📲 Android supports `nekoplayer://share|chat|user` and `https://player.nekoh2o.top/s/...` deep links; desktop installers register the custom protocol and retain single-instance forwarding.
- 🌐 The web player's share page offers web playback, copy link, system share, and "Open in NekoPlayer".

### Song comments (1.0.9)
- The playback page provides three comment entry points: NetEase Cloud, KuGou, and this site; for songs with the same name across platforms, select the corresponding version first.
- NetEase Cloud and this site support pagination, threaded replies, posting, liking/unliking, and deleting your own comments; actions require logging in to the corresponding site.
- KuGou supports paginated viewing, posting, and threaded replies. **KuGou likes and deletion still lack a verified API protocol, so these two operations are currently unavailable**.
- This site's comments use a separate SQLite database; account identity is verified by the server, and existing threaded replies are retained after you delete your own comment.

### Advanced features
- ⏰ Sleep timer
- 🔋 Battery optimization exemption request
- 🎧 When the UI is swiped away from the recent tasks list, a playing background session keeps running, while non-playback sessions exit safely
- 📁 Custom download directory (MediaStore and SAF supported)
- 🗂️ Cache and download management

## System requirements

- Android 7.0 (API 24) or later
- Android 10+ recommended for the best storage experience

## Building

### Prerequisites
- JDK 17
- Android SDK
- Android NDK and CMake 3.22.1
- Use the Gradle Wrapper provided by the repository

### Build steps

```bash
# 克隆仓库
git clone https://github.com/H2Omeow/NekoPlayer.git
cd NekoPlayer

# 编译 Debug 版本
./gradlew assembleDebug

# 编译 Release 版本（需要配置签名）
./gradlew assembleRelease
```

### Release signing configuration

Official signing is injected through the following environment variables:

```properties
KEYSTORE_FILE=/path/to/your/keystore.jks
KEYSTORE_PASSWORD=your_store_password
KEY_ALIAS=your_key_alias
KEY_PASSWORD=your_key_password
```

When not configured, local release builds use debug signing. GitHub Actions reads the official signing configuration from repository Secrets and automatically builds and updates the Release when a `v*` tag is pushed.

### Desktop build

The Flutter desktop app uses the low-resource scripts included in the repository and requires the Flutter SDK, CMake, Ninja, GTK 3, and libmpv built for the same architecture:

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

Windows installers are built by GitHub Actions; see [desktop_flutter/README.en.md](desktop_flutter/README.en.md) for local requirements and packaging instructions.

## Download

Go to the [Releases](../../releases) page to download the latest version.

## Tech stack

- **Language**: Kotlin + C++ (JNI audio processing)
- **UI framework**: Jetpack Compose
- **Player**: Media3 (ExoPlayer)
- **Networking**: Retrofit + OkHttp
- **Image loading**: Coil
- **Async**: Coroutines + Flow
- **Dependency injection**: Manual dependency injection
- **Persistence**: DataStore + SharedPreferences

## Architecture

- **MVVM architecture pattern**
- **Single Activity with multiple Composables**
- **Repository-layer data abstraction**
- **Media3 MediaSession background playback**

## License

The repository has not yet declared an overall license. The full MIT license texts of the native music API reference projects are bundled with the APK under app/src/main/assets/licenses/; please also comply with those licenses.

## Privacy

- After the user logs in through the SSO account center, the app saves the user's playback history, favorites, playlists, and similar data to this site's server
- Community private messages, follow relationships, and share records are stored on this site's server; public profiles show only nickname, avatar, and bio, not email, third-party bindings, or tokens
- Share links publicly display only the fields selected when sending and do not include audio files; after a share is deleted or a message is recalled, the link and card become invalid immediately
- **NetEase Cloud cookies and KuGou original/concept edition login cookies are encrypted and stored in the cloud** for multi-device sync; the app accesses the native NetEase Cloud and KuGou APIs with the corresponding credentials, while aggregated music sources are accessed uniformly through this site's proxy
- This site does not guarantee absolute data security (for example, factors beyond our control such as server intrusion)
- Using this site's cloud sync feature constitutes acceptance of the above risks
- If you do not want your data uploaded to the server, do not log in to an account or use cloud sync and community features

## Disclaimer

This project is for learning and exchange only. Music copyrights belong to NetEase Cloud Music and the original authors. Please support legitimate music.

## Contributing

Issues and Pull Requests are welcome.

## KuGou API deployment

1.0.8 uses the server-side API. The original and concept editions require separate processes, and the platform is determined by the startup parameter.

Run the following in the KuGouMusicApi directory; the existing original edition port remains 4000:

    HOST=127.0.0.1 pm2 start app.js --name KuGouMusicApi-lite -- --platform=lite --port=4001
    pm2 save

Copy deploy/kugou-platform-router.cjs into the API directory as platform-router.cjs, and add the following in server.js after the Express app is created but before the request body parser and cache middleware:

    if (process.env.platform !== 'lite') app.use(require('./platform-router.cjs')());

The existing /kgapi/ proxy address remains valid: platform=0 uses the original edition, and platform=1 forwards to the local concept edition on 4001. Port 4001 listens only on the loopback address. After updating the upstream API, confirm that this route is still installed. Route regression tests can be run with node --test deploy/kugou-platform-router.test.cjs.

Copy deploy/kugou-search.cjs to the API's module/search.js and restart both KuGou processes. Song search uses an HTTPS public catalog endpoint with a web signature, fixing Android search returning business error 152; returned songs are still verified for playback and download permissions by each platform's login session.

Captcha security verification, SMS rate limiting, and account membership permissions are subject to KuGou's server-side results; the app does not treat API errors as successful logins. Old favorites that did not save a KuGou hash must be searched for and added again.

## Native APIs and site comment deployment

1.0.9 ports the existing music APIs to Kotlin/OkHttp, including NetEase Cloud weapi/eapi and KuGou original/concept edition signing, device registration, and session isolation. It references NeteaseCloudMusicApi 4.32.0, KuGouMusicApi 1.6.2, and the comment posting/replying implementation in KuGouMusicApi b624d645. Site login, cloud sync, and site comments still require this site's server.

The site's Node.js service requires Node 24 (node:sqlite). Place deploy/site-comments.mjs in the service directory and call it after the Express app is created and the existing session middleware is installed, but before the SPA fallback route:

    import { installSiteComments } from './site-comments.mjs';
    installSiteComments(app, { dataRoot, resolveUser, jsonParser: express.json({ limit: '16kb' }) });

resolveUser(req) must verify the request's Bearer JWT and return { user: { id, username } }; invalid credentials return null. Write operations accept only authenticated Bearer identities. The database is located at dataRoot/comments/comments.sqlite; when backing up, retain the database and WAL or use a consistent SQLite backup.

Tests: node --test deploy/*.test.*; Android regression: ./gradlew :app:testDebugUnitTest :app:lintDebug. Setting NATIVE_API_SMOKE=1 additionally runs public API connectivity tests that do not send SMS messages or comments. NetEase Cloud guest registration sometimes returns code=400, which the upstream Node module also reproduces, and a subsequent native retry succeeds; the app preserves the real error and does not generate a fake logged-in state. QR-code confirmation, real-account comment posting, membership songs, and Android real-device playback still need acceptance testing with the corresponding account and device.

## Acknowledgements

- [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)
- [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi)
- [Material Design 3](https://m3.material.io/)
- [Jetpack Compose](https://developer.android.com/jetpack/compose)
- [Media3](https://developer.android.com/guide/topics/media/media3)
- [Coil](https://coil-kt.github.io/coil/)

## Music sources and MVs (1.1.0-pre)

- The Music page adds a separate **Music Sources** group that lets you toggle KuGou, Kuwo, NetEase, QQ, Migu, and Bilibili independently, with the source displayed on song cards.
- Music source addresses are stored only on this site's server; the client does not embed upstream APIs. You must log in to a site account, and all requests use short-lived keys, nonces, and HMAC signatures.
- The entire site shares a daily quota of 10,000 music links; lyrics and MVs do not count against the quota. The site's statistics page shows today's total, remaining quota, and per-user call counts.
- NetEase Cloud, KuGou, and music sources all provide entry points for MV search and playback.
