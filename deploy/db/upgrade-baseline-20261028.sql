-- 2026-10-28 基线升级脚本（仅用于已经执行过 2026-10-24 基线的数据库）。
--
-- 本次 V001 只新增四个高频外键索引，不改列、不删表：
--   idx_photo_items_active_file          照片 -> 当前活动文件节点
--   idx_photo_items_motion_video_file    照片 -> 动态视频文件节点
--   idx_media_video_items_owner_source   派生音轨/版本按源条目查询
--   idx_content_assets_owner_file_node   内容资产按文件节点回查
--
-- 新安装不需要执行：V001 已包含这四条索引。
-- 已有环境执行顺序（先补结构，最后 repair 对齐校验和；repair 不能单独使用）：
--   docker exec omninest-postgres psql -U omninest -d omninest -v ON_ERROR_STOP=1 \
--     < deploy/db/upgrade-baseline-20261028.sql
--   mvn -pl omninest-app org.flywaydb:flyway-maven-plugin:11.14.1:repair \
--     -Dflyway.url=... -Dflyway.user=... -Dflyway.password=... \
--     -Dflyway.schemas=omni \
--     -Dflyway.locations=filesystem:omninest-app/src/main/resources/db/migration
--
-- 分类下推说明：file_nodes.category 允许为空，但扫描类查询只认明确分类；
-- 2026-10-28 在开发库实测活动文件 0 条空分类。若其他环境存在空分类行，
-- 需要先用业务侧重新扫描或一次性回填，不能依赖 repair 或本脚本。

BEGIN;

CREATE INDEX IF NOT EXISTS "idx_photo_items_active_file" ON "omni"."photo_items" USING btree (
  "active_file_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE active_file_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS "idx_photo_items_motion_video_file" ON "omni"."photo_items" USING btree (
  "motion_video_file_node_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE motion_video_file_node_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS "idx_media_video_items_owner_source" ON "omni"."media_video_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "source_video_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE source_video_item_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS "idx_content_assets_owner_file_node" ON "omni"."content_assets" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "file_node_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE file_node_id IS NOT NULL;

COMMIT;
