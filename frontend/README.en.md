# OmniNest Frontend

OmniNest Frontend is the unified Flutter client.

**Currently recommended and verified platforms: Web, Android, Windows.**

**iOS / macOS**: The tree contains platform folders and adapters, but they have **not** received full testing equivalent to those three platforms. They are **not recommended** for production or daily reliance; validate fully on your own if you need them.

All platforms share one product information architecture and business state; layout and interaction density adapt to window size, touch, mouse, and keyboard.

**Demo media**: UI illustrations and demo media in product docs **are CC0 / public domain** (or equivalent). Do not use copyrighted material in screenshots or imports. See the root [Disclaimer](../README.md#免责声明disclaimer).

Build, test, and debug logs go under `frontend/logs/` (gitignored), not the frontend source root.

Root overview: [../README.en.md](../README.en.md) · Chinese guide: [README.md](README.md) · Backend: [../backend/README.en.md](../backend/README.en.md) · Deploy: [../deploy/README.md](../deploy/README.md).

## Feature modules

| Module | Main responsibility |
| --- | --- |
| `portal` | Workspace, dynamic backdrops, recent content, notifications, and module entry points |
| `files` | File lists, folders, upload/download, search, preview, and lifecycle operations |
| `photos` | Albums, image import, details, metadata, and image-analysis results |
| `video` | Video library, movie details, playback, subtitles, and playback progress |
| `music` | Local/external music, search, queue, lyrics, covers, and playback controls |
| `reader` | Book and comic import, catalogs, reading, bookmarks, annotations, and reading progress |
| `admin` | Administration, permissions, configuration, tasks, audit, and monitoring |
| `profile` / `settings` | Profile, themes, account security, and client preferences |
| `setup` | First-installation and instance initialization wizard |

## Technology and layers

- Riverpod manages business state; go_router manages routing; Dio handles HTTP; drift and secure storage handle local data and sensitive credentials.
- Feature directories use `domain`, `data`, `application`, and `presentation` layers.
- `domain` has no Flutter or networking dependency. `data` owns DTOs, APIs, caches, and Repository implementations. `application` owns Notifiers, Controllers, and business flows. `presentation` handles rendering, input, navigation, and feedback.
- Pages do not access Dio, databases, MinIO, or host file systems directly. Long-running upload, import, delete, parsing, polling, and sync flows are owned by application/Repository layers; leaving a page does not implicitly cancel an already submitted background task.
- Async operations must handle `mounted`, Provider lifecycles, request races, duplicate submissions, route exits, and resource disposal to prevent `ref` access after unmount, Navigator locks, Duplicate GlobalKey, and other Flutter framework errors.

## Environment configuration

The development template is `frontend/env/dev.example.json`. Create a local configuration from Git Bash before the first run:

```bash
cd frontend
test -f env/dev.json || cp env/dev.example.json env/dev.json
```

Common values include API, WebSocket, and public Web URLs. Never commit real credentials or production configuration.

## Local development

```bash
cd frontend
flutter pub get
flutter devices
flutter run -d windows
```

Replace the device ID with an Android device, or launch Web with Chrome:

```bash
flutter run -d <device-id>
flutter run -d chrome
```

## Builds

```bash
flutter build web --release
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
flutter build macos --release
```

The production Web build is created by `deploy/prod/nginx/Dockerfile` and served by Nginx, which also proxies the API, WebSocket, and MinIO endpoints. See [../deploy/README.md](../deploy/README.md) for deployment.

The Windows and macOS commands currently produce Flutter platform build artifacts. The repository does not include a default Inno Setup, MSIX, or macOS DMG/PKG installer pipeline. Distribution to end users should add platform signing, packaging, and update policies after the build artifacts have been validated.

## Code and verification

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
```

Changes involving imports, uploads, deletes, the reader, the player, routing, or window sizes should add Widget, integration, or responsive regression coverage for leaving a page mid-operation, repeated taps, request races, and theme changes.

## Related entry points

- [Root project overview (English)](../README.en.md)
- [Chinese frontend guide](README.md)
- [Backend guide (English)](../backend/README.en.md)
- [Deployment guide](../deploy/README.md)
