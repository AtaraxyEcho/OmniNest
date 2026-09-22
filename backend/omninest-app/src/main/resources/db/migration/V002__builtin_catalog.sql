-- 系统实例单例。
INSERT INTO omni.system_instances (
    id,
    setup_state,
    instance_name,
    default_locale,
    default_timezone
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'SETUP_REQUIRED',
    'OmniNest',
    'zh-CN',
    'Asia/Shanghai'
);

-- 配置中心受控目录。V002 为新安装提供完整基线；应用启动仅同步元数据和兼容数据。
INSERT INTO omni.config_entries (
    config_key,
    config_value,
    value_type,
    category,
    refresh_scope,
    description,
    is_sensitive
) VALUES
    ('media.transcode.enabled', 'true', 'BOOLEAN', 'media', 'HOT', '是否启用媒体转码', false),
    ('app.version.latest', '', 'STRING', 'general', 'HOT', '客户端最新版本号（留空表示已最新）', false),
    ('app.version.release-notes-url', '', 'STRING', 'general', 'HOT', '当前版本发布说明地址', false),
    ('app.version.download-url', '', 'STRING', 'general', 'HOT', '安装包下载页地址', false),
    ('media.import.enabled', 'true', 'BOOLEAN', 'media', 'HOT', '是否启用媒体自动导入', false),
    ('reader.import.enabled', 'true', 'BOOLEAN', 'reader', 'HOT', '是否启用阅读内容自动导入', false),
    ('photo.backup', 'true', 'BOOLEAN', 'photo', 'HOT', '是否启用照片自动备份', false),
    ('photo.geo.rate', '1', 'NUMBER', 'photo', 'HOT', '地理编码每秒请求上限', false),
    ('photo.geo.offline', 'true', 'BOOLEAN', 'photo', 'HOT', '是否启用 GeoNames 离线逆地理编码', false),
    ('photo.geo.nominatim', 'false', 'BOOLEAN', 'photo', 'HOT', '离线未命中时是否回退 Nominatim 在线服务', false),
    ('photo.geo.max-distance-km', '100', 'NUMBER', 'photo', 'HOT', '离线最近城市最大可信距离（公里，0 表示不限制）', false),
    ('photo.geo.import.batch-size', '1000', 'NUMBER', 'photo', 'HOT', 'GeoNames 导入每批写入行数', false),
    ('photo.geo.import.auto', 'true', 'BOOLEAN', 'photo', 'HOT', '启动时无已发布数据集且文件齐全时自动触发 GeoNames 导入', false),
    ('storage.quota.default', '10', 'NUMBER', 'storage', 'HOT', '新用户默认存储配额（GB，0 表示无限制）', false),
    ('storage.quota.warning', '80', 'NUMBER', 'storage', 'HOT', '存储配额预警阈值百分比', false),
    ('share.enabled', 'true', 'BOOLEAN', 'storage', 'HOT', '是否启用共享空间', false),
    ('share.max-bytes', '322122547200', 'NUMBER', 'storage', 'HOT', '共享空间最大容量（字节，0 表示无限制）', false),
    ('upload.rate.enabled', 'true', 'BOOLEAN', 'upload', 'HOT', '是否启用上传签发限速', false),
    ('security.rate-limit', '120', 'NUMBER', 'security', 'HOT', '默认接口限流上限', false),
    ('clamav.enabled', 'false', 'BOOLEAN', 'security', 'HOT', '是否启用 ClamAV 文件安全扫描（公网生产需在配置中心改为 true）', false),
    ('clamav.host', 'localhost', 'STRING', 'security', 'HOT', 'ClamAV 服务主机', false),
    ('clamav.port', '3310', 'NUMBER', 'security', 'HOT', 'ClamAV 服务端口', false),
    ('clamav.timeout-millis', '2000000', 'NUMBER', 'security', 'HOT', '单文件安全扫描时限（毫秒，活性护栏）', false),
    ('security.quarantine.retention-days', '7', 'NUMBER', 'security', 'HOT', '隔离滞留对象保留天数', false),
    ('log-retention.enabled', 'true', 'BOOLEAN', 'general', 'HOT', '是否启用日志与临时文件保留清理任务', false),
    ('log-retention.retention-days', '14', 'NUMBER', 'general', 'HOT', '日志归档与临时文件保留天数', false),
    ('log-retention.scan-paths', 'logs', 'STRING', 'general', 'HOT', '保留清理扫描目录（逗号分隔的运行目录相对路径）', false),
    ('weather.enabled', 'true', 'BOOLEAN', 'weather', 'HOT', '是否启用天气服务', false),
    ('media.tmdb.enabled', 'true', 'BOOLEAN', 'media', 'HOT', '是否启用 TMDB', false),
    ('media.tmdb.key', '', 'STRING', 'media', 'HOT', 'TMDB v3 API Key', true),
    ('media.tmdb.token', '', 'STRING', 'media', 'HOT', 'TMDB v4 Access Token', true),
    ('media.tmdb.url', 'https://api.themoviedb.org/3', 'STRING', 'media', 'HOT', 'TMDB API 基础地址', false),
    ('media.tmdb.lang', 'zh-CN', 'STRING', 'media', 'HOT', 'TMDB 返回语言', false),
    ('media.tmdb.timeout', '15', 'NUMBER', 'media', 'HOT', 'TMDB 请求超时（秒）', false),
    ('media.tmdb.strategy', 'NORMALIZED_AND_FALLBACKS', 'STRING', 'media', 'HOT', 'TMDB 搜索策略', false),
    ('media.tmdb.limit', '8', 'NUMBER', 'media', 'HOT', 'TMDB 单次搜索结果上限', false),
    ('media.tmdb.adult', 'false', 'BOOLEAN', 'media', 'HOT', 'TMDB 是否包含成人内容', false),
    ('reader.gbooks.enabled', 'false', 'BOOLEAN', 'reader', 'HOT', '是否启用 Google Books', false),
    ('reader.gbooks.url', 'https://www.googleapis.com/books/v1', 'STRING', 'reader', 'HOT', 'Google Books API 地址', false),
    ('reader.gbooks.lang', 'zh-CN', 'STRING', 'reader', 'HOT', 'Google Books 返回语言', false),
    ('reader.gbooks.limit', '5', 'NUMBER', 'reader', 'HOT', 'Google Books 单次搜索结果上限', false),
    ('reader.gbooks.timeout', '40', 'NUMBER', 'reader', 'HOT', 'Google Books 请求超时（秒）', false),
    ('reader.gbooks.key', '', 'STRING', 'reader', 'HOT', 'Google Books API Key', true),
    ('reader.openlib.enabled', 'false', 'BOOLEAN', 'reader', 'HOT', '是否启用 Open Library', false),
    ('reader.openlib.url', 'https://openlibrary.org', 'STRING', 'reader', 'HOT', 'Open Library API 地址', false),
    ('reader.openlib.lang', 'zh', 'STRING', 'reader', 'HOT', 'Open Library 返回语言', false),
    ('music.musicbrainz.enabled', 'true', 'BOOLEAN', 'music', 'HOT', '是否启用 MusicBrainz', false),
    ('music.import.enabled', 'true', 'BOOLEAN', 'music', 'HOT', '是否启用音乐自动导入', false),
    ('music.musicbrainz.url', 'https://musicbrainz.org/ws/2', 'STRING', 'music', 'HOT', 'MusicBrainz API 地址', false),
    ('music.musicbrainz.ua', 'OmniNest/0.1.0 (music@omninest.local)', 'STRING', 'music', 'HOT', 'MusicBrainz User-Agent', false),
    ('music.musicbrainz.cover-url', 'https://coverartarchive.org/release', 'STRING', 'music', 'HOT', 'MusicBrainz 封面地址', false),
    ('music.online.enabled', 'true', 'BOOLEAN', 'music', 'HOT', '是否启用在线音乐', false),
    ('music.netease.enabled', 'true', 'BOOLEAN', 'music', 'HOT', '网易云音乐平台开关', false),
    ('music.netease.url', 'http://localhost:3001', 'STRING', 'music', 'HOT', '网易云音乐 API 地址', false),
    ('music.netease.hosts', 'music.126.net,music.163.com', 'STRING', 'music', 'HOT', '网易云音乐播放域名后缀', false),
    ('photo.ai.enabled', 'true', 'BOOLEAN', 'photo', 'HOT', '是否启用图像分析', false),
    ('photo.ai.url', 'http://localhost:8090', 'STRING', 'photo', 'HOT', '图像分析服务地址', false),
    ('photo.ai.timeout', '30', 'NUMBER', 'photo', 'HOT', '图像分析请求超时（秒）', false),
    ('backdrop.max-image-bytes', '20971520', 'NUMBER', 'backdrop', 'HOT', '背景图片单文件大小上限（字节）', false),
    ('backdrop.max-video-bytes', '469762048', 'NUMBER', 'backdrop', 'HOT', '背景视频单文件大小上限（字节）', false),
    ('backdrop.max-assets-per-user', '30', 'NUMBER', 'backdrop', 'HOT', '每用户背景素材数量上限', false),
    ('backdrop.upload.rate-per-hour', '20', 'NUMBER', 'backdrop', 'HOT', '每用户每小时上传次数上限', false),
    ('weather.qweather.project', '', 'STRING', 'weather', 'HOT', '和风天气项目 ID', false),
    ('weather.qweather.credential', '', 'STRING', 'weather', 'HOT', '和风天气凭据 ID', false),
    ('weather.qweather.url', 'https://devapi.qweather.com', 'STRING', 'weather', 'HOT', '和风天气 API 地址', false),
    ('weather.qweather.key', '', 'STRING', 'weather', 'HOT', '和风天气 Ed25519 私钥', true),
    ('weather.location', '北京', 'STRING', 'weather', 'HOT', '天气默认位置', false),
    ('auth.two-factor.required-roles', 'SUPER_ADMIN,ADMIN', 'STRING', 'auth', 'HOT', '强制开启两步验证的角色编码列表（逗号分隔，留空表示全员自愿）', false);

