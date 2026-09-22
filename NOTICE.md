# NOTICE

OmniNest
Copyright 2026 OmniNest Contributors

This project is distributed under the GNU Affero General Public License v3.0 (AGPL-3.0); the full text
is in [`LICENSE`](./LICENSE).

This product includes the following third-party components. Each is listed as
`name · coordinates/source · license · upstream link`; copyrights belong to their respective owners.

---

## Backend (Java / Spring Boot)

The backend third-party inventory is generated at build time by the Maven `license-maven-plugin`
`aggregate-add-third-party` goal; the full list is in `backend/target/reports/licenses/THIRD-PARTY.txt`.
The table below lists the main runtime components.

### Apache License 2.0 (main)

| Component | Coordinates | Upstream |
|---|---|---|
| Spring Boot / Spring Framework | `org.springframework.boot` | https://spring.io/projects/spring-boot |
| Apache Lucene (core / queryparser / analysis) | `org.apache.lucene:*` | https://lucene.apache.org |
| Apache Tika (transitive) | `org.apache.tika:*` | https://tika.apache.org |
| Jackson (annotations / core / databind) | `com.fasterxml.jackson.core:*` | https://github.com/FasterXML/jackson |
| Netty (buffer / codec / handler / transport, etc.) | `io.netty:*` | https://netty.io |
| Guava | `com.google.guava:guava` | https://github.com/google/guava |
| Apache Commons (Codec / IO / Logging / Lang3 / Compress) | `commons-*` / `org.apache.commons:*` | https://commons.apache.org |
| fastjson2 and extensions | `com.alibaba.fastjson2:*` | https://github.com/alibaba/fastjson2 |
| MinIO Java SDK | `io.minio:minio` | https://github.com/minio/minio-java |
| AWS SDK for Java v2 | `software.amazon.awssdk:*` | https://aws.amazon.com/sdk-for-java |
| HikariCP | `com.zaxxer:HikariCP` | https://github.com/brettwooldridge/HikariCP |
| Caffeine | `com.github.ben-manes.caffeine:caffeine` | https://github.com/ben-manes/caffeine |
| Nimbus JOSE+JWT | `com.nimbusds:nimbus-jose-jwt` | https://connect2id.com/products/nimbus-jose-jwt |
| OkHttp / Okio | `com.squareup.okhttp3:okhttp` / `okio` | https://square.github.io/okhttp |
| Micrometer | `io.micrometer:*` | https://micrometer.io |
| springdoc-openapi | `org.springdoc:*` | https://springdoc.org |
| Tink Cryptography | `com.google.crypto.tink:tink` | https://github.com/tink-crypto/tink-java |
| Gson | `com.google.code.gson:gson` | https://github.com/google/gson |
| Reactor Core | `io.projectreactor:reactor-core` | https://projectreactor.io |
| metadata-extractor | `com.drewnoakes:metadata-extractor` | https://drewnoakes.com/code/exif |

> For Apache License 2.0 components whose upstream ships a NOTICE file, attribution and notice
> obligations follow that upstream NOTICE; full license texts are available upstream or via the links above.

### Licenses requiring special note

| Component | Coordinates | License | Note |
|---|---|---|---|
| RabbitMQ Java Client | `com.rabbitmq:amqp-client` | AL 2.0 / GPL v2 / MPL 2.0 (tri-licensed) | This project uses it under the **Apache License 2.0** option, not GPL v2 |
| Logback (classic / core) | `ch.qos.logback:*` | EPL 1.0 / LGPL 2.1 | Used under the EPL 1.0 option |
| Bouncy Castle Provider | `org.bouncycastle:bcprov-jdk18on` | Bouncy Castle Licence | — |
| AspectJ Weaver | `org.aspectj:aspectjweaver` | EPL 2.0 | — |
| Protocol Buffers (Java) | `com.google.protobuf:protobuf-java` | BSD-3-Clause | — |
| ANTLR 4 Runtime | `org.antlr:antlr4-runtime` | BSD-3-Clause | — |
| Adobe XMPCore | `com.adobe.xmp:xmpcore` | BSD-3-Clause | — |
| Lettuce (Redis client) | `io.lettuce:lettuce-core` | MIT | — |
| thumbnailator | `net.coobird:thumbnailator` | MIT | — |
| SLF4J (api / jul bridge) | `org.slf4j:*` | MIT | — |
| Jakarta EE API family (activation / annotation / persistence / transaction / xml.bind) | `jakarta.*` | EDL 1.0 / EPL 2.0 (some GPL2 w/ CPE) | Used as API dependencies only |
| JAXB (core / runtime / txw2) | `org.glassfish.jaxb:*` | EDL 1.0 | — |
| HdrHistogram / LatencyUtils | `org.hdrhistogram` / `org.latencyutils` | BSD-2-Clause / CC0 | — |

---

## Frontend (Flutter / Dart)

The frontend third-party inventory is generated automatically by Flutter at build time; see the build
output `flutter_assets/NOTICES`. Main direct dependencies (`frontend/pubspec.yaml`) and their licenses:

| Component | License | Upstream |
|---|---|---|
| Flutter SDK and framework | BSD-3-Clause | https://flutter.dev |
| dio | MIT | https://pub.dev/packages/dio |
| flutter_riverpod | MIT | https://pub.dev/packages/flutter_riverpod |
| go_router | BSD-3-Clause | https://pub.dev/packages/go_router |
| drift / sqlite3_flutter_libs | MIT | https://pub.dev/packages/drift |
| media_kit family | MIT | https://pub.dev/packages/media_kit |
| flutter_soloud | MIT | https://pub.dev/packages/flutter_soloud |
| cached_network_image family | BSD-3-Clause | https://pub.dev/packages/cached_network_image |
| fl_chart | MIT | https://pub.dev/packages/fl_chart |
| intl | BSD-3-Clause | https://pub.dev/packages/intl |
| uuid / crypto / cryptography | MIT / BSD | https://pub.dev |
| photo_manager / image_picker and other plugins | Per upstream (mostly MIT / BSD) | https://pub.dev |

> Dart ecosystem dependencies are mostly MIT / BSD-3-Clause. Per-component copyright and full license
> texts are in the build output `flutter_assets/NOTICES`.

---

## Fonts and media assets

| Asset | License | Note |
|---|---|---|
| Noto Sans SC / Noto Serif SC | SIL Open Font License 1.1 | Google Noto project fonts |
| Inter | SIL Open Font License 1.1 | License text at `frontend/assets/fonts/OFL-Inter.txt` |
| JetBrains Mono | SIL Open Font License 1.1 | License text at `frontend/assets/fonts/OFL-JetBrainsMono.txt` |
| Documentation UI illustrations and demo media | Public domain / CC0 (or equivalent) | See README "Disclaimer" |

---

## Disclaimer

This NOTICE is only an attribution and license inventory of third-party components, and does not
constitute endorsement of any third-party trademark, service, or content. The complete and current
text of third-party components and their upstream licenses is as published in their respective
upstream repositories; in case of conflict, the original license text prevails.

This file is a curated summary. The authoritative, machine-generated inventories are the build
outputs `backend/target/reports/licenses/THIRD-PARTY.txt` (backend, Maven) and
`flutter_assets/NOTICES` (frontend, Flutter); if they diverge, those build outputs take precedence.
