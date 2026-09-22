<p align="center">
  <img src="imgs/omninest-logo.webp" alt="OmniNest logo" width="360">
</p>

<p align="center">
  <strong>OmniNest</strong>
</p>

<h3 align="center">Self-hosted personal digital life center</h3>

<p align="center">
  Files · Movies · Music · Photos · Reader — one account, permissions, storage, and background tasks
</p>

---

OmniNest is a **self-hosted** digital life center for personal and family use. It organizes file management, movies, music, photos, and reading under one account, permission, object-storage, and async-task system. You deploy it; you keep the data.

This repository is a **modular monolith**: Spring Boot for API / Worker / Scheduler, and Flutter for clients. See [backend/README.en.md](backend/README.en.md), [frontend/README.en.md](frontend/README.en.md), and [deploy/README.md](deploy/README.md). Chinese editions: [README.md](README.md).

> **Status**: Under active development. This document covers capabilities, platform support, **disclaimer**, and the shortest path to run the stack.

---

## Disclaimer

Please read this section before using OmniNest. **Using this software means you understand and accept the terms below.**

### Content and copyright

- OmniNest **does not provide, distribute, or bundle** any media content (video, music, ebooks, photos, etc.).
- You may only store, manage, or play content you **legally own** or are **lawfully allowed** to use.
- Before uploading, importing, or sharing copyrighted material, you must ensure you have the necessary rights. Any copyright or legal disputes arising from content sources or usage are **the sole responsibility of the user**, not the authors or contributors.
- This project **does not encourage or support** piracy, infringement, or illegal content distribution.
- UI illustrations and demo media in this repository’s documentation **are** public-domain / CC0 (or equivalent) assets. **Do not commit or publish copyrighted media** into this repository or public demos.

### Software

- The software is provided **“AS IS”**, without warranty of any kind, express or implied, including merchantability, fitness for a particular purpose, and non-infringement.
- To the maximum extent permitted by law, authors and contributors are **not liable** for any direct, indirect, incidental, or consequential damages arising from use of the software, including data loss, downtime, device damage, or business loss.
- Security, backups, key management, public exposure, and access control of a self-hosted deployment are **the deployer’s responsibility**. Defaults target personal / private networks and are **not** a hardened public production baseline by themselves.

### Platform support

- Officially recommended and verified clients: **Web, Android, Windows**.
- The Flutter tree contains iOS / macOS directories and adapters, but they have **not** received full testing equivalent to those three platforms. They are **not recommended** for production or critical use without your own validation.
- Optional components such as virus scanning (ClamAV) and image analysis are **deployment choices** based on hardware and exposure. Typical 4C4G personal setups may disable scanning; public internet deployments should evaluate enabling it.

### Third-party music platforms

- This project is for **personal study and research only**; commercial and illegal use is prohibited. It does **not** provide VIP audio source cracking or services that bypass payment, membership, or audio-quality limits.
- OmniNest is an **unofficial** open-source project, with **no affiliation, partnership, or authorization** with NetEase Cloud Music or its affiliates.
- All content resources belong to their respective platform owners. You are responsible for complying with the platform's terms of service and copyright requirements, at your own risk.

### Getting the clients

- **Web** is served by the deployment stack's Nginx and connects same-origin.
- **Android / Windows** packages ship without a baked-in server address: on first launch a setup page asks for your self-hosted server address (`host`, `host:port`, or a full URL), validates it, then continues to login or the install wizard; signed-in users can change it under Profile → Server & connection.
- Custom builds: `frontend/scripts/build_signed_*_release.ps1` accept an optional `-ApiBaseUrl` preset (family distribution; address changes propagate with app updates) and `-RequireHttps` for HTTPS-only strict builds. The server ships as Docker images only; there is no standalone jar (see deploy/README.md).

### Privacy and data

- Data stays on **your** server and storage. Developers do **not** collect your library contents through this software.
- You are responsible for complying with applicable laws regarding personal data and online services.

> Privacy notice: [`PRIVACY.en.md`](./PRIVACY.en.md). Third-party licensing and attribution: [`NOTICE.md`](./NOTICE.md).

---

## Screenshots

<table>
  <tr>
    <th>Portal workspace</th>
    <th>Photos</th>
  </tr>
  <tr>
    <td><img src="imgs/desktop/portal_home_page.png" alt="Portal workspace" width="600"></td>
    <td><img src="imgs/desktop/photos_home_page.png" alt="Photos home" width="600"></td>
  </tr>
  <tr>
    <th>Movie details</th>
    <th>Music</th>
  </tr>
  <tr>
    <td><img src="imgs/desktop/movies_detail_page.png" alt="Movie details" width="600"></td>
    <td><img src="imgs/desktop/music_home_page.png" alt="Music home" width="600"></td>
  </tr>
  <tr>
    <th>Reader</th>
    <th>Admin console</th>
  </tr>
  <tr>
    <td><img src="imgs/desktop/reader_view_page.png" alt="Reader" width="600"></td>
    <td><img src="imgs/desktop/admin_console_home.png" alt="Admin console" width="600"></td>
  </tr>
  <tr>
    <th>Photo slideshow</th>
    <th>Setup wizard</th>
  </tr>
  <tr>
    <td><img src="imgs/desktop/photos_slideshow_page.png" alt="Photo slideshow" width="600"></td>
    <td><img src="imgs/desktop/setup_page.png" alt="Setup wizard" width="600"></td>
  </tr>
