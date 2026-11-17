-- 使用临时表复制当前照片表结构和索引，避免污染开发数据库。
BEGIN;

SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';
SET LOCAL work_mem = '64MB';

CREATE TEMP TABLE photo_items_scale
    (LIKE omni.photo_items INCLUDING ALL)
    ON COMMIT DROP;

CREATE TEMP TABLE photo_favorites_scale
    (LIKE omni.photo_favorites INCLUDING ALL)
    ON COMMIT DROP;

INSERT INTO photo_items_scale (
    id,
    owner_user_id,
    file_node_id,
    title,
    description,
    width,
    height,
    orientation,
    date_taken,
    gps_latitude,
    gps_longitude,
    format,
    file_size,
    metadata_status,
    provider_metadata,
    created_at,
    updated_at,
    gps_location
)
SELECT md5('photo-' || sequence)::uuid,
       '11111111-1111-1111-1111-111111111111'::uuid,
       md5('file-' || sequence)::uuid,
       'Scale photo ' || sequence,
       'Photo pagination scale fixture ' || sequence,
       1920 + (sequence % 3)::int * 640,
       1080 + (sequence % 3)::int * 360,
       1,
       TIMESTAMPTZ '2026-07-25 00:00:00+08' - (sequence || ' hours')::interval,
       30.0000000 + (sequence % 1000)::numeric / 10000,
       120.0000000 + (sequence % 1000)::numeric / 10000,
       CASE sequence % 4
           WHEN 0 THEN 'JPEG'
           WHEN 1 THEN 'PNG'
           WHEN 2 THEN 'HEIC'
           ELSE 'WEBP'
       END,
       1048576 + sequence,
       'MATCHED',
       jsonb_build_object('fixture', true, 'sequence', sequence),
       TIMESTAMPTZ '2026-07-25 00:00:00+08' - (sequence || ' seconds')::interval,
       TIMESTAMPTZ '2026-07-25 00:00:00+08' - (sequence || ' seconds')::interval,
       jsonb_build_object('city', 'Scale City ' || (sequence % 20))
  FROM generate_series(1, 100000) AS fixture(sequence);

INSERT INTO photo_favorites_scale (
    id,
    owner_user_id,
    photo_id,
    created_at,
    version
)
SELECT md5('favorite-' || sequence)::uuid,
       '11111111-1111-1111-1111-111111111111'::uuid,
       md5('photo-' || sequence)::uuid,
       TIMESTAMPTZ '2026-07-25 00:00:00+08' - (sequence || ' seconds')::interval,
       0
  FROM generate_series(10, 100000, 10) AS fixture(sequence);

ANALYZE photo_items_scale;
ANALYZE photo_favorites_scale;

SELECT 'fixture_counts' AS check_name,
       (SELECT COUNT(*) FROM photo_items_scale) AS photos,
       (SELECT COUNT(*) FROM photo_favorites_scale) AS favorites;

SELECT 'photo_page_first' AS plan_name;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF)
SELECT p.id,
       p.file_node_id,
       p.title,
       p.description,
       p.width,
       p.height,
       p.orientation,
       p.date_taken,
       p.gps_latitude,
       p.gps_longitude,
       p.format,
       p.file_size,
       p.cover_file_id,
       p.metadata_status,
       p.created_at
  FROM photo_items_scale p
 WHERE p.owner_user_id = '11111111-1111-1111-1111-111111111111'::uuid
 ORDER BY p.created_at DESC
 LIMIT 50 OFFSET 0;

SELECT 'photo_page_deep' AS plan_name;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF)
SELECT p.id,
       p.file_node_id,
       p.title,
       p.created_at
  FROM photo_items_scale p
 WHERE p.owner_user_id = '11111111-1111-1111-1111-111111111111'::uuid
 ORDER BY p.created_at DESC
 LIMIT 50 OFFSET 99950;

SELECT 'photo_count' AS plan_name;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF)
SELECT COUNT(*)
  FROM photo_items_scale p
 WHERE p.owner_user_id = '11111111-1111-1111-1111-111111111111'::uuid;

SELECT 'favorite_page_first' AS plan_name;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF)
SELECT p.id,
       p.file_node_id,
       p.title,
       p.created_at
  FROM photo_items_scale p
  JOIN photo_favorites_scale f
    ON f.photo_id = p.id
   AND f.owner_user_id = '11111111-1111-1111-1111-111111111111'::uuid
 WHERE p.owner_user_id = '11111111-1111-1111-1111-111111111111'::uuid
 ORDER BY p.created_at DESC
 LIMIT 50 OFFSET 0;

SELECT 'timeline_month_page' AS plan_name;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF)
SELECT DATE_TRUNC('month', p.date_taken AT TIME ZONE 'Asia/Shanghai') AS month_start,
       COUNT(*) AS photo_count
  FROM photo_items_scale p
 WHERE p.owner_user_id = '11111111-1111-1111-1111-111111111111'::uuid
   AND p.date_taken IS NOT NULL
 GROUP BY month_start
 ORDER BY month_start DESC
 LIMIT 50 OFFSET 0;

SELECT 'format_group_page' AS plan_name;
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, TIMING OFF)
SELECT COALESCE(NULLIF(p.format, ''), '未知') AS group_key,
       COUNT(*) AS photo_count
  FROM photo_items_scale p
 WHERE p.owner_user_id = '11111111-1111-1111-1111-111111111111'::uuid
 GROUP BY group_key
 ORDER BY group_key ASC
 LIMIT 50 OFFSET 0;

ROLLBACK;
