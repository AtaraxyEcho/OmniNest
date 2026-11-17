-- 2026-10-24 基线升级脚本（仅用于已经执行过上一版 V001/V002 的数据库）。
--
-- 新安装不需要执行：V001 已包含 as_version_of_file_id、timestamptz 列与 UUID 默认值，
-- V002 已移除重复的 SHARE_ACCESS。执行前先备份；执行后必须用 Flyway repair
-- 让 V001/V002 的校验和与新基线文件一致，否则应用启动时 Flyway validate 会失败。
--
-- 用法：
--   docker compose -f deploy/prod/docker-compose.yml exec -T postgres \
--     psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 \
--     < deploy/db/upgrade-baseline-20261024.sql
--   mvn -pl omninest-app org.flywaydb:flyway-maven-plugin:11.14.1:repair \
--     -Dflyway.url=... -Dflyway.user=... -Dflyway.password=... \
--     -Dflyway.schemas=omni \
--     -Dflyway.locations=filesystem:omninest-app/src/main/resources/db/migration

BEGIN;

ALTER TABLE omni.file_upload_sessions
    ADD COLUMN IF NOT EXISTS as_version_of_file_id uuid;

-- 旧列是 timestamp without time zone，写入侧按 UTC 解释；转换必须显式声明 UTC，
-- 否则会按会话时区（Asia/Shanghai）偏移 8 小时。
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'omni' AND table_name = 'reader_catalog_nodes'
          AND column_name = 'created_at' AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE omni.reader_catalog_nodes
            ALTER COLUMN created_at TYPE timestamptz(6) USING created_at AT TIME ZONE 'UTC';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'omni' AND table_name = 'reader_item_sources'
          AND column_name = 'created_at' AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE omni.reader_item_sources
            ALTER COLUMN created_at TYPE timestamptz(6) USING created_at AT TIME ZONE 'UTC';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'omni' AND table_name = 'reader_page_assets'
          AND column_name = 'created_at' AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE omni.reader_page_assets
            ALTER COLUMN created_at TYPE timestamptz(6) USING created_at AT TIME ZONE 'UTC';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'omni' AND table_name = 'reader_pages'
          AND column_name = 'created_at' AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE omni.reader_pages
            ALTER COLUMN created_at TYPE timestamptz(6) USING created_at AT TIME ZONE 'UTC';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'omni' AND table_name = 'reader_items'
          AND column_name = 'parsed_at' AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE omni.reader_items
            ALTER COLUMN parsed_at TYPE timestamptz(6) USING parsed_at AT TIME ZONE 'UTC';
    END IF;
END $$;

ALTER TABLE omni.reader_catalog_nodes ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.reader_item_sources ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.reader_page_assets ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.reader_pages ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.sync_events ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.storage_import_tasks ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.storage_remote_metadata_cache ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.sync_event_checkpoints ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE omni.user_preferences ALTER COLUMN created_at SET DEFAULT now();

DELETE FROM omni.notification_types WHERE type_code = 'SHARE_ACCESS';

COMMIT;
