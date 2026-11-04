-- 2026-11-04 基线升级脚本（仅用于已经执行过既有 V001 的存量数据库）。
--
-- 本次基线的结构变化：
--   1. 阅读器书签/语言/阅读模式列宽与 DTO @Size / JPA Entity 对齐，
--      批注长文本保持 4096 不变；消除合法长文本落库 500；
--   2. 补齐音乐/阅读器/用户目录模糊搜索所需的 pg_trgm GIN 索引，避免全表扫描；
--   3. 共享空间账本新增 reserved_bytes，用于上传会话原子预留配额。
--
-- 新安装不需要执行：V001 已包含全部变更。
-- 已有环境执行顺序（先升级结构，最后 repair 对齐校验和；repair 不能单独使用）：
--   docker exec omninest-postgres psql -U omninest -d omninest -v ON_ERROR_STOP=1 \
--     < deploy/db/upgrade-baseline-20261104.sql
--   docker compose -f deploy/prod/docker-compose.yml run --rm --entrypoint sh backend-api \
--     -c 'java -cp /app/BOOT-INF/classes:/app/BOOT-INF/lib/* -Dloader.main=org.flywaydb.core.Flyway \
--         org.springframework.boot.loader.launch.PropertiesLauncher repair'
--
-- 脚本可重复执行。

ALTER TABLE "omni"."reader_bookmarks"
    ALTER COLUMN "note" TYPE varchar(2000);

ALTER TABLE "omni"."reader_items"
    ALTER COLUMN "language" TYPE varchar(50);

ALTER TABLE "omni"."reader_progress"
    ALTER COLUMN "reading_mode" TYPE varchar(50);

ALTER TABLE "omni"."shared_space_usage"
    ADD COLUMN IF NOT EXISTS "reserved_bytes" int8 NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conname = 'chk_shared_space_usage_bytes'
           AND conrelid = 'omni.shared_space_usage'::regclass
    ) THEN
        ALTER TABLE "omni"."shared_space_usage"
            ADD CONSTRAINT "chk_shared_space_usage_bytes" CHECK (
                used_bytes >= 0 AND reserved_bytes >= 0 AND file_count >= 0
            );
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS "idx_auth_users_display_name_trgm" ON "omni"."auth_users"
  USING gin (lower("display_name") "public"."gin_trgm_ops");
CREATE INDEX IF NOT EXISTS "idx_music_tracks_album_trgm" ON "omni"."music_tracks"
  USING gin (lower("album_title") "public"."gin_trgm_ops");
CREATE INDEX IF NOT EXISTS "idx_music_albums_title_trgm" ON "omni"."music_albums"
  USING gin (lower("title") "public"."gin_trgm_ops");
CREATE INDEX IF NOT EXISTS "idx_music_artists_name_trgm" ON "omni"."music_artists"
  USING gin (lower("name") "public"."gin_trgm_ops");
CREATE INDEX IF NOT EXISTS "idx_reader_items_title_trgm" ON "omni"."reader_items"
  USING gin (lower("title") "public"."gin_trgm_ops");
CREATE INDEX IF NOT EXISTS "idx_reader_items_author_trgm" ON "omni"."reader_items"
  USING gin (lower("author_name") "public"."gin_trgm_ops");
