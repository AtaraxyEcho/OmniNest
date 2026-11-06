-- 2026-11-06 基线升级脚本（仅用于已经执行过既有 V001 的存量数据库）。
--
-- 本次基线的结构变化：补齐内容回收与库源清理所需的按列索引。
-- 这些外键列此前只有以 owner_user_id 开头的复合索引，内容回收按
-- track/photo/video/file 标识单独 IN (...) 删除时用不到该前缀。
--
-- 新安装不需要执行：V001 已包含全部索引。
-- 已有环境执行顺序（先建索引，最后 repair 对齐校验和；repair 不能单独使用）：
--   docker exec omninest-postgres psql -U omninest -d omninest -v ON_ERROR_STOP=1 \
--     < deploy/db/upgrade-baseline-20261106.sql
--   mvn -pl omninest-app org.flywaydb:flyway-maven-plugin:11.14.1:repair \
--     -Dflyway.url=... -Dflyway.user=... -Dflyway.password=...
--
-- 建索引一律 CONCURRENTLY 且位于事务块之外：事务内建索引会持写锁到 COMMIT，
-- 整个升级窗口内业务写入全部排队。CONCURRENTLY 失败会留下 INVALID 索引，
-- `IF NOT EXISTS` 不会替你重建；升级后先确认
-- `select indisvalid from pg_index where indexrelid = '<索引>'::regclass`。

CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_file_access_records_file_node" ON "omni"."file_access_records" ("file_node_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_file_favorites_file_node" ON "omni"."file_favorites" ("file_node_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_music_favorites_track" ON "omni"."music_favorites" ("track_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_music_play_history_track" ON "omni"."music_play_history" ("track_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_music_playlist_items_track" ON "omni"."music_playlist_items" ("track_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_photo_analysis_runs_photo_id" ON "omni"."photo_content_analysis_runs" ("photo_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_photo_content_labels_photo_id" ON "omni"."photo_content_labels" ("photo_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_media_watch_history_video_item" ON "omni"."media_watch_history" ("video_item_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_media_video_favorites_video_item" ON "omni"."media_video_favorites" ("video_item_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_media_video_collection_items_video_item" ON "omni"."media_video_collection_items" ("video_item_id");
CREATE INDEX CONCURRENTLY IF NOT EXISTS "idx_media_scan_candidates_library_source" ON "omni"."media_scan_candidates" ("library_source_id");
