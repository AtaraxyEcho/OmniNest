-- 2026-11-05 基线升级脚本（仅用于已经执行过既有 V001 的存量数据库）。
--
-- 本次基线的结构变化：
--   1. 补齐文件与相册包含匹配所需的 pg_trgm GIN 索引：
--      文件搜索按数据库实时文件名命中（重命名后不必等正文重解析），
--      相册搜索在 Lucene 索引退役后完全依赖这几条索引；
--   2. 文件正文索引改为以不可变 file_object_id 为键，节点标识与标题不再写进索引。
--
-- 新安装不需要执行：V001 已包含全部索引。
-- 已有环境执行顺序（先建索引，最后 repair 对齐校验和；repair 不能单独使用）：
--   docker exec omninest-postgres psql -U omninest -d omninest -v ON_ERROR_STOP=1 \
--     < deploy/db/upgrade-baseline-20261105.sql
--   docker compose -f deploy/prod/docker-compose.yml run --rm --entrypoint sh backend-api \
--     -c 'java -cp /app/BOOT-INF/classes:/app/BOOT-INF/lib/* -Dloader.main=org.flywaydb.core.Flyway \
--         org.springframework.boot.loader.launch.PropertiesLauncher repair'
--
-- 索引口径变化后旧文档不再被新查询命中，执行完本脚本请由管理员调用
-- POST /api/v1/search/rebuild 重建一次文件正文索引；相册侧无需重建。
--
-- 脚本可重复执行。

CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_file_nodes_name_trgm" ON "omni"."file_nodes"
  USING gin (lower("name") "public"."gin_trgm_ops")
  WHERE "is_deleted" = false;

CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_photo_items_title_trgm" ON "omni"."photo_items"
  USING gin (lower("title") "public"."gin_trgm_ops")
  WHERE "deleted_at" IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_photo_items_description_trgm" ON "omni"."photo_items"
  USING gin (lower("description") "public"."gin_trgm_ops")
  WHERE "deleted_at" IS NULL AND "description" IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_photo_items_ocr_text_trgm" ON "omni"."photo_items"
  USING gin (lower("ocr_text") "public"."gin_trgm_ops")
  WHERE "deleted_at" IS NULL AND "ocr_text" IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_photo_tags_tag_trgm" ON "omni"."photo_tags"
  USING gin (lower("tag") "public"."gin_trgm_ops");
