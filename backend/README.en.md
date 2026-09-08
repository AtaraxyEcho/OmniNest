# OmniNest Backend

The backend provides the shared API, authentication, file capabilities, media services, background processing, and system administration. It is a modular monolith: one codebase can run as API, Worker, or Scheduler roles without splitting business modules into separate microservices.

## Technology baseline

- Java 21, Maven, and Spring Boot 4.0.x.
- Spring Web MVC, Spring Security, Spring Data JPA/Hibernate, and Flyway.
- PostgreSQL for business metadata, permissions, configuration, tasks, and derived state.
- RabbitMQ for background work that needs persistence, progress, retries, recovery, or scheduling.
- Redis for caching, short-lived state, concurrency control, and rate limiting.
- MinIO and controlled Storage Providers for original content and derived assets.
- Lucene for embedded search and Tika for content detection and text extraction.

## Runtime roles

| Role | Responsibility |
| --- | --- |
| `api` | REST API, authentication, authorization, file and media access, task queries, and realtime connections |
| `worker` | Consumes RabbitMQ tasks for indexing, parsing, thumbnails, media processing, and security processing |
| `scheduler` | Runs cleanup, recovery, retry, retention, and scheduled jobs |

Select the runtime with `OMNINEST_ROLE` or a Spring profile. API, Worker, and Scheduler can use the same application image with different roles.

## Modules

| Module | Responsibility |
| --- | --- |
| `omninest-common` | Shared responses, exceptions, base models, and cross-module utilities |
| `omninest-infrastructure` | Database, cache, messaging, storage, search, and runtime infrastructure |
| `omninest-system` | Users, roles, permissions, configuration, notifications, tasks, audit, and system status |
| `omninest-file` | FileNode, content Providers, upload/download, versions, recycle bin, and physical storage lifecycle |
| `omninest-media` | Movies, Music, Photos, Reader, and media metadata services |
| `omninest-worker` | Background consumers, task execution, and retry orchestration |
| `omninest-app` | Spring Boot entry point, HTTP API, runtime configuration, and migration resources |

## Storage boundaries

Business modules keep business IDs and content capabilities. They do not directly use the MinIO client, Rclone, host absolute paths, or low-level `Path` values. The File module owns content access, permission prechecks, Range reads, staging, and Provider capability decisions.

Video may use administrator-registered read-only `LOCAL_FILESYSTEM` sources. Such sources do not provide rename, move, delete, copy, share, version, or offline-download semantics. Explicitly importing content into managed storage is required before those capabilities apply. Large content and derived files must use streaming or background-task paths.

## Configuration

The main configuration is `omninest-app/src/main/resources/application.yml`, which optionally loads `.env` from the working directory. Templates and module configuration notes are in `backend/.env.example`. Common settings include:

- `OMNINEST_PROFILE`, defaulting to `dev`, for the Spring configuration.
- `OMNINEST_ROLE`, defaulting to `api`, for the runtime role.
- PostgreSQL, RabbitMQ, Redis, MinIO, Rclone, and image-analysis Sidecar connections.
- JWT, public URLs, CORS, upload limits, and media limits.

Defaults support local development and configuration validation. Production deployments must explicitly review public URLs, credentials, private storage, and security policies. Never commit real passwords, tokens, keys, or production configuration.

## Local development

Start dependencies as described in [deploy/README.md](../deploy/README.md), then run from Git Bash:

```bash
cd backend
mvn -q test
mvn -pl omninest-app spring-boot:run -Dspring-boot.run.profiles=dev
```

Build the JAR used by the application image:

```bash
mvn -q -pl omninest-app -am -DskipTests package
```

For an empty database, Flyway applies `V001__init_schema.sql` and `V002__builtin_catalog.sql`. These two scripts form the current baseline. While the current version still permits baseline rewrites, structural changes and built-in catalog changes should be synchronized to the corresponding file.

## API and tasks

- REST APIs use the `/api/v1` prefix and stable business error codes.
- Identity comes from the local JWT `sub` mapped to a database user. Authorization uses database-backed roles, permissions, and mappings.
- Work that continues across requests is persisted before it is published to RabbitMQ after transaction commit. Task state, retries, and dead-letter records remain queryable.
- MinIO buckets are private by default. Downloads and media streams use controlled access or short-lived signed URLs.
- External URL fetching, offline downloads, subtitles, and metadata requests must validate protocols, DNS results, IP ranges, and redirects.

## Verification

At minimum, run for normal backend changes:

```bash
mvn -q test
git diff --check
```

Changes involving databases, permissions, tasks, storage, or security boundaries should add relevant unit or Testcontainers integration coverage and record any verification that was not run.

## Related entry points

- [Root project overview](../README.md)
- [Chinese backend guide](README.md)
- [Deployment guide](../deploy/README.md)
- [Image-analysis Sidecar](../deploy/ai-sidecar/README.md)
