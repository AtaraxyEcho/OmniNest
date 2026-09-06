-- 动态照片：photo_items 增加运动状态与运动视频派生节点引用
-- 适用版本：当前 V001 基线阶段（未进入历史迁移不可变阶段前与 V001 重写同步发布）
-- 前置条件：数据库中已存在 omni.photo_items 表
-- 影响：新增两个可空列。motion_state 取值 NULL/DETECTED/READY/FAILED；
--       NULL 表示历史照片或非动态照片；motion_video_file_node_id 仅在 READY 时有值，
--       指向 PHOTO_ITEM 源节点下 MOTION_VIDEO 派生资产文件节点，随源节点永久删除自动清理。
-- 校验：SELECT motion_state, count(*) FROM omni.photo_items GROUP BY motion_state;（升级后应只有 NULL）
-- 回滚：ALTER TABLE "omni"."photo_items" DROP COLUMN IF EXISTS "motion_video_file_node_id";
--      ALTER TABLE "omni"."photo_items" DROP COLUMN IF EXISTS "motion_state";

ALTER TABLE "omni"."photo_items" ADD COLUMN IF NOT EXISTS "motion_state" varchar(16);
ALTER TABLE "omni"."photo_items" ADD COLUMN IF NOT EXISTS "motion_video_file_node_id" uuid;
