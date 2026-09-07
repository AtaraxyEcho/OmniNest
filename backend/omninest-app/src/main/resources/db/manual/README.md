# Manual database scripts

This directory is the only location for manually executed OmniNest database scripts.

- Scripts here are not discovered by Flyway because `spring.flyway.locations` only includes `db/migration`.
- Stop all application roles and back up PostgreSQL before running an upgrade or cleanup script.
- Read each script's prerequisites, verification query, and rollback notes before execution.
- New installations use `db/migration/V001__init_schema.sql` and `V002__builtin_catalog.sql`; manual scripts are only for existing development databases that already ran an older baseline.

## 2026-08-14 shared media library access

`20260814_006__media_library_shared_access.sql` upgrades an existing development database to the shared local Media Library model. It is idempotent after a successful run. Before changing constraints, it reports and rejects both duplicate and parent/child-overlapping logical library roots; resolve those conflicts manually and rerun the script.

## 2026-08-17 configuration catalog normalization

Run `20260817_001__config_catalog_core_settings.sql` only when an existing database is missing the newly exposed core integration rows. Run `20260817_002__config_key_normalization.sql` afterward to migrate renamed values, seed the complete 55-key catalog, and remove the explicitly deleted keys. The normalization script preserves non-default legacy values, does not decrypt sensitive values, and reports the canonical key count for verification.

`20260814_005__config_catalog_upgrade.sql` is retained only as a compatibility marker for old operational records. It is a no-op and must not be used as a replacement for the 2026-08-17 normalization script.

## 2026-09-07 remove OpenSubtitles config

`20260907_001__remove_opensubtitles_config.sql` deletes the `media.subtitle.key` row for existing development databases whose V002 baseline still contains it. The subtitle auto-download capability was removed and subtitles are managed by manual upload only. The script is idempotent, only deletes that single row, and ends with a verification query that must return zero rows. Roll back by re-inserting the row shown in the script header.
