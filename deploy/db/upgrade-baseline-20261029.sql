-- 2026-10-29 基线升级脚本（仅用于已经执行过既有 V002 内置目录的数据库）。
--
-- 本次 V002 删除十个"可编辑但无读取方"的配置行：
--   security.rate-limit            限流实际读 omninest.rate-limit.default-limit
--   reader.gbooks.*（6 项）        仓库内没有 Google Books provider
--   reader.openlib.*（3 项）       仓库内没有 Open Library provider
--
-- 这些键在管理页能改却不影响任何行为，留着会被当成真实生效的开关。
-- 新安装不需要执行：V002 已不再写入这些行。
-- 已有环境执行顺序（先删行，最后 repair 对齐校验和；repair 不能单独使用）：
--   docker exec omninest-postgres psql -U omninest -d omninest -v ON_ERROR_STOP=1 \
--     < deploy/db/upgrade-baseline-20261029.sql
--   docker compose -f deploy/prod/docker-compose.yml run --rm --entrypoint sh backend-api \
--     -c 'java -cp /app/BOOT-INF/classes:/app/BOOT-INF/lib/* -Dloader.main=org.flywaydb.core.Flyway \
--         org.springframework.boot.loader.launch.PropertiesLauncher repair'
--
-- 脚本可重复执行。

DELETE FROM omni.config_entries
WHERE config_key IN (
    'security.rate-limit',
    'reader.gbooks.enabled',
    'reader.gbooks.url',
    'reader.gbooks.lang',
    'reader.gbooks.limit',
    'reader.gbooks.timeout',
    'reader.gbooks.key',
    'reader.openlib.enabled',
    'reader.openlib.url',
    'reader.openlib.lang'
);
