-- 存量库补齐（2026-11-20）：影视刮削新增 TMDB 图床地址与出站代理两个配置项。
--
-- 配套改动：V002__builtin_catalog.sql 已就地补上同一批基线行；本脚本只服务已执行过
-- V002 的旧库。执行后需 `flyway repair` 重算 V002 的 checksum，否则启动时会因迁移
-- 指纹变化失败。严禁新增 V003。
--
-- 幂等：重复执行不会产生重复配置行；管理员已改过的值不会被覆盖。

INSERT INTO "omni"."config_entries" (
    "config_key", "config_value", "value_type", "category",
    "refresh_scope", "description", "is_sensitive"
) VALUES
    ('media.tmdb.image-url', 'https://image.tmdb.org/t/p', 'STRING', 'media',
     'HOT', 'TMDB 图床基础地址', false),
    ('media.tmdb.proxy-url', '', 'STRING', 'media',
     'HOT', 'TMDB 出站代理，如 http://127.0.0.1:7897（留空直连）', false)
ON CONFLICT ("config_key") DO NOTHING;
