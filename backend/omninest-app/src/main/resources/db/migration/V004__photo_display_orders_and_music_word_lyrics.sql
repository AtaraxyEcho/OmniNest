-- V004: 照片多视图自定义排序持久化表 + 音乐逐字歌词列
CREATE TABLE IF NOT EXISTS "omni"."photo_display_orders" (
    "id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "owner_user_id" uuid NOT NULL,
    "context_key" varchar(128) NOT NULL,
    "ordered_photo_ids" jsonb NOT NULL DEFAULT '[]'::jsonb,
    "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
    "version" int8 NOT NULL DEFAULT 0,
    CONSTRAINT "pk_photo_display_orders" PRIMARY KEY ("id"),
    CONSTRAINT "uk_photo_display_orders_owner_context" UNIQUE ("owner_user_id", "context_key")
);

CREATE INDEX IF NOT EXISTS "idx_photo_display_orders_owner"
    ON "omni"."photo_display_orders" ("owner_user_id");

COMMENT ON TABLE "omni"."photo_display_orders"
    IS '照片多视图上下文（如 library:YYYY-MM-DD、favorites）的自定义拖拽排序持久化记录';
COMMENT ON COLUMN "omni"."photo_display_orders"."context_key"
    IS '排序上下文键，例如 library:2026-11-21 或 favorites';
COMMENT ON COLUMN "omni"."photo_display_orders"."ordered_photo_ids"
    IS '按展示顺序排列的照片 UUID JSON 数组';

ALTER TABLE "omni"."music_tracks"
    ADD COLUMN IF NOT EXISTS "lyrics_words" text,
    ADD COLUMN IF NOT EXISTS "manual_original_lyrics_words" text;

COMMENT ON COLUMN "omni"."music_tracks"."lyrics_words"
    IS '本地曲目逐字歌词原文（支持 YRC / ELRC / KRC 格式）';
COMMENT ON COLUMN "omni"."music_tracks"."manual_original_lyrics_words"
    IS '人工编辑前保存的原始逐字歌词快照，用于恢复默认';
