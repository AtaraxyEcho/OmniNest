# OmniNest Frontend

OmniNest Frontend is the unified Flutter client.

**Currently recommended and verified platforms: Web, Android, Windows.**

**iOS / macOS**: The tree contains platform folders and adapters, but they have **not** received full testing equivalent to those three platforms. They are **not recommended** for production or daily reliance; validate fully on your own if you need them.

All platforms share one product information architecture and business state; layout and interaction density adapt to window size, touch, mouse, and keyboard.

**Demo media**: UI illustrations and demo media in product docs **are CC0 / public domain**. Do not use copyrighted material in screenshots or imports. See the root [Disclaimer](../README.md#免责声明disclaimer).

Root overview: [../README.en.md](../README.en.md) · Chinese guide: [README.md](README.md) · Backend: [../backend/README.en.md](../backend/README.en.md) · Deploy: [../deploy/README.md](../deploy/README.md).

## Log directory

Build, test, and debug logs go under `frontend/logs/` (gitignored), not the frontend source root:

```bash
# Examples: test and build logs
flutter test --reporter compact 2>&1 | tee logs/flutter-test.log
flutter build web --dart-define-from-file=env/dev.json 2>&1 | tee logs/flutter-build-web.log
```

Runtime debugging stays in the IDE console; persist to `logs/` only when needed.

## Responsibilities

- Provides Portal, File Manager, Photos, Movies, Music, Reader, Admin, Profile, and Setup user interfaces.
- Connects backend APIs, background tasks, notifications, and realtime sync through Riverpod application state.
- Owns navigation, responsive layout, theming, localization, loading/empty/error feedback, and desktop/mobile input adaptation.
- Uses file picking, media playback, and secure storage through controlled Repositories and platform adapters.
- Keeps long flows (upload, import, parsing, delete, polling, sync) decoupled from page lifecycles; tasks already submitted to the backend keep running server-side after the page closes.

## Pages and information architecture

| Page or route | Main content |
| --- | --- |
| `/server-setup`, `/setup`, `/login` | First-run server setup, installation wizard, login, and session establishment |
| `/portal` | Dynamic backdrop, recent content, notifications, search, and module entries |
| `/files` | File tree, upload/download, preview, trash, and lifecycle operations |
| `/photos` | Albums, timeline, image details, metadata, image analysis, and sharing |
| `/video` | Video library, movie details, playback, subtitles, and progress |
| `/music` | Local/external music, search, queue, lyrics, covers, and playback controls |
| `/reader` | Book/comic library, import, catalogs, reading, bookmarks, annotations, and progress |
| `/admin/*` | Users, roles, permissions, configuration, tasks, logs, sessions, and monitoring |
| `/profile` | Profile, themes, account security, server & connection, and personal preferences |
| `/settings` | Compatibility entry that redirects to the matching profile section |

Desktop and Web use left navigation plus a top toolbar; Android uses compact navigation and touch-friendly controls, while module names, permission boundaries, and main task paths stay identical.

## Backend interaction

```text
presentation
    -> application / Riverpod Notifier
    -> data / Repository / Dio
    -> Spring Boot API
```

- HTTP APIs default to `/api/v1`; WebSocket defaults to `/ws`.
- Auth, token refresh, `X-Request-Id`, error mapping, and necessary idempotent retries are handled by the Dio network layer.
- Long flows (upload, import, parse, scan, delete) are tracked through backend `taskId`s; pages only subscribe to status.
- Presentation never touches Dio, drift DAOs, SQLite, MinIO, Rclone, or host file systems; content access goes through the backend File module.
- Request races are handled via cancellation, request ids, generations, or Provider lifecycles; stale responses must not overwrite current page state.

## Technology and layers

- Riverpod for business state, go_router for routing, Dio for HTTP, drift for local structured caches, `flutter_secure_storage` for sensitive credentials.
- Feature directories use `domain`, `data`, `application`, `presentation` layers.
- `domain` holds entities, value objects, Repository abstractions, and domain rules without Flutter or networking dependencies.
- `data` owns DTOs, API clients, caches, Repository implementations, and persistence adapters.
- `application` owns Notifiers, Controllers, use-case orchestration, and page business state.
- `presentation` only renders, handles input, subscribes to state, navigates, and gives UI feedback.
- Dart imports use `package:omninest/...` uniformly; this is an OmniNest directory-consistency rule, not general Effective Dart advice.

## Installation and environment

### Prerequisites

- Flutter stable. Verified baseline: Flutter 3.44.8, Dart 3.12.2.
- Chrome for Web; Android Studio and SDK for Android; Windows/macOS toolchains for desktop.
- The backend must be running and reachable from the device; defaults are `http://localhost:8080/api/v1` and `ws://localhost:8080/ws`.

### Get dependencies

```bash
cd frontend
flutter pub get
```

### Create the local configuration

```bash
test -f env/dev.json || cp env/dev.example.json env/dev.json
```

`env/dev.json` is a compile-time file; the app does not read it automatically. Prefer `--dart-define-from-file=env/dev.json` (or individual `--dart-define`s) when running or building:

```json
{
  "OMNINEST_API_BASE_URL": "http://localhost:8080/api/v1",
  "OMNINEST_WS_BASE_URL": "ws://localhost:8080/ws",
  "OMNINEST_WEB_BASE_URL": "http://localhost:3000"
}
```

Server address precedence: a custom address saved from the first-run setup page > the compile-time preset above > not configured. Web always derives same-origin endpoints from the browser origin; Android, Windows, and macOS enter the first-run setup page (`/server-setup`) when neither a preset nor a custom address exists — enter `host`, `host:port`, or a full URL, and after a successful probe continue to login or the install wizard. Signed-in users can change the server under Profile → Server & connection (this signs out and clears the local session). Presets are not persisted: devices that never customized follow a new preset shipped with an updated package. When real devices or other machines access the backend, the preset host must be reachable and allowed by backend CORS.

## Local development

Start dependencies via the [deployment guide](../deploy/README.md) and the backend via [../backend/README.en.md](../backend/README.en.md), then from `frontend`:

```bash
flutter devices
flutter run -d chrome --web-port=3000 --dart-define-from-file=env/dev.json
```

Other targets:

```bash
flutter run -d windows --dart-define-from-file=env/dev.json
flutter run -d <device-id> --dart-define-from-file=env/dev.json
```

`<device-id>` comes from `flutter devices`. Confirm the backend address is reachable from the target device.

## Builds

### Web

```bash
flutter build web --release
```

Without compile-time addresses the Web app uses the browser origin, so the production Nginx image builds directly via [deploy/prod/nginx/Dockerfile](../deploy/prod/nginx/Dockerfile) and serves API, WebSocket, and MinIO through same-origin reverse proxying. To host Web on a different origin, pass the addresses explicitly:

```bash
flutter build web --release \
  --dart-define=OMNINEST_API_BASE_URL=https://example.com/api/v1 \
  --dart-define=OMNINEST_WS_BASE_URL=wss://example.com/ws \
  --dart-define=OMNINEST_WEB_BASE_URL=https://example.com
```

### Android, Windows, and macOS

```bash
flutter build apk --release --dart-define-from-file=env/dev.json
flutter build appbundle --release --dart-define-from-file=env/dev.json
flutter build windows --release --dart-define-from-file=env/dev.json
flutter build macos --release --dart-define-from-file=env/dev.json
```

`apk`/`appbundle` target Android; `windows` requires the Windows toolchain and `macos` the macOS toolchain. The repository produces Flutter platform artifacts and does not include a default Inno Setup, MSIX, or macOS DMG/PKG installer pipeline; distribution should add platform signing, packaging, and update policies.

### Release signing scripts

Formal distribution uses the module's signing scripts (signing environment variables and verification details in the script comments):

```powershell
scripts/build_signed_android_release.ps1 -ExpectedCertificateSha256 <fingerprint> [-ApiBaseUrl https://nest.example.com] [-RequireHttps]
scripts/build_signed_windows_release.ps1 -CertificateThumbprint <fingerprint> -TimestampUrl <timestamp-service> [-ApiBaseUrl https://nest.example.com] [-RequireHttps]
```

- `-ApiBaseUrl` is optional: omit it to build a **universal package** (the server is configured on first launch); pass it to preset the address — suitable for family distribution, and address changes propagate with updated packages.
- `-RequireHttps` builds a **strict package**: the app rejects every `http://` server address (with a mutual-exclusion check), equivalent to `--dart-define=OMNINEST_REQUIRE_HTTPS=true`; suited to public HTTPS deployments.
- Android universal packages allow cleartext HTTP for LAN self-hosting (see `android/app/src/main/res/xml/network_security_config.xml`); the setup page shows a risk notice for http addresses.

## Development conventions

- Riverpod owns business state; widget `setState` is only for short-lived hover, expansion, transient selection, and local animation.
- `build()`, `LayoutBuilder`, and `dispose()` perform no network requests, state writes, navigation, dialogs, or background task creation.
- After crossing `await`, Timer, Stream, Dialog, platform callbacks, or post-frame callbacks, verify `mounted` before touching `context`, `ref`, `setState`, Navigator, or ScaffoldMessenger; never look up providers via `ref` in `dispose`.
- Controllers, FocusNodes, Timers, StreamSubscriptions, Listeners, and CancelTokens created by a widget are released by their creator; Provider-owned resources follow Provider lifecycles.
- Route, Overlay, text selection, and GlobalKey operations must avoid double pops, Navigator locks, duplicate GlobalKeys, and deactivated elements.
- Long flows that need cancellation, retry, resume, or status live in application/Repository/Service layers; destroying a page must not orphan an already submitted backend task.
- Page copy goes into ARB files; theming and colors use shared design tokens; every clickable icon has a tooltip or semanticLabel.
- Large lists use builders, Slivers, pagination, and thumbnails instead of building huge widget trees or decoding full-size images.

## Tests and verification

From `frontend`:

```bash
dart format lib test
flutter analyze
flutter test
git diff --check
```

Changes involving imports, uploads, deletes, the reader, the player, routing, text selection, or window sizes should add Widget, integration, or responsive regression coverage — at minimum leaving a page mid-operation, repeated taps, request races, theme switches, and repeated enter/exit. Tests that cannot run must be listed with reasons in delivery notes; never describe unexecuted verification as passed.

## Related entry points

- [Root project overview](../README.en.md)
- [Chinese frontend guide](README.md)
- [Backend guide](../backend/README.en.md)
- [Deployment guide](../deploy/README.md)