</table>

Screenshot folders:

| Platform | Folder | Notes |
| --- | --- | --- |
| Desktop / Web | [imgs/desktop](imgs/desktop) | 22 shots covering Portal, Photos, Movies, Music, Reader, Admin, and setup |
| Android | `imgs/mobile` | Under construction; screenshots will be added over time |

---

## Features

| Area | Main capabilities |
| --- | --- |
| Portal | Unified workspace, backdrops, recent content, notifications, module entry points |
| File Manager | Uploads, folders, search, preview, downloads, recycle bin, storage lifecycle |
| Photos | Albums and timeline, thumbnails, metadata, location, optional image analysis (sidecar currently focused on face detect / embed / cluster) |
| Movies | Library, posters and details, playback, subtitles, progress, local read-only sources |
| Music | Local library, external platforms, queue, covers/lyrics, playback progress |
| Reader | EPUB and more, catalogs, text/comic reading, bookmarks, annotations, progress |
| Admin | Users, roles/permissions, config, tasks, logs, audit, runtime status |
| Profile | Themes, preferences, account security |

---

## Platform support

| Platform | Level | Notes |
| --- | --- | --- |
| **Web** | ✅ Recommended / verified | Modern desktop browsers (dev baseline: Chrome) |
| **Android** | ✅ Recommended / verified | Compact navigation and touch layout |
| **Windows** | ✅ Recommended / verified | Desktop window, mouse and keyboard |
| **iOS / macOS** | ⚠️ Not recommended | Flutter adapters exist; **not fully tested** |

---

## Stack

| Layer | Technology |
| --- | --- |
| Client | Flutter / Dart (Web · Android · Windows) |
| Server | Java 21 · Spring Boot modular monolith (API / Worker / Scheduler) |
| Data | PostgreSQL · MinIO · RabbitMQ · Redis · Lucene · optional image analysis sidecar |

---

## Repository layout

| Path | Description |
| --- | --- |
| [backend](backend/README.en.md) | Server modules and tests; runtime logs under `backend/logs/` |
| [frontend](frontend/README.en.md) | Flutter clients and tests; build/test logs under `frontend/logs/` |
| [deploy](deploy/README.md) | Dev/prod Compose and deployment |
| [deploy/ai-sidecar](deploy/ai-sidecar/README.md) | Image analysis sidecar |
| [imgs](imgs) | Documentation screenshots |

---

## Requirements

- Git; Docker Desktop and Docker Compose
- JDK 21 and Maven
- Flutter stable (baseline: 3.44.8 / Dart 3.12.2)
- Chrome (Web); Android Studio/SDK (Android); Windows toolchain (desktop)

---

## Sizing (self-hosted)

| Scenario | Suggested hardware | ClamAV |
| --- | --- | --- |
| Personal / private network | **4C 4GB** | Usually off |
| Public internet production | **4C 8GB+** | Evaluate enabling |

Production Compose defaults to a **4C4G personal profile without ClamAV / image analysis**. Enabling scanning is an operator decision. See [deploy/README.md](deploy/README.md).

---

## Quick start

### 1. Clone

```bash
git clone git@github.com:AtaraxyEcho/omni-nest.git
cd omni-nest
```

### 2. Dev infrastructure

```bash
cp deploy/dev/.env.example deploy/dev/.env
docker compose --env-file deploy/dev/.env -f deploy/dev/docker-compose.yml up -d
```

Each `.env.example` template has an English counterpart `.env.en.example` in the same directory (identical variables, comments in English).

### 3. Backend

```bash
cp backend/.env.example backend/.env
cd backend
mvn -pl omninest-app spring-boot:run -Dspring-boot.run.profiles=dev
```

API default: `http://localhost:8080/api/v1` (or the port in `backend/.env`, e.g. `9090`).

### 4. Flutter Web

```bash
cd frontend
test -f env/dev.json || cp env/dev.example.json env/dev.json
flutter pub get
flutter run -d chrome --web-port=3000 --dart-define-from-file=env/dev.json
```

Open `http://localhost:3000`; first install: `http://localhost:3000/setup`.

### 5. Android / Windows

```bash
flutter run -d <android-device-id> --dart-define-from-file=env/dev.json
flutter run -d windows --dart-define-from-file=env/dev.json
```

Set API/WebSocket hosts in `env/dev.json` to addresses the client can reach.

**Demo media**: UI illustrations and demo media in this repo’s docs **are CC0 / public domain** (see Disclaimer). Do not use copyrighted material.

---

## Testing

| Area | Command |
| --- | --- |
| Backend | `cd backend && mvn test` |
| Frontend | `cd frontend && flutter test` |
| Frontend analyze | `cd frontend && flutter analyze lib` |

Some Testcontainers/migration cases skip when Docker is unavailable. Full E2E on Web/Android/Windows, native Android layers, and iOS/macOS are **not** part of the current automated gate.

---

## Documentation

- [Backend](backend/README.en.md)
- [Frontend](frontend/README.en.md)
- [Deploy](deploy/README.md)
- Product notes: [PRODUCT.md](PRODUCT.md) (if present)

---

## License

See [LICENSE](LICENSE) in the repository root. Read it fully before use, modification, or distribution.

---

<p align="center">
  <sub>
    OmniNest is self-hosted software. Use media lawfully and take responsibility for your own deployment and data security.
  </sub>
</p>
