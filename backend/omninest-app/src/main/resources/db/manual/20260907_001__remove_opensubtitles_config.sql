-- 2026-09-07 移除 OpenSubtitles 字幕自动下载配置。
-- 适用版本：已执行过包含 media.subtitle.key 行的旧版 V002 基线的开发数据库。
-- 前置条件：可连接目标 PostgreSQL 实例；无需停止应用角色（HOT 刷新，重试幂等）。
-- 影响：从 omni.config_entries 删除 1 行 STRING 配置（OpenSubtitles API Key），
--       字幕来源改为手动上传，不再消费该配置；不修改任何其他行。
-- 校验：执行脚本末尾的校验查询，应返回 0 行。
-- 回滚：INSERT INTO omni.config_entries
--       (config_key, config_value, value_type, category, refresh_scope, description, is_sensitive)
--       VALUES ('media.subtitle.key', '', 'STRING', 'media', 'HOT', 'OpenSubtitles API Key', true);

DELETE FROM omni.config_entries
WHERE config_key = 'media.subtitle.key';

-- 校验：应返回 0 行。
SELECT config_key
FROM omni.config_entries
WHERE config_key = 'media.subtitle.key';
