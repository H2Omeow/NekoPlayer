[English](README.en.md) | [简体中文](README.md)

# NekoPlayer

A music and video player for Android, Windows, and Linux. Music comes from NetEase Cloud Music, KuGou, and aggregated sources; video connects directly to Bilibili. The app also provides account sync, community features, file storage, and an admin panel.

Current version: **1.4.4** (Android `versionCode 32`). The desktop app has been built on Flutter since 1.2.0; the original Compose `desktop/` app no longer receives feature updates.

## Platforms and artifacts

| Platform | Artifact | Notes |
| --- | --- | --- |
| Android 7.0+ (API 24) | `NekoPlayer-vX.Y.Z.apk` | Media3 / ExoPlayer, background playback and system media controls |
| Windows x64 / ARM64 | `*-windows-*.setup.exe` | Flutter desktop; installers are not code-signed |
| Linux x64 / ARM64 | `.deb` / `.rpm` / `.tar.gz` | Requires GTK 3 and libmpv |

Each release ships `SHA256SUMS` for integrity checks.

## Features

### Video (Bilibili)

- Dedicated video tab: search, recommendations, popular, category filters, infinite scrolling, and direct BV input.
- Player: 16:9 stage, quality switching, playback rate, fullscreen, resume, related videos, comments, and description.
- Danmaku: scrolling, top, and bottom modes driven by playback position; adjustable size, speed, opacity, display area, density, stroke, and shadow, plus color danmaku, keyword blocking, and duplicate merging.
- Account: QR code, in-app web login, and Cookie import; signing in enables comments, likes, coins, favorites, and follows.
- On playback failure the app refreshes the media URL and steps down the quality; media requests carry `Referer`, `Origin`, a desktop User-Agent, and an initial `Range` header.

### Music

- Streaming from NetEase Cloud Music and KuGou, with downloads, caching, queue, playback modes, and speed control.
- Source switching for KuGou, KuWo, NetEase, QQ, Migu, and Bilibili, with the source shown on each card.
- Lyrics: scrolling, word-by-word highlight, translation, floating and desktop lyrics.
- Audio effects: system effects follow the device audio session; the professional chain is a local C++ DSP with a 10-band EQ, reverb, and 20 signature mastering presets.
- Accounts: NetEase login, KuGou SMS and QR login, with separate sessions for the standard and concept editions.

### Cloud storage

- Direct upload to S3-compatible object storage with private buckets and presigned URLs; files over 5MB are uploaded in parts and the server never stores the payload.
- Free tier: 3.25 GB storage, 3.25 GB monthly traffic, 50 files; video ≤50MB, image ≤5MB, audio ≤25MB, custom file ≤1GB (counts as five files).
- Supporter (7.99/mo): 32.5 GB storage, 50 GB monthly traffic, unlimited files and file size, files never expire
- Plus (32.5/mo): 80 GB storage, 100 GB monthly traffic
- Sponsor seat (64.8/mo): 200 GB storage, 100 GB monthly traffic, limited to 2 concurrent seats
- Sharing: in-app sharing (downloads consume half of the sharer's traffic) or direct links (public download, full traffic), valid for 1, 7, or 30 days.
- Cloud storage requires a Skland binding; QR code, SMS, phone password, and a web-login fallback are supported.
- Free accounts inactive for 180 days have uploaded files removed (playlists, favorites, and history are unaffected); a notice is sent 7 days in advance.

### Community

- One-to-one messaging with text and song cards, follows, follower feeds, user search, and public profiles.
- Online presence in conversations and profiles (15-second heartbeat, 70-second window).
- Public share pages with web playback and deep links; files can be sent to friends in one tap.
- Message scope, blocking, push notifications, and unread counts.

### Sync

- Cloud sync for playback history, favorites, playlists, NetEase cookies, and both KuGou editions' cookies.
- Local sessions take priority; a blank device restores after sign-in.
- Cookies and sync payloads are encrypted on the server; sync uses per-section optimistic locking and returns 409 on conflict.

## Download

See [Releases](../../releases). Older builds are archived by tag.

## Building

### Android

Requirements: JDK 17, Android SDK, NDK, CMake 3.22.1, and the bundled Gradle wrapper.

```bash
./gradlew assembleDebug
./gradlew assembleRelease   # requires signing environment variables
```

Signing uses `KEYSTORE_FILE`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD`; without them the release build is signed with the debug key. Pushing a `v*` tag triggers the GitHub Actions build for all platforms.

### Desktop (Flutter)

Requires Flutter SDK, CMake, Ninja, GTK 3, and libmpv for the target architecture:

```bash
export FLUTTER_BIN=/path/to/flutter
./deploy/flutter-low-resource.sh analyze
./deploy/flutter-low-resource.sh test
./deploy/flutter-low-resource.sh build linux --release
```

Packaging DEB/RPM/tar.gz is documented in [desktop_flutter/README.en.md](desktop_flutter/README.en.md).

### Tests

```bash
./gradlew :app:testDebugUnitTest :app:lintDebug
node --test deploy/*.test.*
```

Set `NATIVE_API_SMOKE=1` to run public endpoint smoke tests that do not send SMS or comments.

## Server

Accounts, cloud sync, community, cloud storage, and the Bilibili proxy run on self-hosted servers; no upstream credentials are embedded in the client. Deployment details are in [docs/SERVER_DEPLOY.md](docs/SERVER_DEPLOY.md).

## Tech stack

Kotlin with Jetpack Compose, Media3 / ExoPlayer, Retrofit with OkHttp, Coil, Coroutines/Flow, DataStore, and manual dependency injection; audio effects use a C++ DSP over JNI. The desktop app is Flutter with media_kit; the server is Node.js 24 with `node:sqlite`.

## Privacy

- After signing in to the account center, playback history, favorites, playlists, and cookies are encrypted and stored on this site's server for cross-device sync.
- Cloud storage keeps file payloads in object storage and metadata in the server database; admin writes are recorded in an audit log.
- Community messages, follows, and share records are stored on the server; public profiles show only nickname, avatar, and bio.
- Share links expose only the fields selected when sharing and never include audio files; deleting a share or recalling a message invalidates the link.
- NetEase and KuGou cookies are encrypted for sync; the Bilibili session stays on the device.
- No absolute security is guaranteed. If you do not want data uploaded, do not sign in or use sync, community, and cloud storage features.

## Known limitations

- Without a Bilibili account the quality cap is 720P; 1080P and above require signing in.
- Windows installers are not code-signed.
- KuGou comment likes and deletion have no verified protocol and remain disabled.
- Server endpoints depend on upstream sites and may change; the app surfaces real error messages.

## Acknowledgements

- [Binaryify/NeteaseCloudMusicApi](https://github.com/Binaryify/NeteaseCloudMusicApi)
- [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi)
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [Material Design 3](https://m3.material.io/), [Jetpack Compose](https://developer.android.com/jetpack/compose), [Media3](https://developer.android.com/guide/topics/media/media3)

## License and disclaimer

The repository does not declare an overall license; MIT texts for the referenced music API projects are bundled in `app/src/main/assets/licenses/`. The project is for learning and research; music and video rights belong to the respective platforms and authors.

## Contributing

Issues and pull requests are welcome. Changes touching server endpoints should include verification steps.