-- 内置角色。
INSERT INTO omni.auth_roles (id, code, name, description, built_in, enabled) VALUES
    ('4e302a1e-3af2-4e23-8702-5475f5448025', 'SUPER_ADMIN', '超级管理员', '系统最高权限角色。', true, true),
    ('00621191-231c-423c-831a-2e18e1d29af8', 'ADMIN', '管理员', '负责用户和系统日常管理。', true, true),
    ('53e2e138-59b7-4fa6-988f-58554f34b8d3', 'MEMBER', '成员', '拥有个人空间常规读写权限。', true, true),
    ('e8eb254a-cf7f-4792-9b64-d354fb901e69', 'GUEST', '访客', '拥有有限只读权限。', true, true);

-- 内置权限。
INSERT INTO omni.auth_permissions (id, code, name, module, description, enabled) VALUES
    ('bdf881c9-a30b-4e30-813e-2a3e310b56c2', 'profile:read', '读取个人资料', 'profile', '允许读取当前用户资料。', true),
    ('a1b2c3d4-1111-1111-1111-111111111111', 'profile:write', '修改个人资料', 'profile', '允许修改当前用户资料。', true),
    ('1accd3e9-6768-4439-af41-298d1dbe1df3', 'file:read', '读取文件', 'file', '允许查看文件和目录。', true),
    ('eba7e050-1054-42f3-8a1d-996e802964cc', 'file:write', '管理文件', 'file', '允许创建和修改文件。', true),
    ('18a388e5-b0a7-4ca3-a18e-5f798ac78277', 'media:read', '读取媒体', 'media', '允许查看媒体内容。', true),
    ('a1b2c3d4-2222-2222-2222-222222222222', 'media:write', '管理媒体', 'media', '允许导入和修改媒体内容。', true),
    ('a1b2c3d4-5555-5555-5555-555555555555', 'media:library:manage', '管理媒体库', 'media', '允许维护服务器媒体库、扫描和访问授权。', true),
    ('a1b2c3d4-3333-3333-3333-333333333333', 'photo:read', '读取照片', 'photo', '允许查看照片和相册。', true),
    ('a1b2c3d4-4444-4444-4444-444444444444', 'photo:write', '管理照片', 'photo', '允许导入和修改照片。', true),
    ('b2c3d4e4-1111-1111-1111-111111111111', 'photo:admin', '照片管理', 'photo', '允许执行扫描、缩略图重生成等照片管理操作。', true),
    ('a1b2c3d4-8888-8888-8888-888888888888', 'backdrop:read', '读取背景库', 'backdrop', '允许查看背景库素材。', true),
    ('a1b2c3d4-9999-9999-9999-999999999999', 'backdrop:write', '管理背景库', 'backdrop', '允许上传、修改和删除背景素材。', true),
    ('6d1b54bd-c1f3-403b-8428-082821e6de03', 'task:read', '读取任务', 'task', '允许查看当前用户拥有的任务。', true),
    ('a1b2c3d4-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'task:admin', '任务管理', 'task', '允许查看全站任务与死信队列。', true),
    ('4fc5ebd6-ae43-4125-9196-b3c2e15741f3', 'system:config:read', '读取系统配置', 'system', '允许读取系统配置。', true),
    ('80dd01d7-9e38-47ec-b644-fcf7d4bcd024', 'system:config:manage', '管理系统配置', 'system', '允许修改系统配置。', true),
    ('27d7dcd5-92a6-459c-9a7d-48c458dfc8c6', 'system:user:read', '读取用户', 'system', '允许查看系统用户。', true),
    ('d07f3eef-8369-454f-830d-5d45d722934f', 'system:user:manage', '管理用户', 'system', '允许维护系统用户。', true);

-- 访客只读权限。
INSERT INTO omni.auth_role_permissions (role_id, permission_id)
SELECT 'e8eb254a-cf7f-4792-9b64-d354fb901e69', permission.id
FROM omni.auth_permissions permission
WHERE permission.code IN ('profile:read', 'file:read', 'media:read', 'photo:read');

-- 成员个人空间权限。
INSERT INTO omni.auth_role_permissions (role_id, permission_id)
SELECT '53e2e138-59b7-4fa6-988f-58554f34b8d3', permission.id
FROM omni.auth_permissions permission
WHERE permission.code IN (
    'profile:read', 'profile:write', 'file:read', 'file:write',
    'media:read', 'media:write', 'photo:read', 'photo:write', 'task:read',
    'backdrop:read', 'backdrop:write'
);

-- 管理员包含成员权限和用户管理权限，但不包含系统配置修改权限。
INSERT INTO omni.auth_role_permissions (role_id, permission_id)
SELECT '00621191-231c-423c-831a-2e18e1d29af8', permission.id
FROM omni.auth_permissions permission
WHERE permission.code IN (
    'profile:read', 'profile:write', 'file:read', 'file:write',
    'media:read', 'media:write', 'photo:read', 'photo:write', 'photo:admin', 'task:read', 'task:admin',
    'media:library:manage', 'system:config:read', 'system:user:read', 'system:user:manage',
    'backdrop:read', 'backdrop:write'
);

-- 超级管理员拥有当前目录中的全部权限。
INSERT INTO omni.auth_role_permissions (role_id, permission_id)
SELECT '4e302a1e-3af2-4e23-8702-5475f5448025', permission.id
FROM omni.auth_permissions permission;

-- 内置通知类型。
INSERT INTO omni.notification_types (
    id,
    type_code,
    label,
    description,
    icon,
    color,
    sort_order,
    enabled
) VALUES
    ('864b553f-9333-4367-8c3f-f5e2588e248e', 'TASK_COMPLETED', '任务完成',
        '异步任务执行成功', 'check_circle_rounded', '#34D399', 1, true),
    ('6bc8f367-bd04-44b9-b42d-e1fa3a8bf991', 'TASK_FAILED', '任务失败',
        '异步任务执行失败', 'error_rounded', '#F87171', 2, true),
    ('e22d8ccc-4436-485c-836b-81b261f10a7e', 'SHARE_ACCESS', '分享访问',
        '有人访问了你的分享链接', 'share_rounded', '#60A5FA', 3, true),
    ('04a66418-1bd8-4339-8c88-80ef76a2847e', 'SYSTEM_MESSAGE', '系统消息',
        '系统级通知', 'info_rounded', '#C3C0FF', 4, true),
    ('a1b2c3d4-5678-9abc-def0-111111111111', 'MEDIA_SCRAPED', '元数据刮削',
        '媒体元数据刮削完成', 'auto_awesome_rounded', '#A78BFA', 5, true),
    ('a1b2c3d4-5678-9abc-def0-222222222222', 'SHARE_ACCESSED', '分享被访问',
        '有人访问了你的分享链接', 'visibility_rounded', '#60A5FA', 6, true),
    ('a1b2c3d4-5678-9abc-def0-333333333333', 'QUOTA_WARNING', '存储预警',
        '存储空间使用率超过预警阈值', 'storage_rounded', '#FBBF24', 7, true),
    ('a1b2c3d4-5678-9abc-def0-444444444444', 'NEW_DEVICE_LOGIN', '新设备登录',
        '检测到新设备登录', 'phone_android_rounded', '#34D399', 8, true),
    ('a1b2c3d4-5678-9abc-def0-555555555555', 'PASSWORD_CHANGED', '密码已修改',
        '账户密码已成功修改', 'lock_rounded', '#F59E0B', 9, true),
    ('a1b2c3d4-5678-9abc-def0-666666666666', 'SECURITY_THREAT', '安全威胁',
        '文件安全扫描已确认检测到恶意内容', 'security_rounded', '#EF4444', 10, true),
    ('a1b2c3d4-5678-9abc-def0-777777777777', 'SECURITY_SCAN_FAILED', '安全扫描失败',
        '文件安全扫描因服务不可用或处理异常而无法完成', 'warning_amber_rounded', '#F59E0B', 11, true);

-- 内置角色的共享空间权限。
INSERT INTO omni.shared_space_permissions (
    id,
    role_id,
    can_browse,
    can_upload,
    can_download,
    can_delete_own,
    can_delete_any,
    can_move_to,
    can_move_from,
    can_create_folder
) VALUES
    ('b4154371-f81a-407b-a082-72b4288fced1', '4e302a1e-3af2-4e23-8702-5475f5448025',
        true, true, true, true, true, true, true, true),
    ('91a4308c-34d4-4dc9-b647-cd5c722d0baa', '00621191-231c-423c-831a-2e18e1d29af8',
        true, true, true, true, true, true, true, true),
    ('fcf91040-9b81-42b0-bd8e-6b406c15204f', '53e2e138-59b7-4fa6-988f-58554f34b8d3',
        true, true, true, true, false, true, true, true),
    ('0597b024-38e1-40ea-916d-e3875f11431d', 'e8eb254a-cf7f-4792-9b64-d354fb901e69',
        true, false, true, false, false, false, false, false);

-- 共享空间全局用量单例，空库从零开始统计。
INSERT INTO omni.shared_space_usage (id, used_bytes, file_count) VALUES
    ('e745d651-f566-4b98-a484-4a87e92d6217', 0, 0);
