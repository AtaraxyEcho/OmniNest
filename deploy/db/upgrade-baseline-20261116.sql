-- 存量库补齐（2026-11-16）：桌面与样例一比一对齐新增的曲目色相、分享策略，
-- 并为音乐元数据编辑补充跨设备保存封面 URL 与恢复原始歌词快照的列。
--
-- 配套改动：V001__init_schema.sql 已就地补上同一列；本脚本只服务已执行过
-- V001 的旧库。执行后需 `flyway repair` 重算 V001 的 checksum，否则启动时
-- 会因迁移指纹变化失败。严禁新增 V003。
--
-- Now Playing 的 `.focus::before` / `.deck-aura` 颜色来自曲目 `--hue`，
-- 样例在曲目数据里直接给出色相；这里落成可空列，扫描/刮削任务可回填，
-- 未提取时前端回落到强调色。

ALTER TABLE "omni"."music_tracks"
    ADD COLUMN IF NOT EXISTS "hue" int4;

ALTER TABLE "omni"."share_links"
    ADD COLUMN IF NOT EXISTS "allow_downloads" bool NOT NULL DEFAULT true;

ALTER TABLE "omni"."music_tracks"
    ADD COLUMN IF NOT EXISTS "manual_original_metadata" jsonb,
    ADD COLUMN IF NOT EXISTS "manual_original_lyrics_raw" text,
    ADD COLUMN IF NOT EXISTS "manual_original_lyrics_translation" text;

COMMENT ON COLUMN "omni"."share_links"."allow_downloads" IS
    '公开访问是否允许下载或转存';

COMMENT ON COLUMN "omni"."music_tracks"."hue" IS
    '曲目色相 0-359（HSV hue），供 Now Playing 的 focus/deck-aura 取色；NULL 表示未提取';
COMMENT ON COLUMN "omni"."music_tracks"."manual_original_metadata" IS
    '歌曲人工元数据编辑前的结构化快照';
COMMENT ON COLUMN "omni"."music_tracks"."manual_original_lyrics_raw" IS
    '歌曲人工编辑前的歌词原文';
COMMENT ON COLUMN "omni"."music_tracks"."manual_original_lyrics_translation" IS
    '歌曲人工编辑前的歌词译文';

ALTER TABLE "omni"."media_video_collections"
    DROP CONSTRAINT IF EXISTS "chk_media_video_collections_type";

ALTER TABLE "omni"."media_video_collections"
    ADD CONSTRAINT "chk_media_video_collections_type"
    CHECK ("collection_type" IN ('MANUAL', 'AUTO', 'WATCHLIST'));

CREATE UNIQUE INDEX IF NOT EXISTS "uniq_media_video_collections_owner_watchlist"
    ON "omni"."media_video_collections" ("owner_user_id")
    WHERE "collection_type" = 'WATCHLIST';
