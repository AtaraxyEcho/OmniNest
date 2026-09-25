-- OmniNest 当前版本数据库基线（由项目维护，禁止再写入导出工具元数据）。
CREATE SCHEMA IF NOT EXISTS omni;

CREATE TABLE "omni"."audit_logs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "actor_user_id" uuid,
  "action" varchar(80) NOT NULL,
  "resource_type" varchar(80) NOT NULL,
  "resource_id" uuid,
  "ip_address" varchar(45),
  "user_agent" varchar(500),
  "request_id" uuid,
  "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."audit_logs"."id" IS '日志唯一标识，主键';
COMMENT ON COLUMN "omni"."audit_logs"."actor_user_id" IS '操作用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."audit_logs"."action" IS '操作动作';
COMMENT ON COLUMN "omni"."audit_logs"."resource_type" IS '资源类型';
COMMENT ON COLUMN "omni"."audit_logs"."resource_id" IS '资源ID';
COMMENT ON COLUMN "omni"."audit_logs"."ip_address" IS '请求IP地址';
COMMENT ON COLUMN "omni"."audit_logs"."user_agent" IS '请求User-Agent';
COMMENT ON COLUMN "omni"."audit_logs"."request_id" IS '请求链路ID';
COMMENT ON COLUMN "omni"."audit_logs"."metadata" IS '扩展元数据，JSONB格式';
COMMENT ON COLUMN "omni"."audit_logs"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."audit_logs" IS '审计日志表，记录用户操作、资源和请求上下文';

CREATE TABLE "omni"."auth_active_sessions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "client_platform" varchar(32) NOT NULL,
  "device_id" varchar(128),
  "device_name" varchar(255),
  "ip_address" varchar(45),
  "issued_at" timestamptz(6) NOT NULL,
  "expires_at" timestamptz(6) NOT NULL,
  "last_active_at" timestamptz(6) NOT NULL DEFAULT now(),
  "revoked_at" timestamptz(6),
  "revoke_reason" varchar(255),
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."auth_active_sessions"."id" IS '会话唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_active_sessions"."user_id" IS '用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."auth_active_sessions"."client_platform" IS '客户端平台：WEB / ANDROID / DESKTOP';
COMMENT ON COLUMN "omni"."auth_active_sessions"."device_id" IS '设备ID';
COMMENT ON COLUMN "omni"."auth_active_sessions"."device_name" IS '设备名称';
COMMENT ON COLUMN "omni"."auth_active_sessions"."ip_address" IS '客户端IP地址';
COMMENT ON COLUMN "omni"."auth_active_sessions"."issued_at" IS '会话签发时间';
COMMENT ON COLUMN "omni"."auth_active_sessions"."expires_at" IS '会话过期时间';
COMMENT ON COLUMN "omni"."auth_active_sessions"."last_active_at" IS '最后活跃时间';
COMMENT ON COLUMN "omni"."auth_active_sessions"."revoked_at" IS '撤销时间';
COMMENT ON COLUMN "omni"."auth_active_sessions"."revoke_reason" IS '撤销原因';
COMMENT ON TABLE "omni"."auth_active_sessions" IS '活跃会话表，用于登录互斥和会话管理';

CREATE TABLE "omni"."auth_backup_codes" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "code_hash" varchar(64) NOT NULL,
  "used_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."auth_backup_codes"."id" IS '备份码唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_backup_codes"."user_id" IS '用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."auth_backup_codes"."code_hash" IS '备份码SHA-256哈希（十六进制，输入为去分隔符大写形式）';
COMMENT ON COLUMN "omni"."auth_backup_codes"."used_at" IS '使用时间，空表示未使用';
COMMENT ON COLUMN "omni"."auth_backup_codes"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."auth_backup_codes" IS '两步验证备份码表，一次性恢复码，启用两步验证时全量重置';

CREATE TABLE "omni"."auth_login_audit" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid,
  "username" varchar(80) NOT NULL,
  "login_result" varchar(32) NOT NULL,
  "client_platform" varchar(32) NOT NULL,
  "device_id" varchar(128),
  "device_name" varchar(255),
  "ip_address" varchar(45),
  "user_agent" varchar(500),
  "failure_reason" varchar(255),
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."auth_login_audit"."id" IS '记录唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_login_audit"."user_id" IS '用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."auth_login_audit"."username" IS '用户名（冗余，便于查询）';
COMMENT ON COLUMN "omni"."auth_login_audit"."login_result" IS '登录结果：SUCCESS / FAILED / DISABLED';
COMMENT ON COLUMN "omni"."auth_login_audit"."client_platform" IS '客户端平台：WEB / ANDROID / DESKTOP';
COMMENT ON COLUMN "omni"."auth_login_audit"."device_id" IS '设备ID';
COMMENT ON COLUMN "omni"."auth_login_audit"."device_name" IS '设备名称';
COMMENT ON COLUMN "omni"."auth_login_audit"."ip_address" IS '客户端IP地址';
COMMENT ON COLUMN "omni"."auth_login_audit"."user_agent" IS '请求User-Agent';
COMMENT ON COLUMN "omni"."auth_login_audit"."failure_reason" IS '失败原因';
COMMENT ON TABLE "omni"."auth_login_audit" IS '登录审计表，记录所有登录尝试';

CREATE TABLE "omni"."auth_permissions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "code" varchar(120) NOT NULL,
  "name" varchar(120) NOT NULL,
  "module" varchar(80) NOT NULL,
  "description" varchar(500),
  "enabled" bool NOT NULL DEFAULT true,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."auth_permissions"."id" IS '权限唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_permissions"."code" IS '权限编码，唯一';
COMMENT ON COLUMN "omni"."auth_permissions"."name" IS '权限名称';
COMMENT ON COLUMN "omni"."auth_permissions"."module" IS '所属业务模块';
COMMENT ON COLUMN "omni"."auth_permissions"."description" IS '权限说明';
COMMENT ON COLUMN "omni"."auth_permissions"."enabled" IS '是否启用';
COMMENT ON COLUMN "omni"."auth_permissions"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."auth_permissions"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."auth_permissions"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."auth_permissions" IS '认证权限表，保存可授予角色的资源操作权限';

CREATE TABLE "omni"."auth_role_permissions" (
  "role_id" uuid NOT NULL,
  "permission_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."auth_role_permissions"."role_id" IS '角色ID，关联auth_roles';
COMMENT ON COLUMN "omni"."auth_role_permissions"."permission_id" IS '权限ID，关联auth_permissions';
COMMENT ON COLUMN "omni"."auth_role_permissions"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."auth_role_permissions" IS '角色权限关联表，保存角色拥有的权限';

CREATE TABLE "omni"."auth_roles" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "code" varchar(80) NOT NULL,
  "name" varchar(120) NOT NULL,
  "description" varchar(500),
  "built_in" bool NOT NULL DEFAULT true,
  "enabled" bool NOT NULL DEFAULT true,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."auth_roles"."id" IS '角色唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_roles"."code" IS '角色编码，唯一';
COMMENT ON COLUMN "omni"."auth_roles"."name" IS '角色名称';
COMMENT ON COLUMN "omni"."auth_roles"."description" IS '角色说明';
COMMENT ON COLUMN "omni"."auth_roles"."built_in" IS '是否为系统内置角色';
COMMENT ON COLUMN "omni"."auth_roles"."enabled" IS '是否启用';
COMMENT ON COLUMN "omni"."auth_roles"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."auth_roles"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."auth_roles"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."auth_roles" IS '认证角色表，保存系统内置角色与后续扩展角色';

CREATE TABLE "omni"."auth_session_revocations" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "session_id" uuid NOT NULL,
  "revoked_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."auth_session_revocations"."id" IS '撤销记录唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_session_revocations"."user_id" IS '用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."auth_session_revocations"."session_id" IS '被撤销的会话ID';
COMMENT ON COLUMN "omni"."auth_session_revocations"."revoked_at" IS '撤销时间';
COMMENT ON TABLE "omni"."auth_session_revocations" IS '会话撤销记录表，作为 Redis 黑名单的 DB 兜底，当 Redis 不可用时用于校验会话是否已被踢出';

CREATE TABLE "omni"."auth_totp_credentials" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "secret" varchar(64) NOT NULL,
  "enabled" bool NOT NULL DEFAULT false,
  "confirmed_at" timestamptz(6),
  "last_used_step" int8,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."auth_totp_credentials"."id" IS 'TOTP凭据唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."user_id" IS '用户ID，关联auth_users，唯一';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."secret" IS 'TOTP共享秘钥，Base32编码';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."enabled" IS '是否已确认启用';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."confirmed_at" IS '确认启用时间';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."last_used_step" IS '最近一次验证成功的时间步（epoch秒/30），用于防重放，仅接受更新的时间步';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."auth_totp_credentials"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."auth_totp_credentials" IS '两步验证TOTP凭据表，每用户至多一条';

CREATE TABLE "omni"."auth_user_roles" (
  "user_id" uuid NOT NULL,
  "role_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."auth_user_roles"."user_id" IS '用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."auth_user_roles"."role_id" IS '角色ID，关联auth_roles';
COMMENT ON COLUMN "omni"."auth_user_roles"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."auth_user_roles" IS '用户角色关联表，保存用户拥有的角色';

CREATE TABLE "omni"."auth_users" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "username" varchar(80) NOT NULL,
  "password_hash" varchar(255) NOT NULL,
  "display_name" varchar(120),
  "avatar_file_id" uuid,
  "email" varchar(255),
  "status" varchar(32) NOT NULL DEFAULT 'ACTIVE'::character varying,
  "quota_bytes" int8 NOT NULL DEFAULT '10737418240'::bigint,
  "used_bytes" int8 NOT NULL DEFAULT 0,
  "reserved_bytes" int8 NOT NULL DEFAULT 0,
  "last_login_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."auth_users"."id" IS '用户唯一标识，主键';
COMMENT ON COLUMN "omni"."auth_users"."username" IS '登录用户名或用户唯一短名';
COMMENT ON COLUMN "omni"."auth_users"."password_hash" IS 'BCrypt加密后的登录密码哈希';
COMMENT ON COLUMN "omni"."auth_users"."display_name" IS '展示名称';
COMMENT ON COLUMN "omni"."auth_users"."avatar_file_id" IS '头像文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."auth_users"."email" IS '用户邮箱';
COMMENT ON COLUMN "omni"."auth_users"."status" IS '状态：ACTIVE / DISABLED';
COMMENT ON COLUMN "omni"."auth_users"."quota_bytes" IS '存储配额字节数，默认10GB';
COMMENT ON COLUMN "omni"."auth_users"."used_bytes" IS '已使用存储字节数';
COMMENT ON COLUMN "omni"."auth_users"."reserved_bytes" IS '写入任务已预留但尚未结算的存储字节数';
COMMENT ON COLUMN "omni"."auth_users"."last_login_at" IS '最后登录时间';
COMMENT ON COLUMN "omni"."auth_users"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."auth_users"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."auth_users"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."auth_users" IS '认证用户表，保存内置登录账号、状态和容量信息';

CREATE TABLE "omni"."backdrop_assets" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "owner_user_id" uuid NOT NULL,
  "title" varchar(200) NOT NULL,
  "media_type" varchar(16) NOT NULL,
  "file_node_id" uuid,
  "playback_file_id" uuid,
  "thumb_file_id" uuid,
  "width" int4,
  "height" int4,
  "duration_ms" int4,
  "video_codec" varchar(32),
  "file_size" int8 NOT NULL,
  "sha256" varchar(64) NOT NULL,
  "status" varchar(16) NOT NULL DEFAULT 'PROCESSING',
  "fail_reason" varchar(200),
  "version" int8 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  CONSTRAINT "chk_backdrop_assets_media_type" CHECK (media_type IN ('image', 'gif', 'video')),
  CONSTRAINT "chk_backdrop_assets_status" CHECK (status IN ('PROCESSING', 'READY', 'FAILED'))
)
;
COMMENT ON COLUMN "omni"."backdrop_assets"."id" IS '背景素材唯一标识，主键';
COMMENT ON COLUMN "omni"."backdrop_assets"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."backdrop_assets"."title" IS '素材展示标题';
COMMENT ON COLUMN "omni"."backdrop_assets"."media_type" IS '媒体类型：image / gif / video';
COMMENT ON COLUMN "omni"."backdrop_assets"."file_node_id" IS '原始素材文件节点ID，关联file_nodes；行先于对象的顺序下，PROCESSING 在途阶段为空，READY 必有值';
COMMENT ON COLUMN "omni"."backdrop_assets"."playback_file_id" IS '壁纸播放用降分辨率衍生节点ID，视频可为空（失败或无需缩放）';
COMMENT ON COLUMN "omni"."backdrop_assets"."thumb_file_id" IS '缩略图文件节点ID，关联file_nodes，GIF和视频为空';
COMMENT ON COLUMN "omni"."backdrop_assets"."width" IS '客户端上报的展示宽度，非可信字段';
COMMENT ON COLUMN "omni"."backdrop_assets"."height" IS '客户端上报的展示高度，非可信字段';
COMMENT ON COLUMN "omni"."backdrop_assets"."duration_ms" IS '客户端上报的展示时长（毫秒），非可信字段';
COMMENT ON COLUMN "omni"."backdrop_assets"."video_codec" IS '服务端 ffprobe 探测的视频编码名（如 h264/hevc），图片与探测失败时为空';
COMMENT ON COLUMN "omni"."backdrop_assets"."file_size" IS '素材文件大小，单位字节';
COMMENT ON COLUMN "omni"."backdrop_assets"."sha256" IS '服务端计算的SHA256，用户级去重键';
COMMENT ON COLUMN "omni"."backdrop_assets"."status" IS '素材状态：PROCESSING / READY / FAILED';
COMMENT ON COLUMN "omni"."backdrop_assets"."fail_reason" IS '失败原因摘要，仅供展示与排障';
COMMENT ON COLUMN "omni"."backdrop_assets"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."backdrop_assets"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."backdrop_assets"."updated_at" IS '更新时间';
COMMENT ON TABLE "omni"."backdrop_assets" IS '跨端背景素材表，保存服务端背景库的素材元数据与生命周期状态';

CREATE UNIQUE INDEX "uq_backdrop_assets_owner_sha" ON "omni"."backdrop_assets" USING btree (
  "owner_user_id",
  "sha256"
);
CREATE INDEX "idx_backdrop_assets_owner_updated" ON "omni"."backdrop_assets" USING btree (
  "owner_user_id",
  "updated_at" DESC
);

CREATE TABLE "omni"."config_entries" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "config_key" varchar(160) NOT NULL,
  "config_value" text,
  "value_type" varchar(32) NOT NULL DEFAULT 'STRING'::character varying,
  "category" varchar(80) NOT NULL,
  "refresh_scope" varchar(32) NOT NULL DEFAULT 'HOT'::character varying,
  "description" text,
  "is_sensitive" bool NOT NULL DEFAULT false,
  "updated_by" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."config_entries"."id" IS '配置唯一标识，主键';
COMMENT ON COLUMN "omni"."config_entries"."config_key" IS '配置键，唯一';
COMMENT ON COLUMN "omni"."config_entries"."config_value" IS '配置值';
COMMENT ON COLUMN "omni"."config_entries"."value_type" IS '配置值类型：STRING / NUMBER / BOOLEAN / JSON';
COMMENT ON COLUMN "omni"."config_entries"."category" IS '配置分类';
COMMENT ON COLUMN "omni"."config_entries"."refresh_scope" IS '刷新范围：HOT / NEXT_TASK / RESTART_REQUIRED';
COMMENT ON COLUMN "omni"."config_entries"."description" IS '说明描述';
COMMENT ON COLUMN "omni"."config_entries"."is_sensitive" IS '是否为敏感配置';
COMMENT ON COLUMN "omni"."config_entries"."updated_by" IS '最后更新用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."config_entries"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."config_entries"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."config_entries"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."config_entries" IS '配置中心当前值表，保存可热更新或需重启的系统配置';

CREATE TABLE "omni"."config_histories" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "config_key" varchar(160) NOT NULL,
  "old_value" text,
  "new_value" text,
  "changed_by" uuid,
  "change_reason" varchar(500),
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."config_histories"."id" IS '历史记录唯一标识，主键';
COMMENT ON COLUMN "omni"."config_histories"."config_key" IS '配置键';
COMMENT ON COLUMN "omni"."config_histories"."old_value" IS '变更前配置值';
COMMENT ON COLUMN "omni"."config_histories"."new_value" IS '变更后配置值';
COMMENT ON COLUMN "omni"."config_histories"."changed_by" IS '变更用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."config_histories"."change_reason" IS '变更原因';
COMMENT ON COLUMN "omni"."config_histories"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."config_histories" IS '配置变更历史表，记录配置修改前后值和操作人';

CREATE TABLE "omni"."content_assets" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "resource_type" varchar(32) NOT NULL,
  "resource_id" uuid NOT NULL,
  "asset_type" varchar(32) NOT NULL,
  "file_node_id" uuid,
  "external_url" text,
  "provider" varchar(64),
  "language" varchar(16),
  "width" int4,
  "height" int4,
  "sort_order" int4 NOT NULL DEFAULT 0,
  "is_primary" bool NOT NULL DEFAULT false,
  "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."content_assets"."id" IS '资源唯一标识，主键';
COMMENT ON COLUMN "omni"."content_assets"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."content_assets"."resource_type" IS '业务资源类型：VIDEO_ITEM / TV_SERIES / TV_SEASON / MUSIC_TRACK / MUSIC_ALBUM / MUSIC_ARTIST / READER_ITEM / READER_COLLECTION';
COMMENT ON COLUMN "omni"."content_assets"."resource_id" IS '业务资源ID，由应用层关联对应业务表';
COMMENT ON COLUMN "omni"."content_assets"."asset_type" IS '资源类型：POSTER / BACKDROP / THUMBNAIL / LOGO / BANNER / COVER / ARTIST_PHOTO / SCREENSHOT / NFO / LYRICS / SUBTITLE / OTHER';
COMMENT ON COLUMN "omni"."content_assets"."file_node_id" IS '文件节点ID，表示已入库到文件管理的资源，关联file_nodes';
COMMENT ON COLUMN "omni"."content_assets"."external_url" IS '外部资源地址，常用于未下载或候选资源';
COMMENT ON COLUMN "omni"."content_assets"."provider" IS '资源来源提供方：TMDB / Bangumi / MusicBrainz';
COMMENT ON COLUMN "omni"."content_assets"."language" IS '资源语言';
COMMENT ON COLUMN "omni"."content_assets"."width" IS '图片或视频资源宽度';
COMMENT ON COLUMN "omni"."content_assets"."height" IS '图片或视频资源高度';
COMMENT ON COLUMN "omni"."content_assets"."sort_order" IS '展示排序值';
COMMENT ON COLUMN "omni"."content_assets"."is_primary" IS '是否为该资源类型的主资源';
COMMENT ON COLUMN "omni"."content_assets"."metadata" IS '资源扩展元数据，JSONB格式';
COMMENT ON COLUMN "omni"."content_assets"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."content_assets"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."content_assets"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."content_assets" IS '通用内容资源表，保存影视、音乐、阅读等模块的海报、封面、背景图、歌词、字幕和NFO等资源索引';

CREATE TABLE "omni"."download_offline_tasks" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "source_uri" text NOT NULL,
  "target_parent_id" uuid,
  "space_type" varchar(16) NOT NULL DEFAULT 'PERSONAL'::character varying,
  "task_id" uuid,
  "aria2_gid" varchar(32),
  "file_name" varchar(255),
  "total_bytes" int8 NOT NULL DEFAULT 0,
  "completed_bytes" int8 NOT NULL DEFAULT 0,
  "download_speed_bytes" int8 NOT NULL DEFAULT 0,
  "error_summary" text,
  "completed_file_id" uuid,
  "completed_at" timestamptz(6),
  "status" varchar(32) NOT NULL DEFAULT 'QUEUED'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."download_offline_tasks"."id" IS '任务唯一标识，主键';
COMMENT ON COLUMN "omni"."download_offline_tasks"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."download_offline_tasks"."source_uri" IS '离线下载源地址';
COMMENT ON COLUMN "omni"."download_offline_tasks"."target_parent_id" IS '目标父级文件夹ID，关联file_nodes';
COMMENT ON COLUMN "omni"."download_offline_tasks"."space_type" IS '目标空间：PERSONAL 或 SHARED';
COMMENT ON COLUMN "omni"."download_offline_tasks"."task_id" IS '系统任务ID，关联sys_tasks';
COMMENT ON COLUMN "omni"."download_offline_tasks"."aria2_gid" IS 'aria2 RPC任务GID';
COMMENT ON COLUMN "omni"."download_offline_tasks"."file_name" IS '下载结果显示名称';
COMMENT ON COLUMN "omni"."download_offline_tasks"."total_bytes" IS '总字节数';
COMMENT ON COLUMN "omni"."download_offline_tasks"."completed_bytes" IS '已完成字节数';
COMMENT ON COLUMN "omni"."download_offline_tasks"."download_speed_bytes" IS '当前下载速度（字节/秒）';
COMMENT ON COLUMN "omni"."download_offline_tasks"."error_summary" IS '失败摘要';
COMMENT ON COLUMN "omni"."download_offline_tasks"."completed_file_id" IS '导入完成后的文件或文件夹节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."download_offline_tasks"."completed_at" IS '完成时间';
COMMENT ON COLUMN "omni"."download_offline_tasks"."status" IS '状态';
COMMENT ON COLUMN "omni"."download_offline_tasks"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."download_offline_tasks"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."download_offline_tasks"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."download_offline_tasks" IS '离线下载任务表，记录远程资源下载到文件空间的任务';

CREATE TABLE "omni"."file_access_records" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid NOT NULL,
  "last_accessed_at" timestamptz(6) NOT NULL DEFAULT now(),
  "access_count" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."file_access_records"."id" IS '记录唯一标识，主键';
COMMENT ON COLUMN "omni"."file_access_records"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_access_records"."file_node_id" IS '文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."file_access_records"."last_accessed_at" IS '最后访问时间';
COMMENT ON COLUMN "omni"."file_access_records"."access_count" IS '累计访问次数';
COMMENT ON COLUMN "omni"."file_access_records"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_access_records"."updated_at" IS '更新时间';
COMMENT ON TABLE "omni"."file_access_records" IS '文件访问记录表，保存用户最近打开或下载文件的时间';

CREATE TABLE "omni"."file_favorites" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."file_favorites"."id" IS '收藏唯一标识，主键';
COMMENT ON COLUMN "omni"."file_favorites"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_favorites"."file_node_id" IS '文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."file_favorites"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."file_favorites" IS '文件收藏表，保存用户星标收藏的文件节点';

CREATE TABLE "omni"."file_move_records" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "file_node_id" uuid NOT NULL,
  "operator_id" uuid NOT NULL,
  "from_space" varchar(20) NOT NULL,
  "to_space" varchar(20) NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."file_move_records"."file_node_id" IS '文件节点ID';
COMMENT ON COLUMN "omni"."file_move_records"."operator_id" IS '操作人用户ID';
COMMENT ON COLUMN "omni"."file_move_records"."from_space" IS '源空间：PERSONAL / SHARED';
COMMENT ON COLUMN "omni"."file_move_records"."to_space" IS '目标空间：PERSONAL / SHARED';
COMMENT ON TABLE "omni"."file_move_records" IS '文件跨空间移动记录表，审计用';

CREATE TABLE "omni"."file_node_permissions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "file_node_id" uuid NOT NULL,
  "grantee_user_id" uuid,
  "allow_view" bool NOT NULL DEFAULT true,
  "allow_download" bool NOT NULL DEFAULT true,
  "allow_share" bool NOT NULL DEFAULT false,
  "allow_edit" bool NOT NULL DEFAULT false,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."file_node_permissions"."id" IS '权限记录唯一标识';
COMMENT ON COLUMN "omni"."file_node_permissions"."file_node_id" IS '文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."file_node_permissions"."grantee_user_id" IS '被授权用户ID，NULL表示全局默认权限';
COMMENT ON COLUMN "omni"."file_node_permissions"."allow_view" IS '是否允许查看';
COMMENT ON COLUMN "omni"."file_node_permissions"."allow_download" IS '是否允许下载';
COMMENT ON COLUMN "omni"."file_node_permissions"."allow_share" IS '是否允许再分享';
COMMENT ON COLUMN "omni"."file_node_permissions"."allow_edit" IS '是否允许编辑（重命名/移动/删除）';
COMMENT ON COLUMN "omni"."file_node_permissions"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_node_permissions"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."file_node_permissions"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."file_node_permissions" IS '文件权限表，保存文件的共享权限配置';

CREATE TABLE "omni"."file_nodes" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "parent_id" uuid,
  "node_type" varchar(16) NOT NULL,
  "name" varchar(255) NOT NULL,
  "normalized_path" text NOT NULL,
  "mime_type" varchar(160),
  "category" varchar(32),
  "size_bytes" int8 NOT NULL DEFAULT 0,
  "current_object_id" uuid,
  "source_type" varchar(32) NOT NULL DEFAULT 'LOCAL'::character varying,
  "is_deleted" bool NOT NULL DEFAULT false,
  "deleted_at" timestamptz(6),
  "deleted_by" uuid,
  "purge_state" varchar(24) NOT NULL DEFAULT 'NONE',
  "purge_task_id" uuid,
  "purge_requested_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "shared" bool NOT NULL DEFAULT false,
  "shared_at" timestamptz(6),
  "space_type" varchar(20) NOT NULL DEFAULT 'PERSONAL'::character varying,
  "uploaded_by" uuid
)
;
COMMENT ON COLUMN "omni"."file_nodes"."id" IS '节点唯一标识，主键';
COMMENT ON COLUMN "omni"."file_nodes"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_nodes"."parent_id" IS '父级节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."file_nodes"."node_type" IS '节点类型：FILE / FOLDER';
COMMENT ON COLUMN "omni"."file_nodes"."name" IS '名称';
COMMENT ON COLUMN "omni"."file_nodes"."normalized_path" IS '规范化路径';
COMMENT ON COLUMN "omni"."file_nodes"."mime_type" IS 'MIME类型';
COMMENT ON COLUMN "omni"."file_nodes"."category" IS '业务分类：image/video/audio/document/novel/comic/archive/other，仅FILE写入';
COMMENT ON COLUMN "omni"."file_nodes"."size_bytes" IS '大小字节数';
COMMENT ON COLUMN "omni"."file_nodes"."current_object_id" IS '当前文件对象ID，关联file_objects';
COMMENT ON COLUMN "omni"."file_nodes"."source_type" IS '来源类型：LOCAL / LOCAL_FILESYSTEM / EXTERNAL / DERIVED / RCLONE / SHARE';
COMMENT ON COLUMN "omni"."file_nodes"."is_deleted" IS '是否已删除（软删除）';
COMMENT ON COLUMN "omni"."file_nodes"."deleted_at" IS '删除时间';
COMMENT ON COLUMN "omni"."file_nodes"."deleted_by" IS '删除用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_nodes"."purge_state" IS '永久删除状态：NONE / QUEUED / RUNNING / RETRY_WAIT / FAILED';
COMMENT ON COLUMN "omni"."file_nodes"."purge_task_id" IS '当前永久删除任务ID';
COMMENT ON COLUMN "omni"."file_nodes"."purge_requested_at" IS '永久删除请求时间';
COMMENT ON COLUMN "omni"."file_nodes"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_nodes"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."file_nodes"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."file_nodes"."space_type" IS '空间类型：PERSONAL / SHARED';
COMMENT ON COLUMN "omni"."file_nodes"."uploaded_by" IS '上传者用户ID，仅共享空间文件使用，关联auth_users';
COMMENT ON TABLE "omni"."file_nodes" IS '文件节点表，维护用户文件夹和文件的树形目录';

CREATE TABLE "omni"."file_objects" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "bucket_name" varchar(80) NOT NULL,
  "object_key" text NOT NULL,
  "sha256" varchar(64),
  "size_bytes" int8 NOT NULL,
  "mime_type" varchar(160),
  "storage_class" varchar(32) NOT NULL DEFAULT 'STANDARD'::character varying,
  "encryption_status" varchar(32) NOT NULL DEFAULT 'SERVER_SIDE'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."file_objects"."id" IS '对象唯一标识，主键';
COMMENT ON COLUMN "omni"."file_objects"."bucket_name" IS '对象存储桶名称';
COMMENT ON COLUMN "omni"."file_objects"."object_key" IS '对象存储键';
COMMENT ON COLUMN "omni"."file_objects"."sha256" IS '文件SHA-256摘要';
COMMENT ON COLUMN "omni"."file_objects"."size_bytes" IS '大小字节数';
COMMENT ON COLUMN "omni"."file_objects"."mime_type" IS 'MIME类型';
COMMENT ON COLUMN "omni"."file_objects"."storage_class" IS '对象存储等级';
COMMENT ON COLUMN "omni"."file_objects"."encryption_status" IS '加密状态';
COMMENT ON COLUMN "omni"."file_objects"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."file_objects" IS '文件对象表，记录MinIO对象存储位置、摘要和大小';

CREATE TABLE "omni"."storage_locations" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "name" varchar(160) NOT NULL,
  "provider_type" varchar(32) NOT NULL,
  "management_mode" varchar(24) NOT NULL,
  "mount_key" varchar(80) NOT NULL,
  "relative_root" text NOT NULL DEFAULT '.',
  "scope_type" varchar(24) NOT NULL,
  "scope_id" uuid,
  "enabled" bool NOT NULL DEFAULT false,
  "created_by" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "chk_storage_locations_provider" CHECK (provider_type = 'LOCAL_FILESYSTEM'),
  CONSTRAINT "chk_storage_locations_mode" CHECK (management_mode = 'READ_ONLY'),
  CONSTRAINT "chk_storage_locations_scope" CHECK (scope_type IN ('SYSTEM', 'USER')),
  CONSTRAINT "chk_storage_locations_scope_id" CHECK (
    (scope_type = 'SYSTEM' AND scope_id IS NULL) OR (scope_type = 'USER' AND scope_id IS NOT NULL)
  ),
  CONSTRAINT "uk_storage_locations_mount_root_scope" UNIQUE NULLS NOT DISTINCT (
    mount_key, relative_root, scope_type, scope_id
  )
);
COMMENT ON COLUMN "omni"."storage_locations"."mount_key" IS '部署配置中的挂载键，不保存宿主机绝对路径';
COMMENT ON COLUMN "omni"."storage_locations"."relative_root" IS '挂载点内部相对根目录';
COMMENT ON COLUMN "omni"."storage_locations"."scope_type" IS '作用域类型：SYSTEM / USER';
COMMENT ON TABLE "omni"."storage_locations" IS '受部署白名单约束的本地只读存储位置';

CREATE TABLE "omni"."file_content_refs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid NOT NULL,
  "storage_location_id" uuid NOT NULL,
  "relative_path" text NOT NULL,
  "provider_etag" varchar(160),
  "size_bytes" int8 NOT NULL DEFAULT 0,
  "modified_at" timestamptz(6),
  "availability_status" varchar(24) NOT NULL DEFAULT 'AVAILABLE',
  "last_seen_at" timestamptz(6) NOT NULL DEFAULT now(),
  "last_seen_scan_run_id" uuid,
  "missing_since" timestamptz(6),
  "missing_confirmations" int4 NOT NULL DEFAULT 0,
  "last_availability_run_id" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "chk_file_content_refs_size" CHECK (size_bytes >= 0),
  CONSTRAINT "chk_file_content_refs_status" CHECK (
    availability_status IN ('AVAILABLE', 'MISSING_PENDING', 'MISSING', 'CHANGED', 'BLOCKED', 'UNAVAILABLE')
  ),
  CONSTRAINT "chk_file_content_refs_missing_confirmations" CHECK (missing_confirmations >= 0),
  CONSTRAINT "uk_file_content_refs_node" UNIQUE (file_node_id),
  CONSTRAINT "uk_file_content_refs_location_path_owner" UNIQUE (
    storage_location_id, relative_path, owner_user_id
  )
);
CREATE INDEX "idx_file_content_refs_location_owner_path" ON "omni"."file_content_refs" (
  "storage_location_id", "owner_user_id", "relative_path"
);
COMMENT ON COLUMN "omni"."file_content_refs"."relative_path" IS '存储位置根目录内的规范化相对路径';
COMMENT ON COLUMN "omni"."file_content_refs"."availability_status" IS '内容可用状态：AVAILABLE / MISSING_PENDING / MISSING / CHANGED / BLOCKED / UNAVAILABLE';
COMMENT ON COLUMN "omni"."file_content_refs"."last_seen_scan_run_id" IS '最近一次确认文件存在的媒体发现运行ID';
COMMENT ON COLUMN "omni"."file_content_refs"."missing_since" IS '首次在完整成功扫描中未发现的时间';
COMMENT ON COLUMN "omni"."file_content_refs"."missing_confirmations" IS '连续完整成功扫描未发现次数';
COMMENT ON TABLE "omni"."file_content_refs" IS '文件节点到非托管原文件的只读内容引用';

CREATE TABLE "omni"."file_ingress_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "source_type" varchar(24) NOT NULL,
  "source_task_id" uuid,
  "upload_session_id" uuid,
  "quarantine_bucket" varchar(80) NOT NULL,
  "quarantine_object_key" text NOT NULL,
  "target_bucket" varchar(80) NOT NULL,
  "target_object_key" text NOT NULL,
  "target_parent_id" uuid,
  "target_name" varchar(255) NOT NULL,
  "size_bytes" int8 NOT NULL,
  "sha256" varchar(64),
  "mime_type" varchar(160),
  "status" varchar(24) NOT NULL DEFAULT 'PENDING_SCAN',
  "scan_attempt_count" int4 NOT NULL DEFAULT 0,
  "next_scan_at" timestamptz(6),
  "threat_name" varchar(255),
  "error_code" varchar(64),
  "result_file_node_id" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON TABLE "omni"."file_ingress_items" IS '文件安全入库状态表，记录隔离、扫描和发布结果';
COMMENT ON COLUMN "omni"."file_ingress_items"."id" IS '安全入库记录唯一标识，主键';
COMMENT ON COLUMN "omni"."file_ingress_items"."owner_user_id" IS '文件所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_ingress_items"."source_type" IS '来源类型：UPLOAD / EXTERNAL / OFFLINE / SYSTEM';
COMMENT ON COLUMN "omni"."file_ingress_items"."source_task_id" IS '来源异步任务ID，无任务来源时为空';
COMMENT ON COLUMN "omni"."file_ingress_items"."upload_session_id" IS '上传会话ID，非上传来源时为空';
COMMENT ON COLUMN "omni"."file_ingress_items"."quarantine_bucket" IS '扫描前对象所在的隔离存储桶';
COMMENT ON COLUMN "omni"."file_ingress_items"."status" IS '状态：PENDING_SCAN / SCANNING / CLEAN / AVAILABLE / REJECTED / FAILED';
COMMENT ON COLUMN "omni"."file_ingress_items"."quarantine_object_key" IS '隔离桶中的对象键';
COMMENT ON COLUMN "omni"."file_ingress_items"."target_bucket" IS '扫描通过后发布到的目标存储桶';
COMMENT ON COLUMN "omni"."file_ingress_items"."target_object_key" IS '扫描通过后发布到的目标对象键';
COMMENT ON COLUMN "omni"."file_ingress_items"."target_parent_id" IS '目标父文件节点ID，根目录时为空';
COMMENT ON COLUMN "omni"."file_ingress_items"."target_name" IS '发布后的文件节点名称';
COMMENT ON COLUMN "omni"."file_ingress_items"."size_bytes" IS '待入库文件字节数';
COMMENT ON COLUMN "omni"."file_ingress_items"."sha256" IS '服务端扫描流计算的SHA-256摘要';
COMMENT ON COLUMN "omni"."file_ingress_items"."mime_type" IS '基于内容识别的MIME类型';
COMMENT ON COLUMN "omni"."file_ingress_items"."scan_attempt_count" IS '安全扫描尝试次数';
COMMENT ON COLUMN "omni"."file_ingress_items"."next_scan_at" IS '扫描失败后允许重试的时间';
COMMENT ON COLUMN "omni"."file_ingress_items"."threat_name" IS '确认检出威胁时的有界威胁摘要';
COMMENT ON COLUMN "omni"."file_ingress_items"."error_code" IS '扫描或发布失败的稳定错误码';
COMMENT ON COLUMN "omni"."file_ingress_items"."result_file_node_id" IS '发布成功后的文件节点ID';
COMMENT ON COLUMN "omni"."file_ingress_items"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_ingress_items"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."file_ingress_items"."version" IS '乐观锁版本号';

CREATE TABLE "omni"."file_purge_entries" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "task_id" uuid NOT NULL,
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid,
  "object_id" uuid,
  "bucket_name" varchar(80) NOT NULL,
  "object_key" text NOT NULL,
  "minio_version_id" varchar(255),
  "entry_type" varchar(32) NOT NULL,
  "status" varchar(24) NOT NULL DEFAULT 'PENDING',
  "attempt_count" int4 NOT NULL DEFAULT 0,
  "last_error_code" varchar(64),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON TABLE "omni"."file_purge_entries" IS '文件永久删除对象清单，支持逐对象幂等删除和失败重试';
COMMENT ON COLUMN "omni"."file_purge_entries"."task_id" IS '所属永久删除任务ID';
COMMENT ON COLUMN "omni"."file_purge_entries"."entry_type" IS '条目类型：SOURCE / VERSION / DERIVED / LEGACY';
COMMENT ON COLUMN "omni"."file_purge_entries"."status" IS '删除状态：PENDING / DELETED / NOT_FOUND / FAILED';

CREATE TABLE "omni"."file_share_recipients" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "share_link_id" uuid NOT NULL,
  "recipient_user_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."file_share_recipients"."id" IS '记录唯一标识，主键';
COMMENT ON COLUMN "omni"."file_share_recipients"."share_link_id" IS '分享链接ID，关联share_links';
COMMENT ON COLUMN "omni"."file_share_recipients"."recipient_user_id" IS '接收用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_share_recipients"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."file_share_recipients" IS '文件分享接收人表，保存定向分享可见用户';

CREATE TABLE "omni"."file_upload_parts" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "upload_session_id" uuid NOT NULL,
  "owner_user_id" uuid NOT NULL,
  "part_number" int4 NOT NULL,
  "size_bytes" int8 NOT NULL,
  "etag" varchar(160),
  "status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."file_upload_parts"."id" IS '分片唯一标识，主键';
COMMENT ON COLUMN "omni"."file_upload_parts"."upload_session_id" IS '上传会话ID，关联file_upload_sessions';
COMMENT ON COLUMN "omni"."file_upload_parts"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_upload_parts"."part_number" IS '分片序号，从1开始';
COMMENT ON COLUMN "omni"."file_upload_parts"."size_bytes" IS '分片大小字节数';
COMMENT ON COLUMN "omni"."file_upload_parts"."etag" IS '对象存储返回的分片ETag';
COMMENT ON COLUMN "omni"."file_upload_parts"."status" IS '分片状态：PENDING / COMPLETED / FAILED';
COMMENT ON COLUMN "omni"."file_upload_parts"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_upload_parts"."updated_at" IS '更新时间';
COMMENT ON TABLE "omni"."file_upload_parts" IS '文件上传分片表，记录标准S3 Multipart Upload的分片状态和ETag';

CREATE TABLE "omni"."file_upload_sessions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "target_parent_id" uuid,
  "file_name" varchar(255) NOT NULL,
  "total_size_bytes" int8 NOT NULL,
  "part_size_bytes" int4 NOT NULL DEFAULT 0,
  "total_parts" int4 NOT NULL DEFAULT 1,
  "uploaded_parts" int4 NOT NULL DEFAULT 0,
  "mime_type" varchar(160),
  "sha256" varchar(64),
  "status" varchar(32) NOT NULL DEFAULT 'CREATED'::character varying,
  "upload_id" varchar(255) NOT NULL,
  "target_bucket" varchar(80) NOT NULL,
  "target_object_key" text NOT NULL,
  "ingress_item_id" uuid,
  "result_file_node_id" uuid,
  "result_object_id" uuid,
  "completion_task_id" uuid,
  "quota_reservation_id" uuid,
  "expires_at" timestamptz(6) NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "space_type" varchar(20) NOT NULL DEFAULT 'PERSONAL'::character varying
)
;
COMMENT ON COLUMN "omni"."file_upload_sessions"."id" IS '会话唯一标识，主键';
COMMENT ON COLUMN "omni"."file_upload_sessions"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_upload_sessions"."target_parent_id" IS '目标父级文件夹ID，关联file_nodes';
COMMENT ON COLUMN "omni"."file_upload_sessions"."file_name" IS '上传文件名';
COMMENT ON COLUMN "omni"."file_upload_sessions"."total_size_bytes" IS '上传总大小字节数';
COMMENT ON COLUMN "omni"."file_upload_sessions"."part_size_bytes" IS '分片大小字节数';
COMMENT ON COLUMN "omni"."file_upload_sessions"."total_parts" IS '总分片数';
COMMENT ON COLUMN "omni"."file_upload_sessions"."uploaded_parts" IS '已上传分片数';
COMMENT ON COLUMN "omni"."file_upload_sessions"."mime_type" IS 'MIME类型';
COMMENT ON COLUMN "omni"."file_upload_sessions"."sha256" IS '文件SHA-256摘要';
COMMENT ON COLUMN "omni"."file_upload_sessions"."status" IS '状态：CREATED / UPLOADING / FINALIZING / SCANNING / COMPLETED / REJECTED / FAILED / CANCELLED / EXPIRED';
COMMENT ON COLUMN "omni"."file_upload_sessions"."upload_id" IS '对象存储分片上传ID';
COMMENT ON COLUMN "omni"."file_upload_sessions"."target_bucket" IS '目标对象存储桶';
COMMENT ON COLUMN "omni"."file_upload_sessions"."target_object_key" IS '目标对象存储键';
COMMENT ON COLUMN "omni"."file_upload_sessions"."ingress_item_id" IS '文件安全入库记录ID';
COMMENT ON COLUMN "omni"."file_upload_sessions"."result_file_node_id" IS '完成后生成的文件节点ID';
COMMENT ON COLUMN "omni"."file_upload_sessions"."result_object_id" IS '完成后生成的文件对象ID';
COMMENT ON COLUMN "omni"."file_upload_sessions"."completion_task_id" IS '异步完成任务ID，未启用异步完成时为空';
COMMENT ON COLUMN "omni"."file_upload_sessions"."quota_reservation_id" IS '上传会话占用的存储配额预留ID';
COMMENT ON COLUMN "omni"."file_upload_sessions"."expires_at" IS '过期时间';
COMMENT ON COLUMN "omni"."file_upload_sessions"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_upload_sessions"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."file_upload_sessions"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."file_upload_sessions"."space_type" IS '目标空间类型：PERSONAL / SHARED';
COMMENT ON TABLE "omni"."file_upload_sessions" IS '文件上传会话表，记录预签名上传过程和目标对象';

CREATE TABLE "omni"."file_versions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "file_node_id" uuid NOT NULL,
  "object_id" uuid NOT NULL,
  "version_no" int4 NOT NULL,
  "minio_version_id" varchar(255),
  "change_type" varchar(32) NOT NULL,
  "remark" varchar(500),
  "created_by" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."file_versions"."id" IS '版本唯一标识，主键';
COMMENT ON COLUMN "omni"."file_versions"."remark" IS '版本备注';
COMMENT ON COLUMN "omni"."file_versions"."file_node_id" IS '文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."file_versions"."object_id" IS '文件对象ID，关联file_objects';
COMMENT ON COLUMN "omni"."file_versions"."version_no" IS '文件版本序号';
COMMENT ON COLUMN "omni"."file_versions"."minio_version_id" IS 'MinIO对象版本ID';
COMMENT ON COLUMN "omni"."file_versions"."change_type" IS '版本变更类型：UPLOAD / EDIT / RESTORE / DERIVED';
COMMENT ON COLUMN "omni"."file_versions"."created_by" IS '创建用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_versions"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."file_versions" IS '文件版本表，记录文件节点的对象版本历史';

CREATE TABLE "omni"."integration_accounts" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "integration_type" varchar(64) NOT NULL,
  "provider" varchar(64) NOT NULL,
  "external_user_id" varchar(255),
  "display_name" varchar(160),
  "avatar_url" varchar(1024),
  "encrypted_credentials" text NOT NULL,
  "credential_key_version" int4 NOT NULL DEFAULT 1,
  "status" varchar(32) NOT NULL DEFAULT 'ACTIVE'::character varying,
  "last_verified_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."integration_accounts"."owner_user_id" IS '所属用户ID，由应用层维护关联';
COMMENT ON COLUMN "omni"."integration_accounts"."integration_type" IS '外部集成业务类型';
COMMENT ON COLUMN "omni"."integration_accounts"."provider" IS '外部服务提供者';
COMMENT ON COLUMN "omni"."integration_accounts"."encrypted_credentials" IS 'AES-GCM加密后的凭据';
COMMENT ON COLUMN "omni"."integration_accounts"."credential_key_version" IS '凭据加密密钥版本';
COMMENT ON TABLE "omni"."integration_accounts" IS '通用外部集成账号表';

CREATE TABLE "omni"."media_movies" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "library_source_id" uuid,
  "tmdb_id" int4,
  "imdb_id" varchar(64),
  "title" varchar(500) NOT NULL,
  "original_title" varchar(500),
  "original_language" varchar(32),
  "release_date" date,
  "overview" text,
  "tagline" varchar(1000),
  "runtime_seconds" int4,
  "rating" float8,
  "vote_count" int4 NOT NULL DEFAULT 0,
  "popularity" float8,
  "content_rating" varchar(64),
  "genres" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "cast_members" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "crew_members" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "studios" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "countries" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "poster_file_id" uuid,
  "backdrop_file_id" uuid,
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "metadata_status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "last_scraped_at" timestamptz(6),
  "is_favorite" bool NOT NULL DEFAULT false,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_movies"."id" IS '电影唯一标识，主键';
COMMENT ON COLUMN "omni"."media_movies"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_movies"."library_source_id" IS '本地媒体库来源ID；托管上传内容为空';
COMMENT ON COLUMN "omni"."media_movies"."tmdb_id" IS 'TMDB电影ID';
COMMENT ON COLUMN "omni"."media_movies"."imdb_id" IS 'IMDb ID';
COMMENT ON COLUMN "omni"."media_movies"."title" IS '电影标题';
COMMENT ON COLUMN "omni"."media_movies"."original_title" IS '原始标题';
COMMENT ON COLUMN "omni"."media_movies"."original_language" IS '原始语言';
COMMENT ON COLUMN "omni"."media_movies"."release_date" IS '发行日期';
COMMENT ON COLUMN "omni"."media_movies"."overview" IS '简介';
COMMENT ON COLUMN "omni"."media_movies"."tagline" IS '宣传语或副标题';
COMMENT ON COLUMN "omni"."media_movies"."runtime_seconds" IS '时长（秒）';
COMMENT ON COLUMN "omni"."media_movies"."rating" IS '评分（0~10）';
COMMENT ON COLUMN "omni"."media_movies"."vote_count" IS '评分人数';
COMMENT ON COLUMN "omni"."media_movies"."popularity" IS '热度值';
COMMENT ON COLUMN "omni"."media_movies"."content_rating" IS '内容分级';
COMMENT ON COLUMN "omni"."media_movies"."genres" IS '类型列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_movies"."cast_members" IS '演员列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_movies"."crew_members" IS '职员列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_movies"."studios" IS '制作公司或工作室列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_movies"."countries" IS '制片国家或地区列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_movies"."poster_file_id" IS '海报文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_movies"."backdrop_file_id" IS '背景图文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_movies"."external_ids" IS '外部平台ID集合，JSONB格式';
COMMENT ON COLUMN "omni"."media_movies"."provider_metadata" IS '元数据提供方返回的原始或补充信息，JSONB格式';
COMMENT ON COLUMN "omni"."media_movies"."metadata_status" IS '元数据状态：PENDING / MATCHED / MANUAL / FAILED';
COMMENT ON COLUMN "omni"."media_movies"."last_scraped_at" IS '最后刮削时间';
COMMENT ON COLUMN "omni"."media_movies"."is_favorite" IS '是否收藏';
COMMENT ON COLUMN "omni"."media_movies"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_movies"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_movies"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_movies" IS '电影逻辑实体表，承载元数据；一个电影可关联多个video_items（多版本）';

CREATE TABLE "omni"."media_nfo_exports" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "video_item_id" uuid NOT NULL,
  "export_path" text NOT NULL,
  "status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "error_summary" text,
  "exported_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_nfo_exports"."id" IS '导出记录唯一标识，主键';
COMMENT ON COLUMN "omni"."media_nfo_exports"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_nfo_exports"."video_item_id" IS '视频条目ID，关联media_video_items';
COMMENT ON COLUMN "omni"."media_nfo_exports"."export_path" IS '导出路径';
COMMENT ON COLUMN "omni"."media_nfo_exports"."status" IS '导出状态：PENDING / GENERATED / FAILED';
COMMENT ON COLUMN "omni"."media_nfo_exports"."error_summary" IS '错误摘要';
COMMENT ON COLUMN "omni"."media_nfo_exports"."exported_at" IS '导出时间';
COMMENT ON COLUMN "omni"."media_nfo_exports"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_nfo_exports"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_nfo_exports"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_nfo_exports" IS 'NFO导出记录表';

CREATE TABLE "omni"."media_playback_progresses" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "video_item_id" uuid,
  "position_seconds" int8 NOT NULL DEFAULT 0,
  "duration_seconds" int8 NOT NULL DEFAULT 0,
  "completed" bool NOT NULL DEFAULT false,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "client_updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "device_id" varchar(128) NOT NULL DEFAULT 'legacy',
  "version" int8 NOT NULL DEFAULT 0,
  "media_type" varchar(16) NOT NULL,
  "media_key" varchar(512) NOT NULL
)
;
COMMENT ON COLUMN "omni"."media_playback_progresses"."id" IS '进度唯一标识，主键';
COMMENT ON COLUMN "omni"."media_playback_progresses"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_playback_progresses"."video_item_id" IS '兼容旧版视频进度的条目ID，新记录使用 media_type 与 media_key';
COMMENT ON COLUMN "omni"."media_playback_progresses"."position_seconds" IS '当前播放位置（秒）';
COMMENT ON COLUMN "omni"."media_playback_progresses"."duration_seconds" IS '视频总时长（秒）';
COMMENT ON COLUMN "omni"."media_playback_progresses"."completed" IS '是否已看完';
COMMENT ON COLUMN "omni"."media_playback_progresses"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_playback_progresses"."client_updated_at" IS '客户端产生进度事件的时间';
COMMENT ON COLUMN "omni"."media_playback_progresses"."device_id" IS '产生进度事件的稳定设备标识';
COMMENT ON COLUMN "omni"."media_playback_progresses"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."media_playback_progresses"."media_type" IS '媒体类型：video 或 music';
COMMENT ON COLUMN "omni"."media_playback_progresses"."media_key" IS '媒体稳定键；视频使用条目ID，音乐使用类型化 playableKey';
COMMENT ON TABLE "omni"."media_playback_progresses" IS '统一媒体播放进度表，保存视频和音乐的当前播放位置';

CREATE TABLE "omni"."media_series_favorites" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "series_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_series_favorites"."id" IS '收藏唯一标识，主键';
COMMENT ON COLUMN "omni"."media_series_favorites"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_series_favorites"."series_id" IS '系列ID，关联media_tv_series';
COMMENT ON COLUMN "omni"."media_series_favorites"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_series_favorites"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_series_favorites" IS '系列收藏表，保存用户收藏的电视剧系列';

CREATE TABLE "omni"."media_subtitle_tracks" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "video_item_id" uuid NOT NULL,
  "file_node_id" uuid,
  "language" varchar(64) NOT NULL,
  "label" varchar(120) NOT NULL,
  "track_kind" varchar(32) NOT NULL DEFAULT 'SUBTITLE'::character varying,
  "stream_index" int4,
  "sort_order" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."id" IS '轨道唯一标识，主键';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."video_item_id" IS '视频条目ID，关联media_video_items';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."file_node_id" IS '字幕文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."language" IS '字幕语言';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."label" IS '字幕显示名称';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."track_kind" IS '轨道类型：SUBTITLE / CAPTION / EXTERNAL';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."stream_index" IS '内嵌字幕流索引（ffprobe），外挂字幕为NULL';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."sort_order" IS '排序值';
COMMENT ON COLUMN "omni"."media_subtitle_tracks"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."media_subtitle_tracks" IS '字幕轨道表';

CREATE TABLE "omni"."media_tv_episodes" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "series_id" uuid NOT NULL,
  "season_id" uuid,
  "season_number" int4 NOT NULL,
  "episode_number" int4 NOT NULL,
  "tmdb_id" int4,
  "title" varchar(500),
  "original_title" varchar(500),
  "air_date" date,
  "overview" text,
  "runtime_seconds" int4,
  "rating" float8,
  "vote_count" int4 NOT NULL DEFAULT 0,
  "still_file_id" uuid,
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "metadata_status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "last_scraped_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_tv_episodes"."id" IS '单集唯一标识，主键';
COMMENT ON COLUMN "omni"."media_tv_episodes"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_tv_episodes"."series_id" IS '系列ID，关联media_tv_series';
COMMENT ON COLUMN "omni"."media_tv_episodes"."season_id" IS '季ID，关联media_tv_seasons';
COMMENT ON COLUMN "omni"."media_tv_episodes"."season_number" IS '季编号';
COMMENT ON COLUMN "omni"."media_tv_episodes"."episode_number" IS '集编号';
COMMENT ON COLUMN "omni"."media_tv_episodes"."tmdb_id" IS 'TMDB单集ID';
COMMENT ON COLUMN "omni"."media_tv_episodes"."title" IS '单集标题';
COMMENT ON COLUMN "omni"."media_tv_episodes"."original_title" IS '原始标题';
COMMENT ON COLUMN "omni"."media_tv_episodes"."air_date" IS '首播日期';
COMMENT ON COLUMN "omni"."media_tv_episodes"."overview" IS '单集简介';
COMMENT ON COLUMN "omni"."media_tv_episodes"."runtime_seconds" IS '时长（秒）';
COMMENT ON COLUMN "omni"."media_tv_episodes"."rating" IS '评分（0~10）';
COMMENT ON COLUMN "omni"."media_tv_episodes"."vote_count" IS '评分人数';
COMMENT ON COLUMN "omni"."media_tv_episodes"."still_file_id" IS '剧照文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_tv_episodes"."external_ids" IS '外部平台ID集合，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_episodes"."provider_metadata" IS '元数据提供方返回的原始或补充信息，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_episodes"."metadata_status" IS '元数据状态：PENDING / MATCHED / MANUAL / FAILED';
COMMENT ON COLUMN "omni"."media_tv_episodes"."last_scraped_at" IS '最后刮削时间';
COMMENT ON COLUMN "omni"."media_tv_episodes"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_tv_episodes"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_tv_episodes"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_tv_episodes" IS '电视剧单集逻辑实体，承载元数据；一个episode可关联多个video_items（多版本）';

CREATE TABLE "omni"."media_tv_seasons" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "series_id" uuid NOT NULL,
  "season_number" int4 NOT NULL,
  "title" varchar(500) NOT NULL,
  "overview" text,
  "air_date" date,
  "episode_count" int4 NOT NULL DEFAULT 0,
  "poster_file_id" uuid,
  "rating" float8,
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_tv_seasons"."id" IS '季唯一标识，主键';
COMMENT ON COLUMN "omni"."media_tv_seasons"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_tv_seasons"."series_id" IS '系列ID，关联media_tv_series';
COMMENT ON COLUMN "omni"."media_tv_seasons"."season_number" IS '季编号';
COMMENT ON COLUMN "omni"."media_tv_seasons"."title" IS '季标题';
COMMENT ON COLUMN "omni"."media_tv_seasons"."overview" IS '季简介';
COMMENT ON COLUMN "omni"."media_tv_seasons"."air_date" IS '本季首播日期';
COMMENT ON COLUMN "omni"."media_tv_seasons"."episode_count" IS '本季集数';
COMMENT ON COLUMN "omni"."media_tv_seasons"."poster_file_id" IS '海报文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_tv_seasons"."rating" IS '本季评分（0~10）';
COMMENT ON COLUMN "omni"."media_tv_seasons"."external_ids" IS '外部平台ID集合，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_seasons"."provider_metadata" IS '元数据提供方返回的原始或补充信息，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_seasons"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_tv_seasons"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_tv_seasons"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_tv_seasons" IS '电视剧季表，保存某系列下的季信息（如第一季、第二季）';

CREATE TABLE "omni"."media_tv_series" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "library_source_id" uuid,
  "tmdb_id" int4,
  "title" varchar(500) NOT NULL,
  "sort_title" varchar(500),
  "original_title" varchar(500),
  "original_language" varchar(32),
  "first_air_date" date,
  "overview" text,
  "poster_file_id" uuid,
  "backdrop_file_id" uuid,
  "rating" float8,
  "vote_count" int4 NOT NULL DEFAULT 0,
  "popularity" float8,
  "genres" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "cast_members" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "crew_members" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "studios" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "countries" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "content_rating" varchar(64),
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "metadata_status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "scrape_locked" bool NOT NULL DEFAULT false,
  "last_scraped_at" timestamptz(6),
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "is_favorite" bool NOT NULL DEFAULT false,
  "series_type" varchar(32) NOT NULL DEFAULT 'TV'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_tv_series"."id" IS '系列唯一标识，主键';
COMMENT ON COLUMN "omni"."media_tv_series"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_tv_series"."library_source_id" IS '本地媒体库来源ID；托管上传内容为空';
COMMENT ON COLUMN "omni"."media_tv_series"."tmdb_id" IS 'TMDB系列ID';
COMMENT ON COLUMN "omni"."media_tv_series"."title" IS '系列标题';
COMMENT ON COLUMN "omni"."media_tv_series"."sort_title" IS '排序标题';
COMMENT ON COLUMN "omni"."media_tv_series"."original_title" IS '系列原始标题';
COMMENT ON COLUMN "omni"."media_tv_series"."original_language" IS '原始语言';
COMMENT ON COLUMN "omni"."media_tv_series"."first_air_date" IS '首播日期';
COMMENT ON COLUMN "omni"."media_tv_series"."overview" IS '系列简介';
COMMENT ON COLUMN "omni"."media_tv_series"."poster_file_id" IS '海报文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_tv_series"."backdrop_file_id" IS '背景图文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_tv_series"."rating" IS '评分（0~10）';
COMMENT ON COLUMN "omni"."media_tv_series"."vote_count" IS '评分人数';
COMMENT ON COLUMN "omni"."media_tv_series"."popularity" IS '热度值';
COMMENT ON COLUMN "omni"."media_tv_series"."genres" IS '类型列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_series"."cast_members" IS '演员列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_series"."crew_members" IS '职员列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_series"."studios" IS '制作公司或工作室列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_series"."countries" IS '制片国家或地区列表，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_series"."content_rating" IS '内容分级';
COMMENT ON COLUMN "omni"."media_tv_series"."external_ids" IS '外部平台ID集合，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_series"."metadata_status" IS '元数据状态：PENDING / MATCHED / MANUAL / FAILED';
COMMENT ON COLUMN "omni"."media_tv_series"."scrape_locked" IS '是否锁定刮削结果';
COMMENT ON COLUMN "omni"."media_tv_series"."last_scraped_at" IS '最后刮削时间';
COMMENT ON COLUMN "omni"."media_tv_series"."provider_metadata" IS '元数据提供方返回的原始或补充信息，JSONB格式';
COMMENT ON COLUMN "omni"."media_tv_series"."is_favorite" IS '是否收藏';
COMMENT ON COLUMN "omni"."media_tv_series"."series_type" IS '系列类型：TV（电视剧）、ANIME（动漫）、DOCUMENTARY（纪录片）';
COMMENT ON COLUMN "omni"."media_tv_series"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_tv_series"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_tv_series"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_tv_series" IS '电视剧系列表，保存系列级元数据（如《权力的游戏》整部剧）';

CREATE TABLE "omni"."media_video_collection_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "collection_id" uuid NOT NULL,
  "video_item_id" uuid NOT NULL,
  "sort_order" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_video_collection_items"."id" IS '条目唯一标识，主键';
COMMENT ON COLUMN "omni"."media_video_collection_items"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_video_collection_items"."collection_id" IS '合集ID，关联media_video_collections';
COMMENT ON COLUMN "omni"."media_video_collection_items"."video_item_id" IS '视频条目ID，关联media_video_items';
COMMENT ON COLUMN "omni"."media_video_collection_items"."sort_order" IS '排序值';
COMMENT ON COLUMN "omni"."media_video_collection_items"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_video_collection_items"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_video_collection_items" IS '视频合集条目表，保存合集与视频条目的应用层关联';

CREATE TABLE "omni"."media_video_collections" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "name" varchar(160) NOT NULL,
  "description" text,
  "cover_file_id" uuid,
  "collection_type" varchar(32) NOT NULL DEFAULT 'MANUAL'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_video_collections"."id" IS '合集唯一标识，主键';
COMMENT ON COLUMN "omni"."media_video_collections"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_video_collections"."name" IS '合集名称';
COMMENT ON COLUMN "omni"."media_video_collections"."description" IS '合集描述';
COMMENT ON COLUMN "omni"."media_video_collections"."cover_file_id" IS '封面文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_video_collections"."collection_type" IS '合集类型：MANUAL / AUTO';
COMMENT ON COLUMN "omni"."media_video_collections"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_video_collections"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_video_collections"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_video_collections" IS '视频合集表，保存手动或自动生成的媒体合集';

CREATE TABLE "omni"."media_video_favorites" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "video_item_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_video_favorites"."id" IS '收藏唯一标识，主键';
COMMENT ON COLUMN "omni"."media_video_favorites"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_video_favorites"."video_item_id" IS '视频条目ID，关联media_video_items';
COMMENT ON COLUMN "omni"."media_video_favorites"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_video_favorites"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_video_favorites" IS '视频收藏表，保存用户星标收藏的视频条目';

CREATE TABLE "omni"."video_library_sources" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "owner_user_id" uuid NOT NULL,
  "storage_location_id" uuid NOT NULL,
  "name" varchar(160) NOT NULL,
  "relative_root" text NOT NULL DEFAULT '.',
  "library_type" varchar(24) NOT NULL DEFAULT 'MOVIE',
  "import_policy" varchar(32) NOT NULL DEFAULT 'MANUAL_REVIEW',
  "visibility_type" varchar(24) NOT NULL DEFAULT 'PRIVATE',
  "enabled" bool NOT NULL DEFAULT true,
  "scan_status" varchar(24) NOT NULL DEFAULT 'NEVER_SCANNED',
  "health_status" varchar(24) NOT NULL DEFAULT 'AVAILABLE',
  "last_scanned_at" timestamptz(6),
  "last_successful_scan_at" timestamptz(6),
  "last_error_code" varchar(80),
  "last_scanned_count" int4 NOT NULL DEFAULT 0,
  "last_created_count" int4 NOT NULL DEFAULT 0,
  "last_candidate_count" int4 NOT NULL DEFAULT 0,
  "last_missing_count" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "chk_video_library_sources_status" CHECK (
    scan_status IN ('NEVER_SCANNED', 'QUEUED', 'DISCOVERING', 'READY', 'APPLYING', 'COMPLETED', 'PARTIAL', 'FAILED', 'CANCELLED')
  ),
  CONSTRAINT "chk_video_library_sources_type" CHECK (
    library_type IN ('MOVIE', 'TV_SERIES', 'ANIME', 'ROOT')
  ),
  CONSTRAINT "chk_video_library_sources_import_policy" CHECK (
    import_policy IN ('MANUAL_REVIEW', 'AUTO_ADD_CONFIDENT', 'AUTO_ADD_ALL_MATCHED')
  ),
  CONSTRAINT "chk_video_library_sources_visibility" CHECK (
    visibility_type IN ('PRIVATE', 'SELECTED_USERS', 'ALL_MEMBERS')
  ),
  CONSTRAINT "chk_video_library_sources_health" CHECK (
    health_status IN ('AVAILABLE', 'DEGRADED', 'OFFLINE', 'DISABLED')
  ),
  CONSTRAINT "uk_video_library_sources_location_root" UNIQUE (
    storage_location_id, relative_root
  )
);
CREATE INDEX "idx_video_library_sources_owner_enabled" ON "omni"."video_library_sources" (
  "owner_user_id", "enabled"
);
COMMENT ON COLUMN "omni"."video_library_sources"."relative_root" IS '存储位置内的影视库相对目录';
COMMENT ON COLUMN "omni"."video_library_sources"."library_type" IS '媒体库类型：MOVIE / TV_SERIES / ANIME / ROOT';
COMMENT ON COLUMN "omni"."video_library_sources"."import_policy" IS '候选入库策略：MANUAL_REVIEW / AUTO_ADD_CONFIDENT / AUTO_ADD_ALL_MATCHED';
COMMENT ON COLUMN "omni"."video_library_sources"."visibility_type" IS '可见性：PRIVATE / SELECTED_USERS / ALL_MEMBERS';
COMMENT ON COLUMN "omni"."video_library_sources"."scan_status" IS '发现与入库任务状态';
COMMENT ON COLUMN "omni"."video_library_sources"."health_status" IS '来源健康状态：AVAILABLE / DEGRADED / OFFLINE / DISABLED';
COMMENT ON TABLE "omni"."video_library_sources" IS '共享影视库与本地只读存储位置子目录的关联';

CREATE TABLE "omni"."media_library_access" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "library_source_id" uuid NOT NULL,
  "user_id" uuid NOT NULL,
  "created_by" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "uk_media_library_access_source_user" UNIQUE (library_source_id, user_id)
);
CREATE INDEX "idx_media_library_access_user_source" ON "omni"."media_library_access" (
  "user_id", "library_source_id"
);
CREATE INDEX "idx_media_library_access_source" ON "omni"."media_library_access" (
  "library_source_id"
);
COMMENT ON COLUMN "omni"."media_library_access"."library_source_id" IS '影视库来源ID，关联video_library_sources';
COMMENT ON COLUMN "omni"."media_library_access"."user_id" IS '被授权用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_library_access"."created_by" IS '授权操作用户ID，关联auth_users';
COMMENT ON TABLE "omni"."media_library_access" IS '影视库指定用户访问授权';

CREATE TABLE "omni"."media_scan_runs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "owner_user_id" uuid NOT NULL,
  "library_source_id" uuid NOT NULL,
  "discovery_task_id" uuid,
  "apply_task_id" uuid,
  "generation" int8 NOT NULL DEFAULT 1,
  "selection_revision" int8 NOT NULL DEFAULT 0,
  "status" varchar(24) NOT NULL DEFAULT 'QUEUED',
  "phase" varchar(24) NOT NULL DEFAULT 'DISCOVERY',
  "discovered_count" int4 NOT NULL DEFAULT 0,
  "candidate_count" int4 NOT NULL DEFAULT 0,
  "existing_count" int4 NOT NULL DEFAULT 0,
  "conflict_count" int4 NOT NULL DEFAULT 0,
  "unmatched_count" int4 NOT NULL DEFAULT 0,
  "missing_count" int4 NOT NULL DEFAULT 0,
  "selected_count" int4 NOT NULL DEFAULT 0,
  "applied_count" int4 NOT NULL DEFAULT 0,
  "failed_count" int4 NOT NULL DEFAULT 0,
  "started_at" timestamptz(6),
  "finished_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "chk_media_scan_runs_status" CHECK (
    status IN ('QUEUED', 'DISCOVERING', 'READY', 'APPLYING', 'PAUSED', 'COMPLETED', 'PARTIAL', 'FAILED', 'CANCELLED')
  ),
  CONSTRAINT "chk_media_scan_runs_phase" CHECK (phase IN ('DISCOVERY', 'APPLY')),
  CONSTRAINT "chk_media_scan_runs_counts" CHECK (
    discovered_count >= 0 AND candidate_count >= 0 AND existing_count >= 0
    AND conflict_count >= 0 AND unmatched_count >= 0 AND missing_count >= 0
    AND selected_count >= 0 AND applied_count >= 0 AND failed_count >= 0
  )
);
CREATE INDEX "idx_media_scan_runs_source_created" ON "omni"."media_scan_runs" (
  "owner_user_id", "library_source_id", "created_at" DESC
);
CREATE UNIQUE INDEX "uk_media_scan_runs_discovery_task" ON "omni"."media_scan_runs" (
  "discovery_task_id"
) WHERE discovery_task_id IS NOT NULL;
COMMENT ON TABLE "omni"."media_scan_runs" IS '本地媒体发现、审核与入库运行记录';

CREATE TABLE "omni"."media_scan_candidates" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "owner_user_id" uuid NOT NULL,
  "scan_run_id" uuid NOT NULL,
  "library_source_id" uuid NOT NULL,
  "relative_path" text NOT NULL,
  "file_name" varchar(512) NOT NULL,
  "size_bytes" int8 NOT NULL DEFAULT 0,
  "modified_at" timestamptz(6),
  "provider_etag" varchar(160),
  "candidate_type" varchar(24) NOT NULL,
  "group_id" uuid NOT NULL,
  "group_title" varchar(512) NOT NULL,
  "season_number" int4,
  "episode_number" int4,
  "match_status" varchar(24) NOT NULL DEFAULT 'NEW',
  "selected" bool NOT NULL DEFAULT false,
  "apply_status" varchar(24) NOT NULL DEFAULT 'PENDING',
  "existing_file_node_id" uuid,
  "applied_file_node_id" uuid,
  "reason_code" varchar(80),
  "error_summary" varchar(500),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "chk_media_scan_candidates_size" CHECK (size_bytes >= 0),
  CONSTRAINT "chk_media_scan_candidates_type" CHECK (candidate_type IN ('MOVIE', 'EPISODE')),
  CONSTRAINT "chk_media_scan_candidates_match" CHECK (
    match_status IN ('NEW', 'EXISTING', 'CHANGED', 'AMBIGUOUS', 'UNMATCHED', 'IGNORED')
  ),
  CONSTRAINT "chk_media_scan_candidates_apply" CHECK (
    apply_status IN ('PENDING', 'APPLYING', 'APPLIED', 'FAILED', 'SKIPPED')
  ),
  CONSTRAINT "uk_media_scan_candidates_run_path" UNIQUE (scan_run_id, relative_path)
);
CREATE INDEX "idx_media_scan_candidates_run_group" ON "omni"."media_scan_candidates" (
  "owner_user_id", "scan_run_id", "group_id", "season_number", "episode_number"
);
CREATE INDEX "idx_media_scan_candidates_run_selection" ON "omni"."media_scan_candidates" (
  "owner_user_id", "scan_run_id", "selected", "apply_status"
);
COMMENT ON COLUMN "omni"."media_scan_candidates"."relative_path" IS '存储位置根目录内安全相对路径，不含宿主机绝对路径';
COMMENT ON TABLE "omni"."media_scan_candidates" IS '本地媒体发现候选与人工审核状态';

CREATE TABLE "omni"."media_scan_batches" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  "owner_user_id" uuid NOT NULL,
  "scan_run_id" uuid NOT NULL,
  "phase" varchar(24) NOT NULL,
  "batch_no" int4 NOT NULL,
  "status" varchar(24) NOT NULL DEFAULT 'RUNNING',
  "planned_size" int4 NOT NULL,
  "item_count" int4 NOT NULL DEFAULT 0,
  "success_count" int4 NOT NULL DEFAULT 0,
  "failure_count" int4 NOT NULL DEFAULT 0,
  "payload_bytes" int8 NOT NULL DEFAULT 0,
  "duration_millis" int8 NOT NULL DEFAULT 0,
  "next_suggested_size" int4 NOT NULL,
  "retry_count" int4 NOT NULL DEFAULT 0,
  "last_error_summary" varchar(500),
  "started_at" timestamptz(6) NOT NULL DEFAULT now(),
  "finished_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "chk_media_scan_batches_phase" CHECK (phase IN ('DISCOVERY', 'APPLY', 'CLEANUP')),
  CONSTRAINT "chk_media_scan_batches_status" CHECK (status IN ('RUNNING', 'COMPLETED', 'PARTIAL', 'FAILED', 'CANCELLED')),
  CONSTRAINT "chk_media_scan_batches_counts" CHECK (
    batch_no >= 0 AND planned_size > 0 AND item_count >= 0 AND success_count >= 0
    AND failure_count >= 0 AND payload_bytes >= 0 AND duration_millis >= 0
    AND next_suggested_size > 0 AND retry_count >= 0
  ),
  CONSTRAINT "uk_media_scan_batches_run_phase_no" UNIQUE (scan_run_id, phase, batch_no)
);
CREATE INDEX "idx_media_scan_batches_run_phase" ON "omni"."media_scan_batches" (
  "owner_user_id", "scan_run_id", "phase", "batch_no"
);
COMMENT ON TABLE "omni"."media_scan_batches" IS '自适应媒体批次、检查点与恢复信息';

CREATE TABLE "omni"."media_video_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid NOT NULL,
  "library_source_id" uuid,
  "media_type" varchar(32) NOT NULL,
  "series_id" uuid,
  "season_id" uuid,
  "season_number" int4,
  "episode_number" int4,
  "runtime_seconds" int4,
  "video_codec" varchar(64),
  "audio_codec" varchar(64),
  "container_format" varchar(64),
  "resolution_width" int4,
  "resolution_height" int4,
  "metadata_status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "scrape_locked" bool NOT NULL DEFAULT false,
  "nfo_status" varchar(32) NOT NULL DEFAULT 'DISABLED'::character varying,
  "nfo_updated_at" timestamptz(6),
  "nfo_path" text,
  "movie_id" uuid,
  "episode_id" uuid,
  "version_label" varchar(128),
  "is_default_version" bool NOT NULL DEFAULT false,
  "source_video_item_id" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "duration_seconds" int4
)
;
COMMENT ON COLUMN "omni"."media_video_items"."id" IS '视频条目唯一标识，主键';
COMMENT ON COLUMN "omni"."media_video_items"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_video_items"."file_node_id" IS '文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."media_video_items"."library_source_id" IS '本地媒体库来源ID；托管上传内容为空';
COMMENT ON COLUMN "omni"."media_video_items"."media_type" IS '媒体类型：MOVIE / EPISODE';
COMMENT ON COLUMN "omni"."media_video_items"."series_id" IS '系列ID，关联media_tv_series（仅EPISODE）';
COMMENT ON COLUMN "omni"."media_video_items"."season_id" IS '季ID，关联media_tv_seasons（仅EPISODE）';
COMMENT ON COLUMN "omni"."media_video_items"."season_number" IS '季编号';
COMMENT ON COLUMN "omni"."media_video_items"."episode_number" IS '集编号';
COMMENT ON COLUMN "omni"."media_video_items"."runtime_seconds" IS '运行时长（秒）';
COMMENT ON COLUMN "omni"."media_video_items"."video_codec" IS '视频编码';
COMMENT ON COLUMN "omni"."media_video_items"."audio_codec" IS '音频编码';
COMMENT ON COLUMN "omni"."media_video_items"."container_format" IS '容器格式';
COMMENT ON COLUMN "omni"."media_video_items"."resolution_width" IS '视频宽度';
COMMENT ON COLUMN "omni"."media_video_items"."resolution_height" IS '视频高度';
COMMENT ON COLUMN "omni"."media_video_items"."metadata_status" IS '元数据状态：PENDING / MATCHED / MANUAL / FAILED';
COMMENT ON COLUMN "omni"."media_video_items"."scrape_locked" IS '是否锁定刮削结果';
COMMENT ON COLUMN "omni"."media_video_items"."nfo_status" IS 'NFO导出状态：DISABLED / PENDING / GENERATED / FAILED';
COMMENT ON COLUMN "omni"."media_video_items"."nfo_updated_at" IS 'NFO更新时间';
COMMENT ON COLUMN "omni"."media_video_items"."nfo_path" IS 'NFO导出路径';
COMMENT ON COLUMN "omni"."media_video_items"."movie_id" IS '电影逻辑实体ID，关联media_movies';
COMMENT ON COLUMN "omni"."media_video_items"."episode_id" IS '剧集逻辑实体ID，关联media_tv_episodes';
COMMENT ON COLUMN "omni"."media_video_items"."version_label" IS '版本标签（如"1080p"、"4K"）';
COMMENT ON COLUMN "omni"."media_video_items"."is_default_version" IS '是否为默认版本';
COMMENT ON COLUMN "omni"."media_video_items"."source_video_item_id" IS '转码来源视频项ID，关联media_video_items';
COMMENT ON COLUMN "omni"."media_video_items"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."media_video_items"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."media_video_items"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_video_items" IS '视频条目表，保存电影和单集的文件级记录；元数据已拆分到media_movies / media_tv_episodes';

CREATE TABLE "omni"."media_watch_history" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "video_item_id" uuid NOT NULL,
  "position_seconds" int8 NOT NULL DEFAULT 0,
  "duration_seconds" int8 NOT NULL DEFAULT 0,
  "completed" bool NOT NULL DEFAULT false,
  "played_at" timestamptz(6) NOT NULL DEFAULT now(),
  "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."media_watch_history"."id" IS '历史唯一标识，主键';
COMMENT ON COLUMN "omni"."media_watch_history"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."media_watch_history"."video_item_id" IS '视频条目ID，关联media_video_items';
COMMENT ON COLUMN "omni"."media_watch_history"."position_seconds" IS '播放位置（秒）';
COMMENT ON COLUMN "omni"."media_watch_history"."duration_seconds" IS '视频总时长（秒）';
COMMENT ON COLUMN "omni"."media_watch_history"."completed" IS '是否已看完';
COMMENT ON COLUMN "omni"."media_watch_history"."played_at" IS '播放记录时间';
COMMENT ON COLUMN "omni"."media_watch_history"."metadata" IS '扩展元数据，JSONB格式';
COMMENT ON COLUMN "omni"."media_watch_history"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."media_watch_history" IS '观看历史表，记录用户每次播放进度上报';

CREATE TABLE "omni"."music_albums" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "title" varchar(500) NOT NULL,
  "artist_name" varchar(300),
  "cover_file_id" uuid,
  "release_date" date,
  "total_duration" int4,
  "track_count" int4 NOT NULL DEFAULT 0,
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."music_albums"."id" IS '专辑唯一标识，主键';
COMMENT ON COLUMN "omni"."music_albums"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_albums"."title" IS '专辑标题';
COMMENT ON COLUMN "omni"."music_albums"."artist_name" IS '专辑艺术家名称';
COMMENT ON COLUMN "omni"."music_albums"."cover_file_id" IS '专辑封面文件ID，关联file_nodes';
COMMENT ON COLUMN "omni"."music_albums"."release_date" IS '发行日期';
COMMENT ON COLUMN "omni"."music_albums"."total_duration" IS '专辑总时长（秒）';
COMMENT ON COLUMN "omni"."music_albums"."track_count" IS '专辑曲目数量';
COMMENT ON COLUMN "omni"."music_albums"."external_ids" IS '外部平台ID集合，JSONB格式';
COMMENT ON COLUMN "omni"."music_albums"."provider_metadata" IS '元数据提供方返回的原始或补充信息，JSONB格式';
COMMENT ON COLUMN "omni"."music_albums"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."music_albums"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."music_albums"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."music_albums" IS '音乐专辑表';

CREATE TABLE "omni"."music_artists" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "name" varchar(300) NOT NULL,
  "avatar_file_id" uuid,
  "bio" text,
  "track_count" int4 NOT NULL DEFAULT 0,
  "album_count" int4 NOT NULL DEFAULT 0,
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."music_artists"."id" IS '艺术家唯一标识，主键';
COMMENT ON COLUMN "omni"."music_artists"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_artists"."name" IS '艺术家名称';
COMMENT ON COLUMN "omni"."music_artists"."avatar_file_id" IS '艺术家头像文件ID，关联file_nodes';
COMMENT ON COLUMN "omni"."music_artists"."bio" IS '艺术家简介';
COMMENT ON COLUMN "omni"."music_artists"."track_count" IS '歌曲数量';
COMMENT ON COLUMN "omni"."music_artists"."album_count" IS '专辑数量';
COMMENT ON COLUMN "omni"."music_artists"."external_ids" IS '外部平台ID集合，JSONB格式';
COMMENT ON COLUMN "omni"."music_artists"."provider_metadata" IS '元数据提供方返回的原始或补充信息，JSONB格式';
COMMENT ON COLUMN "omni"."music_artists"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."music_artists"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."music_artists"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."music_artists" IS '音乐艺术家表';

CREATE TABLE "omni"."music_favorites" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "track_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."music_favorites"."id" IS '收藏唯一标识，主键';
COMMENT ON COLUMN "omni"."music_favorites"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_favorites"."track_id" IS '歌曲ID，关联music_tracks';
COMMENT ON COLUMN "omni"."music_favorites"."created_at" IS '收藏时间';
COMMENT ON COLUMN "omni"."music_favorites"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."music_favorites" IS '音乐收藏表';

CREATE TABLE "omni"."music_play_history" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "track_id" uuid,
  "play_duration" int4,
  "played_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "playable_key" varchar(512) NOT NULL,
  "platform" varchar(32),
  "external_song_id" varchar(255),
  "title" varchar(500),
  "artist_name" varchar(300),
  "album_title" varchar(500),
  "cover_url" varchar(2048),
  "duration_seconds" int4,
  "media_mid" varchar(255)
)
;
COMMENT ON COLUMN "omni"."music_play_history"."id" IS '历史唯一标识，主键';
COMMENT ON COLUMN "omni"."music_play_history"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_play_history"."track_id" IS '歌曲ID，关联music_tracks';
COMMENT ON COLUMN "omni"."music_play_history"."play_duration" IS '实际播放时长（秒）';
COMMENT ON COLUMN "omni"."music_play_history"."played_at" IS '播放时间';
COMMENT ON COLUMN "omni"."music_play_history"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."music_play_history"."playable_key" IS '类型化可播放键，本地和在线音乐使用统一标识';
COMMENT ON COLUMN "omni"."music_play_history"."platform" IS '在线音乐平台标识，本地音乐为空';
COMMENT ON COLUMN "omni"."music_play_history"."external_song_id" IS '外部平台歌曲标识，本地音乐为空';
COMMENT ON COLUMN "omni"."music_play_history"."title" IS '播放时歌曲标题快照';
COMMENT ON COLUMN "omni"."music_play_history"."artist_name" IS '播放时歌手名称快照';
COMMENT ON COLUMN "omni"."music_play_history"."album_title" IS '播放时专辑名称快照';
COMMENT ON COLUMN "omni"."music_play_history"."cover_url" IS '播放时外部封面地址快照';
COMMENT ON COLUMN "omni"."music_play_history"."duration_seconds" IS '播放时歌曲时长快照';
COMMENT ON COLUMN "omni"."music_play_history"."media_mid" IS 'QQ音乐媒体标识快照';
COMMENT ON TABLE "omni"."music_play_history" IS '音乐播放历史表';

CREATE TABLE "omni"."music_playlist_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "playlist_id" uuid NOT NULL,
  "track_id" uuid NOT NULL,
  "sort_order" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."music_playlist_items"."id" IS '条目唯一标识，主键';
COMMENT ON COLUMN "omni"."music_playlist_items"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_playlist_items"."playlist_id" IS '播放列表ID，关联music_playlists';
COMMENT ON COLUMN "omni"."music_playlist_items"."track_id" IS '歌曲ID，关联music_tracks';
COMMENT ON COLUMN "omni"."music_playlist_items"."sort_order" IS '排序值';
COMMENT ON COLUMN "omni"."music_playlist_items"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."music_playlist_items"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."music_playlist_items" IS '音乐播放列表歌曲表';

CREATE TABLE "omni"."music_playlists" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "name" varchar(300) NOT NULL,
  "description" text,
  "playlist_type" varchar(32) NOT NULL DEFAULT 'CUSTOM'::character varying,
  "cover_file_id" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "chk_music_playlists_type" CHECK (playlist_type::text = 'CUSTOM'::text)
)
;
COMMENT ON COLUMN "omni"."music_playlists"."id" IS '播放列表唯一标识，主键';
COMMENT ON COLUMN "omni"."music_playlists"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_playlists"."name" IS '播放列表名称';
COMMENT ON COLUMN "omni"."music_playlists"."description" IS '播放列表描述';
COMMENT ON COLUMN "omni"."music_playlists"."playlist_type" IS '播放列表类型';
COMMENT ON COLUMN "omni"."music_playlists"."cover_file_id" IS '播放列表封面文件ID，关联file_nodes';
COMMENT ON COLUMN "omni"."music_playlists"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."music_playlists"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."music_playlists"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."music_playlists" IS '音乐播放列表表';

CREATE TABLE "omni"."music_scan_jobs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "status" varchar(32) NOT NULL DEFAULT 'QUEUED'::character varying,
  "scanned_files" int4 NOT NULL DEFAULT 0,
  "message" varchar(500),
  "details" jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "task_id" uuid
)
;
COMMENT ON COLUMN "omni"."music_scan_jobs"."id" IS '扫描任务唯一标识，主键';
COMMENT ON COLUMN "omni"."music_scan_jobs"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_scan_jobs"."status" IS '扫描状态';
COMMENT ON COLUMN "omni"."music_scan_jobs"."scanned_files" IS '已扫描文件数量';
COMMENT ON COLUMN "omni"."music_scan_jobs"."message" IS '扫描消息';
COMMENT ON COLUMN "omni"."music_scan_jobs"."details" IS '扫描详情JSON';
COMMENT ON COLUMN "omni"."music_scan_jobs"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."music_scan_jobs"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."music_scan_jobs"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."music_scan_jobs"."task_id" IS '系统任务ID，关联sys_tasks';
COMMENT ON TABLE "omni"."music_scan_jobs" IS '音乐库扫描任务表';

CREATE TABLE "omni"."music_tracks" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid NOT NULL,
  "album_id" uuid,
  "artist_id" uuid,
  "title" varchar(500) NOT NULL,
  "artist_name" varchar(300),
  "album_title" varchar(500),
  "genre" varchar(120),
  "track_number" int4,
  "disc_number" int4,
  "release_date" date,
  "duration_seconds" int4,
  "format" varchar(32),
  "bitrate" int4,
  "sample_rate" int4,
  "file_size" int8,
  "lyrics_raw" text,
  "lyrics_translation" text,
  "cover_file_id" uuid,
  "metadata_status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."music_tracks"."id" IS '歌曲唯一标识，主键';
COMMENT ON COLUMN "omni"."music_tracks"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."music_tracks"."file_node_id" IS '文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."music_tracks"."album_id" IS '专辑ID，关联music_albums';
COMMENT ON COLUMN "omni"."music_tracks"."artist_id" IS '艺术家ID，关联music_artists';
COMMENT ON COLUMN "omni"."music_tracks"."title" IS '歌曲标题';
COMMENT ON COLUMN "omni"."music_tracks"."artist_name" IS '艺术家名称快照';
COMMENT ON COLUMN "omni"."music_tracks"."album_title" IS '专辑名称快照';
COMMENT ON COLUMN "omni"."music_tracks"."genre" IS '音乐风格';
COMMENT ON COLUMN "omni"."music_tracks"."track_number" IS '专辑内曲目序号';
COMMENT ON COLUMN "omni"."music_tracks"."disc_number" IS '碟片序号';
COMMENT ON COLUMN "omni"."music_tracks"."release_date" IS '发行日期';
COMMENT ON COLUMN "omni"."music_tracks"."duration_seconds" IS '歌曲时长（秒）';
COMMENT ON COLUMN "omni"."music_tracks"."format" IS '音频格式';
COMMENT ON COLUMN "omni"."music_tracks"."bitrate" IS '码率';
COMMENT ON COLUMN "omni"."music_tracks"."sample_rate" IS '采样率';
COMMENT ON COLUMN "omni"."music_tracks"."file_size" IS '文件大小';
COMMENT ON COLUMN "omni"."music_tracks"."lyrics_raw" IS '歌词原文（LRC或纯文本）';
COMMENT ON COLUMN "omni"."music_tracks"."lyrics_translation" IS '歌词译文（与原文时间轴对齐的LRC或纯文本）';
COMMENT ON COLUMN "omni"."music_tracks"."cover_file_id" IS '歌曲封面文件ID，关联file_nodes';
COMMENT ON COLUMN "omni"."music_tracks"."metadata_status" IS '元数据状态：PENDING / MATCHED / MANUAL / FAILED';
COMMENT ON COLUMN "omni"."music_tracks"."external_ids" IS '外部平台ID集合，JSONB格式';
COMMENT ON COLUMN "omni"."music_tracks"."provider_metadata" IS '元数据提供方返回的原始或补充信息，JSONB格式';
COMMENT ON COLUMN "omni"."music_tracks"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."music_tracks"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."music_tracks"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."music_tracks" IS '音乐歌曲表';

CREATE TABLE "omni"."notification_messages" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "recipient_user_id" uuid NOT NULL,
  "notification_type" varchar(64) NOT NULL,
  "title" varchar(160) NOT NULL,
  "message" text,
  "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "read_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."notification_messages"."id" IS '通知唯一标识，主键';
COMMENT ON COLUMN "omni"."notification_messages"."recipient_user_id" IS '通知接收用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."notification_messages"."notification_type" IS '通知类型';
COMMENT ON COLUMN "omni"."notification_messages"."title" IS '标题';
COMMENT ON COLUMN "omni"."notification_messages"."message" IS '消息内容';
COMMENT ON COLUMN "omni"."notification_messages"."metadata" IS '扩展元数据，JSONB格式';
COMMENT ON COLUMN "omni"."notification_messages"."read_at" IS '已读时间';
COMMENT ON COLUMN "omni"."notification_messages"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."notification_messages" IS '通知消息表，保存面向用户的站内通知';

CREATE TABLE "omni"."notification_types" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "type_code" varchar(64) NOT NULL,
  "label" varchar(64) NOT NULL,
  "description" varchar(256),
  "icon" varchar(64),
  "color" varchar(16),
  "sort_order" int4 NOT NULL DEFAULT 0,
  "enabled" bool NOT NULL DEFAULT true,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."notification_types"."id" IS '主键 ID。';
COMMENT ON COLUMN "omni"."notification_types"."type_code" IS '类型标识码，如 TASK_COMPLETED。';
COMMENT ON COLUMN "omni"."notification_types"."label" IS '显示名称，如"任务完成"。';
COMMENT ON COLUMN "omni"."notification_types"."description" IS '类型说明文字。';
COMMENT ON COLUMN "omni"."notification_types"."icon" IS 'Material icon 名称。';
COMMENT ON COLUMN "omni"."notification_types"."color" IS '十六进制颜色值。';
COMMENT ON COLUMN "omni"."notification_types"."sort_order" IS '排序权重，升序。';
COMMENT ON COLUMN "omni"."notification_types"."enabled" IS '是否启用，禁用后不推送该类型通知。';
COMMENT ON COLUMN "omni"."notification_types"."created_at" IS '创建时间。';
COMMENT ON TABLE "omni"."notification_types" IS '通知类型配置表，支持动态扩展通知类型。';

CREATE TABLE "omni"."photo_album_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "album_id" uuid NOT NULL,
  "photo_id" uuid NOT NULL,
  "sort_order" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_albums" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "name" varchar(200) NOT NULL,
  "description" text,
  "cover_file_id" uuid,
  "photo_count" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_batch_tasks" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "task_type" varchar(32) NOT NULL,
  "status" varchar(32) NOT NULL DEFAULT 'QUEUED'::character varying,
  "total_items" int4 NOT NULL DEFAULT 0,
  "processed_items" int4 NOT NULL DEFAULT 0,
  "params" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "result" jsonb,
  "error_message" varchar(1000),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "task_id" uuid
)
;
COMMENT ON COLUMN "omni"."photo_batch_tasks"."task_id" IS '系统任务ID，关联sys_tasks';

CREATE TABLE "omni"."photo_edit_versions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "photo_id" uuid NOT NULL,
  "version_number" int4 NOT NULL DEFAULT 1,
  "edit_type" varchar(32) NOT NULL,
  "edit_params" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "file_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_face_clusters" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "name" varchar(200),
  "cover_face_id" uuid,
  "face_count" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_faces" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "photo_id" uuid NOT NULL,
  "owner_user_id" uuid NOT NULL,
  "bbox_x" int4 NOT NULL,
  "bbox_y" int4 NOT NULL,
  "bbox_w" int4 NOT NULL,
  "bbox_h" int4 NOT NULL,
  "embedding" bytea,
  "cluster_id" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_favorites" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "photo_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid NOT NULL,
  "title" varchar(500) NOT NULL,
  "description" text,
  "width" int4,
  "height" int4,
  "orientation" int4,
  "date_taken" timestamptz(6),
  "camera_make" varchar(120),
  "camera_model" varchar(120),
  "aperture" varchar(32),
  "shutter_speed" varchar(32),
  "iso" int4,
  "focal_length" varchar(32),
  "gps_latitude" numeric(10,7),
  "gps_longitude" numeric(10,7),
  "format" varchar(16),
  "file_size" int8 NOT NULL DEFAULT 0,
  "cover_file_id" uuid,
  "metadata_status" varchar(32) NOT NULL DEFAULT 'PENDING'::character varying,
  "provider_metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "flash" varchar(32),
  "white_balance" varchar(32),
  "metering_mode" varchar(32),
  "lens_model" varchar(120),
  "gps_location" jsonb DEFAULT '{}'::jsonb,
  "deleted_at" timestamptz(6),
  "motion_state" varchar(16),
  "motion_video_file_node_id" uuid
)
;

CREATE INDEX "idx_photo_items_owner_deleted_at" ON "omni"."photo_items" USING btree (
  "owner_user_id" ASC,
  "deleted_at" ASC
) WHERE "deleted_at" IS NOT NULL
;

CREATE TABLE "omni"."geo_dataset" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "dataset_version" varchar(64) NOT NULL,
  "source_dump_date" date NOT NULL,
  "dataset_type" varchar(32) NOT NULL DEFAULT 'cities5000'::character varying,
  "source_hash" varchar(128),
  "status" varchar(20) NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "published_at" timestamptz(6),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "pk_geo_dataset" PRIMARY KEY ("id")
)
;

CREATE UNIQUE INDEX "uk_geo_dataset_version" ON "omni"."geo_dataset" USING btree (
  "dataset_version" ASC
)
;

CREATE TABLE "omni"."geo_cities" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "dataset_id" uuid NOT NULL,
  "geoname_id" int8 NOT NULL,
  "name" varchar(200) NOT NULL,
  "name_zh" varchar(200),
  "country_code" varchar(2) NOT NULL,
  "country_name_en" varchar(200),
  "country_name_zh" varchar(200),
  "province_name_en" varchar(200),
  "province_name_zh" varchar(200),
  "latitude" numeric(10,7) NOT NULL,
  "longitude" numeric(10,7) NOT NULL,
  "population" int8 NOT NULL DEFAULT 0,
  "feature_code" varchar(10),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  CONSTRAINT "pk_geo_cities" PRIMARY KEY ("id"),
  CONSTRAINT "uk_geo_cities_dataset_geoname" UNIQUE ("dataset_id", "geoname_id")
)
;

CREATE TABLE "omni"."photo_scan_jobs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "status" varchar(32) NOT NULL DEFAULT 'QUEUED'::character varying,
  "scanned_files" int4 NOT NULL DEFAULT 0,
  "message" varchar(500),
  "details" jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "task_id" uuid
)
;
COMMENT ON COLUMN "omni"."photo_scan_jobs"."task_id" IS '系统任务ID，关联sys_tasks';

CREATE TABLE "omni"."photo_tags" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "photo_id" uuid NOT NULL,
  "tag" varchar(100) NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_content_analysis_runs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "photo_id" uuid NOT NULL,
  "content_hash" varchar(128),
  "pipeline_version" varchar(128) NOT NULL,
  "status" varchar(32) NOT NULL DEFAULT 'RUNNING'::character varying,
  "error_code" varchar(64),
  "error_message" varchar(1000),
  "started_at" timestamptz(6),
  "completed_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."photo_content_labels" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "photo_id" uuid NOT NULL,
  "run_id" uuid NOT NULL,
  "namespace" varchar(32) NOT NULL,
  "label_code" varchar(100) NOT NULL,
  "confidence" float4 NOT NULL,
  "source" varchar(64) NOT NULL,
  "model_version" varchar(128),
  "boxes" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "state" varchar(32) NOT NULL DEFAULT 'AUTO'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now()
)
;

CREATE TABLE "omni"."reader_annotations" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "start_offset" int8 NOT NULL,
  "end_offset" int8 NOT NULL,
  "highlight_text" varchar(4096),
  "note" varchar(4096),
  "color" varchar(16) NOT NULL DEFAULT '#FFEB3B'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "client_operation_id" varchar(120),
  "chapter_id" varchar(128)
)
;
COMMENT ON COLUMN "omni"."reader_annotations"."start_offset" IS '高亮起始位置，全书绝对字符偏移';
COMMENT ON COLUMN "omni"."reader_annotations"."end_offset" IS '高亮结束位置，全书绝对字符偏移';
COMMENT ON COLUMN "omni"."reader_annotations"."highlight_text" IS '高亮文本内容';
COMMENT ON COLUMN "omni"."reader_annotations"."note" IS '用户笔记';
COMMENT ON COLUMN "omni"."reader_annotations"."color" IS '高亮颜色';
COMMENT ON COLUMN "omni"."reader_annotations"."client_operation_id" IS '客户端离线创建操作号，用于重试幂等';
COMMENT ON COLUMN "omni"."reader_annotations"."chapter_id" IS '批注所属章节标识，章节内偏移与该字段共同定位正文';
COMMENT ON TABLE "omni"."reader_annotations" IS '阅读标注表，记录高亮和文本关联笔记';

CREATE TABLE "omni"."reader_bookmarks" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "char_offset" int8 NOT NULL DEFAULT 0,
  "progress_percent" numeric(8,5) NOT NULL DEFAULT 0,
  "note" varchar(1024),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "client_operation_id" varchar(120)
)
;
COMMENT ON COLUMN "omni"."reader_bookmarks"."char_offset" IS '全书绝对字符偏移';
COMMENT ON COLUMN "omni"."reader_bookmarks"."progress_percent" IS '书签位置的全书进度（0-1）';
COMMENT ON COLUMN "omni"."reader_bookmarks"."note" IS '书签备注';
COMMENT ON COLUMN "omni"."reader_bookmarks"."client_operation_id" IS '客户端离线创建操作号，用于重试幂等';
COMMENT ON TABLE "omni"."reader_bookmarks" IS '阅读书签表';

CREATE TABLE "omni"."reader_bookshelf" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now()
)
;
COMMENT ON TABLE "omni"."reader_bookshelf" IS '书架表，记录用户加入书架的书籍';

CREATE TABLE "omni"."reader_catalog_nodes" (
  "id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "parent_id" uuid,
  "node_type" varchar(20) NOT NULL,
  "title" varchar(500) NOT NULL,
  "sort_index" int4 NOT NULL DEFAULT 0,
  "page_count" int4 DEFAULT 0,
  "created_at" timestamp(6) NOT NULL DEFAULT now(),
  "source_id" uuid,
  "catalog_key" varchar(500),
  "page_start_index" int4,
  "page_end_index" int4
)
;

CREATE TABLE "omni"."reader_item_sources" (
  "id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "file_node_id" uuid NOT NULL,
  "content_hash" varchar(64) NOT NULL,
  "file_format" varchar(20) NOT NULL,
  "source_name" varchar(500),
  "page_count" int4 DEFAULT 0,
  "created_at" timestamp(6) NOT NULL DEFAULT now(),
  "source_sort_key" varchar(200),
  "status" varchar(20) NOT NULL DEFAULT 'READY'::character varying,
  "error_code" varchar(50),
  "error_message" text,
  "retry_count" int4 NOT NULL DEFAULT 0,
  "season_no" int4,
  "volume_no" int4,
  "chapter_start" int4,
  "chapter_end" int4,
  "extra_order" int4,
  "reading_direction" varchar(10)
)
;

CREATE TABLE "omni"."reader_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "file_node_id" uuid,
  "content_hash" varchar(64),
  "item_type" varchar(16) NOT NULL,
  "title" varchar(500) NOT NULL,
  "author_name" varchar(300),
  "description" text,
  "cover_file_id" uuid,
  "publisher" varchar(300),
  "language" varchar(32),
  "release_date" date,
  "rating" numeric(4,2),
  "genres" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "external_ids" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "content_kind" varchar(20) NOT NULL DEFAULT 'TEXT'::character varying,
  "manifest_version" int4 NOT NULL DEFAULT 0,
  "import_status" varchar(20) NOT NULL DEFAULT 'READY'::character varying,
  "parse_error_code" varchar(50),
  "parse_error_message" text,
  "parsed_at" timestamp(6)
)
;
COMMENT ON COLUMN "omni"."reader_items"."file_node_id" IS '原始文件节点ID，关联 file_nodes（MinIO 存储）';
COMMENT ON COLUMN "omni"."reader_items"."item_type" IS '条目类型：EPUB / TXT / CBZ / ZIP / PDF';
COMMENT ON COLUMN "omni"."reader_items"."cover_file_id" IS '封面文件ID，导入时从 EPUB 提取存入 MinIO';
COMMENT ON COLUMN "omni"."reader_items"."external_ids" IS '外部平台ID，JSONB（预留刮削扩展）';
COMMENT ON TABLE "omni"."reader_items" IS '阅读条目表，存储书籍元数据和文件引用';

CREATE TABLE "omni"."reader_text_chapters" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "reader_item_id" uuid NOT NULL,
  "chapter_index" int4 NOT NULL,
  "chapter_key" varchar(128) NOT NULL,
  "title" varchar(500) NOT NULL,
  "content_path" varchar(1000),
  "source_start_offset" int8,
  "source_end_offset" int8,
  "char_count" int4 NOT NULL DEFAULT 0,
  "level" int4 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON TABLE "omni"."reader_text_chapters" IS '文本书籍服务端解析章节清单';
COMMENT ON COLUMN "omni"."reader_text_chapters"."content_path" IS 'EPUB 归档内正文路径';
COMMENT ON COLUMN "omni"."reader_text_chapters"."source_start_offset" IS 'TXT 源文本字符起始偏移';
COMMENT ON COLUMN "omni"."reader_text_chapters"."source_end_offset" IS 'TXT 源文本字符结束偏移';

CREATE TABLE "omni"."reader_notes" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "char_offset" int8,
  "title" varchar(500),
  "content" text NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "client_operation_id" varchar(120)
)
;
COMMENT ON COLUMN "omni"."reader_notes"."char_offset" IS '可选，关联到全书某个字符偏移位置';
COMMENT ON COLUMN "omni"."reader_notes"."client_operation_id" IS '客户端离线创建操作号，用于重试幂等';
COMMENT ON TABLE "omni"."reader_notes" IS '自由笔记表，可独立存在也可关联到全书某个位置';

CREATE TABLE "omni"."reader_page_assets" (
  "id" uuid NOT NULL,
  "page_id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "source_id" uuid NOT NULL,
  "manifest_version" int4 NOT NULL,
  "file_node_id" uuid NOT NULL,
  "mime_type" varchar(50) NOT NULL,
  "byte_size" int8 NOT NULL,
  "checksum" varchar(64),
  "created_at" timestamp(6) NOT NULL DEFAULT now()
)
;
COMMENT ON COLUMN "omni"."reader_page_assets"."id" IS '页级派生资源唯一标识';
COMMENT ON COLUMN "omni"."reader_page_assets"."page_id" IS '漫画页面 ID，由应用层关联 reader_pages';
COMMENT ON COLUMN "omni"."reader_page_assets"."reader_item_id" IS '阅读条目 ID，由应用层关联 reader_items';
COMMENT ON COLUMN "omni"."reader_page_assets"."source_id" IS '漫画来源文件 ID，由应用层关联 reader_item_sources';
COMMENT ON COLUMN "omni"."reader_page_assets"."manifest_version" IS '漫画清单版本号';
COMMENT ON COLUMN "omni"."reader_page_assets"."file_node_id" IS '派生资产 FileNode ID，对象定位由 File 模块解析';

COMMENT ON COLUMN "omni"."reader_page_assets"."mime_type" IS '图片 MIME 类型';
COMMENT ON COLUMN "omni"."reader_page_assets"."byte_size" IS '图片字节大小';
COMMENT ON COLUMN "omni"."reader_page_assets"."checksum" IS '图片校验值';
COMMENT ON COLUMN "omni"."reader_page_assets"."created_at" IS '创建时间';
COMMENT ON TABLE "omni"."reader_page_assets" IS '漫画页面派生资源表，保存页级图片对象索引';

CREATE TABLE "omni"."reader_pages" (
  "id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "source_id" uuid NOT NULL,
  "catalog_node_id" uuid,
  "page_index" int4 NOT NULL,
  "source_path" varchar(1000) NOT NULL,
  "width" int4,
  "height" int4,
  "fingerprint" varchar(64),
  "created_at" timestamp(6) NOT NULL DEFAULT now(),
  "entry_index" int4,
  "mime_type" varchar(50),
  "byte_size" int8,
  "source_page_index" int4 NOT NULL DEFAULT 0,
  "catalog_key" varchar(500)
)
;

CREATE TABLE "omni"."reader_progress" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "char_offset" int8 NOT NULL DEFAULT 0,
  "progress_percent" numeric(8,5) NOT NULL DEFAULT 0,
  "reading_mode" varchar(16) NOT NULL DEFAULT 'scroll'::character varying,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "chapter_id" varchar(128) NOT NULL DEFAULT ''::character varying,
  "page_id" uuid,
  "page_index" int4,
  "page_fingerprint" varchar(64),
  "source_id" uuid,
  "manifest_version" int4 DEFAULT 0,
  "intra_page_offset" float8,
  "source_page_index" int4,
  "catalog_key" varchar(500)
)
;
COMMENT ON COLUMN "omni"."reader_progress"."char_offset" IS '章节内字符偏移，与 chapter_id 共同构成精确位置，用于恢复阅读进度';
COMMENT ON COLUMN "omni"."reader_progress"."progress_percent" IS '全书进度比例（0-1），仅用于 UI 显示，不参与位置恢复';
COMMENT ON COLUMN "omni"."reader_progress"."reading_mode" IS '阅读模式：scroll（滚动）/ page（翻页）';
COMMENT ON COLUMN "omni"."reader_progress"."chapter_id" IS '阅读章节 ID，与 char_offset（章节内字符偏移）共同构成精确位置';
COMMENT ON COLUMN "omni"."reader_progress"."page_id" IS '漫画当前页面 ID，用于按页恢复漫画阅读位置';
COMMENT ON COLUMN "omni"."reader_progress"."page_index" IS '漫画当前页面全局索引';
COMMENT ON COLUMN "omni"."reader_progress"."page_fingerprint" IS '漫画当前页面指纹，用于清单变化后的锚点校验';
COMMENT ON COLUMN "omni"."reader_progress"."source_id" IS '漫画当前页面所属来源文件 ID';
COMMENT ON COLUMN "omni"."reader_progress"."manifest_version" IS '漫画清单版本号，用于检测目录或页面结构变化';
COMMENT ON COLUMN "omni"."reader_progress"."intra_page_offset" IS '漫画页内偏移，滚动模式下取值 0 到 1';
COMMENT ON COLUMN "omni"."reader_progress"."source_page_index" IS '漫画当前页面在来源文件内的索引';
COMMENT ON COLUMN "omni"."reader_progress"."catalog_key" IS '漫画当前页面所属目录键，用于多层目录恢复';
COMMENT ON TABLE "omni"."reader_progress" IS '阅读进度表，每本书每用户一条记录，全书线性进度';

CREATE TABLE "omni"."reader_reading_sessions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "reader_item_id" uuid NOT NULL,
  "started_at" timestamptz(6) NOT NULL,
  "ended_at" timestamptz(6) NOT NULL,
  "duration_seconds" int4 NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "client_session_id" varchar(128)
)
;
COMMENT ON COLUMN "omni"."reader_reading_sessions"."client_session_id" IS '客户端会话幂等ID，用于离线队列重试去重';
COMMENT ON TABLE "omni"."reader_reading_sessions" IS '阅读会话表，用于统计阅读时长';

CREATE TABLE "omni"."search_index_states" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid,
  "index_path" text NOT NULL,
  "schema_version" varchar(32) NOT NULL,
  "analyzer_name" varchar(80) NOT NULL,
  "dictionary_version" varchar(80),
  "status" varchar(32) NOT NULL DEFAULT 'READY'::character varying,
  "last_rebuild_task_id" uuid,
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."search_index_states"."id" IS '状态唯一标识，主键';
COMMENT ON COLUMN "omni"."search_index_states"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."search_index_states"."index_path" IS '搜索索引路径';
COMMENT ON COLUMN "omni"."search_index_states"."schema_version" IS '索引结构版本';
COMMENT ON COLUMN "omni"."search_index_states"."analyzer_name" IS '分词器名称';
COMMENT ON COLUMN "omni"."search_index_states"."dictionary_version" IS '词典版本';
COMMENT ON COLUMN "omni"."search_index_states"."status" IS '状态';
COMMENT ON COLUMN "omni"."search_index_states"."last_rebuild_task_id" IS '最后重建任务ID，关联sys_tasks';
COMMENT ON COLUMN "omni"."search_index_states"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."search_index_states"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."search_index_states" IS '搜索索引状态表，记录用户索引路径、版本和重建状态';

CREATE TABLE "omni"."share_links" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "resource_type" varchar(32) NOT NULL,
  "resource_id" uuid NOT NULL,
  "token_hash" varchar(128) NOT NULL,
  "token_cipher" text,
  "password_hash" varchar(255),
  "expires_at" timestamptz(6),
  "max_access_count" int4,
  "access_count" int4 NOT NULL DEFAULT 0,
  "include_location" bool NOT NULL DEFAULT true,
  "original_quality" bool NOT NULL DEFAULT true,
  "disabled_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."share_links"."id" IS '分享唯一标识，主键';
COMMENT ON COLUMN "omni"."share_links"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."share_links"."resource_type" IS '资源类型';
COMMENT ON COLUMN "omni"."share_links"."resource_id" IS '资源ID';
COMMENT ON COLUMN "omni"."share_links"."token_hash" IS '分享令牌哈希';
COMMENT ON COLUMN "omni"."share_links"."token_cipher" IS '分享令牌密文，供所有者重新展示链接地址';
COMMENT ON COLUMN "omni"."share_links"."password_hash" IS '访问密码哈希';
COMMENT ON COLUMN "omni"."share_links"."expires_at" IS '过期时间';
COMMENT ON COLUMN "omni"."share_links"."max_access_count" IS '最大访问次数';
COMMENT ON COLUMN "omni"."share_links"."access_count" IS '已访问次数';
COMMENT ON COLUMN "omni"."share_links"."include_location" IS '公开访问是否包含位置信息';
COMMENT ON COLUMN "omni"."share_links"."original_quality" IS '公开访问是否签发原图地址';
COMMENT ON COLUMN "omni"."share_links"."disabled_at" IS '禁用时间';
COMMENT ON COLUMN "omni"."share_links"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."share_links"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."share_links"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."share_links" IS '分享链接表，保存文件或内容的公开分享令牌与限制';

CREATE TABLE "omni"."shared_space_permissions" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "role_id" uuid NOT NULL,
  "can_browse" bool NOT NULL DEFAULT true,
  "can_upload" bool NOT NULL DEFAULT true,
  "can_download" bool NOT NULL DEFAULT true,
  "can_delete_own" bool NOT NULL DEFAULT true,
  "can_delete_any" bool NOT NULL DEFAULT false,
  "can_move_to" bool NOT NULL DEFAULT true,
  "can_move_from" bool NOT NULL DEFAULT true,
  "can_create_folder" bool NOT NULL DEFAULT true,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."shared_space_permissions"."role_id" IS '角色ID，关联auth_roles';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_browse" IS '是否允许浏览共享空间';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_upload" IS '是否允许上传到共享空间';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_download" IS '是否允许下载共享空间文件';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_delete_own" IS '是否允许删除自己上传的文件';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_delete_any" IS '是否允许删除任意文件（管理员）';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_move_to" IS '是否允许从个人空间移入共享空间';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_move_from" IS '是否允许从共享空间移回个人空间';
COMMENT ON COLUMN "omni"."shared_space_permissions"."can_create_folder" IS '是否允许在共享空间创建文件夹';
COMMENT ON TABLE "omni"."shared_space_permissions" IS '共享空间权限表，按角色控制共享空间操作权限';

CREATE TABLE "omni"."shared_space_usage" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "used_bytes" int8 NOT NULL DEFAULT 0,
  "file_count" int8 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON TABLE "omni"."shared_space_usage" IS '共享空间用量表，记录共享空间的总使用量';

CREATE TABLE "omni"."storage_quota_reservations" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "source_type" varchar(32) NOT NULL,
  "source_id" uuid NOT NULL,
  "reserved_bytes" int8 NOT NULL,
  "committed_bytes" int8 NOT NULL DEFAULT 0,
  "quota_applied" bool NOT NULL DEFAULT true,
  "status" varchar(24) NOT NULL DEFAULT 'RESERVED',
  "expires_at" timestamptz(6) NOT NULL,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."storage_quota_reservations"."owner_user_id" IS '预留所属用户ID';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."id" IS '配额预留唯一标识，主键';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."source_type" IS '来源类型：UPLOAD / EXTERNAL_IMPORT / OFFLINE_DOWNLOAD';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."source_id" IS '来源业务记录ID';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."reserved_bytes" IS '预留字节数';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."committed_bytes" IS '最终结算为实际用量的字节数';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."quota_applied" IS '是否实际占用受限账户的预留字节';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."status" IS '状态：RESERVED / COMMITTED / RELEASED / EXPIRED';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."expires_at" IS '预留自动过期时间';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."storage_quota_reservations"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."storage_quota_reservations" IS '持久化文件写入任务的存储配额预留与结算状态';

CREATE TABLE "omni"."storage_external_accounts" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "provider" varchar(64) NOT NULL,
  "display_name" varchar(160) NOT NULL,
  "encrypted_credentials" text NOT NULL,
  "status" varchar(32) NOT NULL DEFAULT 'ACTIVE'::character varying,
  "last_error_code" varchar(64),
  "last_checked_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."storage_external_accounts"."id" IS '账号唯一标识，主键';
COMMENT ON COLUMN "omni"."storage_external_accounts"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."storage_external_accounts"."provider" IS '服务提供商';
COMMENT ON COLUMN "omni"."storage_external_accounts"."display_name" IS '展示名称';
COMMENT ON COLUMN "omni"."storage_external_accounts"."encrypted_credentials" IS '加密后的凭据';
COMMENT ON COLUMN "omni"."storage_external_accounts"."status" IS '状态';
COMMENT ON COLUMN "omni"."storage_external_accounts"."last_error_code" IS '最近连接错误码';
COMMENT ON COLUMN "omni"."storage_external_accounts"."last_checked_at" IS '最近连接检查时间';
COMMENT ON COLUMN "omni"."storage_external_accounts"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."storage_external_accounts"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."storage_external_accounts"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."storage_external_accounts" IS '外部存储账号表，保存用户绑定的第三方存储配置';

CREATE TABLE "omni"."storage_connector_oauth_apps" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "connector_code" varchar(64) NOT NULL,
  "client_id" varchar(256) NOT NULL,
  "client_secret_encrypted" text NOT NULL,
  "redirect_uri" varchar(512) NOT NULL,
  "enabled" bool NOT NULL DEFAULT true,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "storage_connector_oauth_apps_pkey" PRIMARY KEY ("id")
)
;
COMMENT ON COLUMN "omni"."storage_connector_oauth_apps"."connector_code" IS '连接器编码，如 ONEDRIVE';
COMMENT ON COLUMN "omni"."storage_connector_oauth_apps"."client_id" IS 'OAuth 应用 Client ID';
COMMENT ON COLUMN "omni"."storage_connector_oauth_apps"."client_secret_encrypted" IS '加密后的 Client Secret';
COMMENT ON COLUMN "omni"."storage_connector_oauth_apps"."redirect_uri" IS 'OAuth 回调地址';
COMMENT ON TABLE "omni"."storage_connector_oauth_apps" IS '实例级 OAuth 应用配置（BYOA）';

CREATE UNIQUE INDEX "uk_storage_connector_oauth_apps_code" ON "omni"."storage_connector_oauth_apps" USING btree (
  "connector_code"
);

CREATE TABLE "omni"."storage_import_tasks" (
  "id" uuid NOT NULL,
  "owner_user_id" uuid NOT NULL,
  "external_account_id" uuid NOT NULL,
  "source_path" varchar(1024) NOT NULL,
  "target_parent_id" uuid,
  "rclone_job_id" int4,
  "rclone_group" varchar(128),
  "file_name" varchar(255) NOT NULL,
  "total_bytes" int8 NOT NULL DEFAULT 0,
  "transferred_bytes" int8 NOT NULL DEFAULT 0,
  "speed_bytes" int8 NOT NULL DEFAULT 0,
  "status" varchar(32) NOT NULL DEFAULT 'QUEUED'::character varying,
  "error_summary" text,
  "completed_file_id" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "space_type" varchar(16) NOT NULL DEFAULT 'PERSONAL'::character varying,
  "task_id" uuid,
  "source_kind" varchar(16) NOT NULL DEFAULT 'FILE'::character varying,
  "total_files" int4 NOT NULL DEFAULT 0,
  "completed_files" int4 NOT NULL DEFAULT 0,
  "current_file_name" varchar(1024)
)
;
COMMENT ON COLUMN "omni"."storage_import_tasks"."task_id" IS '系统任务ID，关联sys_tasks';
COMMENT ON COLUMN "omni"."storage_import_tasks"."source_kind" IS '导入源类型：FILE或DIRECTORY';
COMMENT ON COLUMN "omni"."storage_import_tasks"."total_files" IS '任务包含的文件总数';
COMMENT ON COLUMN "omni"."storage_import_tasks"."completed_files" IS '已完成入库的文件数';
COMMENT ON COLUMN "omni"."storage_import_tasks"."current_file_name" IS '当前扫描、传输或入库的文件相对路径';

CREATE TABLE "omni"."storage_remote_metadata_cache" (
  "id" uuid NOT NULL,
  "external_account_id" uuid NOT NULL,
  "remote_path" varchar(1024) NOT NULL,
  "metadata_json" jsonb NOT NULL,
  "cached_at" timestamptz(6) NOT NULL DEFAULT now(),
  "expires_at" timestamptz(6) NOT NULL
)
;

CREATE TABLE "omni"."sync_event_checkpoints" (
  "id" uuid NOT NULL,
  "checkpoint_key" varchar(64) NOT NULL,
  "sequence_no" int8 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."sync_events" (
  "id" uuid NOT NULL,
  "sequence_no" int8 NOT NULL GENERATED ALWAYS AS IDENTITY (
INCREMENT 1
MINVALUE  1
MAXVALUE 9223372036854775807
START 1
CACHE 1
),
  "recipient_user_id" uuid NOT NULL,
  "scope" varchar(32) NOT NULL,
  "resource_type" varchar(64) NOT NULL,
  "resource_id" varchar(128),
  "action" varchar(32) NOT NULL,
  "resource_version" int8,
  "payload" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "publish_status" varchar(16) NOT NULL DEFAULT 'PENDING'::character varying,
  "publish_attempts" int4 NOT NULL DEFAULT 0,
  "available_at" timestamptz(6) NOT NULL DEFAULT now(),
  "locked_by" varchar(128),
  "locked_until" timestamptz(6),
  "published_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;

CREATE TABLE "omni"."sys_tasks" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "task_type" varchar(80) NOT NULL,
  "status" varchar(32) NOT NULL,
  "routing_key" varchar(200),
  "phase" varchar(64),
  "resource_type" varchar(64),
  "resource_id" uuid,
  "payload" text,
  "result" text,
  "error_summary" text,
  "stack_summary" text,
  "retry_count" int4 NOT NULL DEFAULT 0,
  "progress" int4 NOT NULL DEFAULT 0,
  "max_retries" int4 NOT NULL DEFAULT 3,
  "started_at" timestamptz(6),
  "completed_at" timestamptz(6),
  "next_retry_at" timestamptz(6),
  "heartbeat_at" timestamptz(6),
  "owner_user_id" uuid,
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON COLUMN "omni"."sys_tasks"."id" IS '任务唯一标识，主键';
COMMENT ON COLUMN "omni"."sys_tasks"."task_type" IS '任务类型';
COMMENT ON COLUMN "omni"."sys_tasks"."status" IS '任务状态：QUEUED / RUNNING / RETRY_WAIT / COMPLETED / FAILED / CANCELLED / DLQ';
COMMENT ON COLUMN "omni"."sys_tasks"."routing_key" IS '消息路由键';
COMMENT ON COLUMN "omni"."sys_tasks"."phase" IS '任务内部执行阶段';
COMMENT ON COLUMN "omni"."sys_tasks"."resource_type" IS '任务关联资源类型';
COMMENT ON COLUMN "omni"."sys_tasks"."resource_id" IS '任务关联资源ID';
COMMENT ON COLUMN "omni"."sys_tasks"."payload" IS '任务载荷，JSON文本';
COMMENT ON COLUMN "omni"."sys_tasks"."result" IS '执行结果，JSON文本';
COMMENT ON COLUMN "omni"."sys_tasks"."error_summary" IS '错误摘要';
COMMENT ON COLUMN "omni"."sys_tasks"."stack_summary" IS '失败堆栈摘要，脱敏截断';
COMMENT ON COLUMN "omni"."sys_tasks"."retry_count" IS '已重试次数';
COMMENT ON COLUMN "omni"."sys_tasks"."progress" IS '进度值（0~100）';
COMMENT ON COLUMN "omni"."sys_tasks"."max_retries" IS '最大重试次数';
COMMENT ON COLUMN "omni"."sys_tasks"."started_at" IS '开始执行时间';
COMMENT ON COLUMN "omni"."sys_tasks"."completed_at" IS '完成时间';
COMMENT ON COLUMN "omni"."sys_tasks"."next_retry_at" IS '下次允许自动重试时间';
COMMENT ON COLUMN "omni"."sys_tasks"."heartbeat_at" IS '任务执行心跳时间';
COMMENT ON COLUMN "omni"."sys_tasks"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."sys_tasks"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."sys_tasks"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."sys_tasks"."version" IS '乐观锁版本号';
COMMENT ON TABLE "omni"."sys_tasks" IS '系统任务记录表，保存通用异步任务的状态和执行信息';

CREATE TABLE "omni"."sys_task_dispatches" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "task_id" uuid NOT NULL,
  "exchange_name" varchar(160) NOT NULL,
  "routing_key" varchar(200) NOT NULL,
  "payload" text NOT NULL,
  "status" varchar(24) NOT NULL DEFAULT 'PENDING',
  "attempt_count" int4 NOT NULL DEFAULT 0,
  "next_attempt_at" timestamptz(6) NOT NULL DEFAULT now(),
  "locked_by" varchar(128),
  "locked_until" timestamptz(6),
  "published_at" timestamptz(6),
  "last_error_code" varchar(64),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0
)
;
COMMENT ON TABLE "omni"."sys_task_dispatches" IS '异步任务可靠投递Outbox';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."status" IS '发布状态：PENDING / PUBLISHING / PUBLISHED';

CREATE TABLE "omni"."user_preferences" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_user_id" uuid NOT NULL,
  "scope" varchar(32) NOT NULL,
  "preferences" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  "created_at" timestamptz(6) NOT NULL
)
;
COMMENT ON COLUMN "omni"."user_preferences"."id" IS '主键 ID。';
COMMENT ON COLUMN "omni"."user_preferences"."owner_user_id" IS '所属用户 ID。';
COMMENT ON COLUMN "omni"."user_preferences"."scope" IS '配置作用域，如 reader、video、music 等。';
COMMENT ON COLUMN "omni"."user_preferences"."preferences" IS '该作用域下的偏好配置 JSON，字段由各子系统自定义。';
COMMENT ON COLUMN "omni"."user_preferences"."updated_at" IS '更新时间。';
COMMENT ON COLUMN "omni"."user_preferences"."version" IS '乐观锁版本号。';
COMMENT ON COLUMN "omni"."user_preferences"."created_at" IS '创建时间。';
COMMENT ON TABLE "omni"."user_preferences" IS '用户偏好设置表，按子系统 scope 分组保存个性化配置。';

CREATE INDEX "idx_audit_logs_actor_created" ON "omni"."audit_logs" USING btree (
  "actor_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_audit_logs_created_at" ON "omni"."audit_logs" USING btree (
  "created_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_audit_logs_resource" ON "omni"."audit_logs" USING btree (
  "resource_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "resource_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."audit_logs" ADD CONSTRAINT "ck_audit_logs_metadata_json_size" CHECK (octet_length(metadata::text) <= 262144);

ALTER TABLE "omni"."audit_logs" ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_sessions_expires_at" ON "omni"."auth_active_sessions" USING btree (
  "expires_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sessions_user_platform" ON "omni"."auth_active_sessions" USING btree (
  "user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "client_platform" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE revoked_at IS NULL;

ALTER TABLE "omni"."auth_active_sessions" ADD CONSTRAINT "auth_active_sessions_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_auth_backup_codes_user" ON "omni"."auth_backup_codes" USING btree (
  "user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."auth_backup_codes" ADD CONSTRAINT "auth_backup_codes_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_login_audit_user" ON "omni"."auth_login_audit" USING btree (
  "user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."auth_login_audit" ADD CONSTRAINT "auth_login_audit_pkey" PRIMARY KEY ("id");

ALTER TABLE "omni"."auth_permissions" ADD CONSTRAINT "uniq_auth_permissions_code" UNIQUE ("code");

ALTER TABLE "omni"."auth_permissions" ADD CONSTRAINT "auth_permissions_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_auth_role_permissions_permission" ON "omni"."auth_role_permissions" USING btree (
  "permission_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."auth_role_permissions" ADD CONSTRAINT "auth_role_permissions_pkey" PRIMARY KEY ("role_id", "permission_id");

ALTER TABLE "omni"."auth_roles" ADD CONSTRAINT "uniq_auth_roles_code" UNIQUE ("code");

ALTER TABLE "omni"."auth_roles" ADD CONSTRAINT "auth_roles_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_session_revocations_user_session" ON "omni"."auth_session_revocations" USING btree (
  "user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "session_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."auth_session_revocations" ADD CONSTRAINT "auth_session_revocations_pkey" PRIMARY KEY ("id");

CREATE UNIQUE INDEX "uniq_auth_totp_credentials_user" ON "omni"."auth_totp_credentials" USING btree (
  "user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."auth_totp_credentials" ADD CONSTRAINT "auth_totp_credentials_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_auth_user_roles_role" ON "omni"."auth_user_roles" USING btree (
  "role_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."auth_user_roles" ADD CONSTRAINT "auth_user_roles_pkey" PRIMARY KEY ("user_id", "role_id");

ALTER TABLE "omni"."auth_users" ADD CONSTRAINT "uniq_auth_users_username" UNIQUE ("username");

ALTER TABLE "omni"."auth_users" ADD CONSTRAINT "chk_auth_users_status" CHECK (status::text = ANY (ARRAY['ACTIVE'::character varying::text, 'DISABLED'::character varying::text]));
ALTER TABLE "omni"."auth_users" ADD CONSTRAINT "chk_auth_users_quota" CHECK (quota_bytes >= 0 AND used_bytes >= 0 AND reserved_bytes >= 0);

ALTER TABLE "omni"."auth_users" ADD CONSTRAINT "auth_users_pkey" PRIMARY KEY ("id");

ALTER TABLE "omni"."config_entries" ADD CONSTRAINT "uniq_config_entries_key" UNIQUE ("config_key");

ALTER TABLE "omni"."config_entries" ADD CONSTRAINT "chk_config_entries_value_type" CHECK (value_type::text = ANY (ARRAY['STRING'::character varying::text, 'NUMBER'::character varying::text, 'BOOLEAN'::character varying::text, 'JSON'::character varying::text]));
ALTER TABLE "omni"."config_entries" ADD CONSTRAINT "chk_config_entries_refresh_scope" CHECK (refresh_scope::text = ANY (ARRAY['HOT'::character varying::text, 'NEXT_TASK'::character varying::text, 'RESTART_REQUIRED'::character varying::text]));

ALTER TABLE "omni"."config_entries" ADD CONSTRAINT "config_entries_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_config_histories_key_created" ON "omni"."config_histories" USING btree (
  "config_key" "pg_catalog"."text_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."config_histories" ADD CONSTRAINT "config_histories_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_content_assets_owner_type" ON "omni"."content_assets" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "resource_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "asset_type" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "idx_content_assets_primary_unique" ON "omni"."content_assets" USING btree (
  "resource_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "resource_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "asset_type" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE is_primary = true;
CREATE INDEX "idx_content_assets_resource" ON "omni"."content_assets" USING btree (
  "resource_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "resource_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "asset_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "sort_order" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."content_assets" ADD CONSTRAINT "ck_content_assets_metadata_json_size" CHECK (octet_length(metadata::text) <= 262144);
ALTER TABLE "omni"."content_assets" ADD CONSTRAINT "chk_content_assets_asset_type" CHECK (asset_type::text = ANY (ARRAY['POSTER'::character varying::text, 'BACKDROP'::character varying::text, 'THUMBNAIL'::character varying::text, 'LOGO'::character varying::text, 'BANNER'::character varying::text, 'COVER'::character varying::text, 'ARTIST_PHOTO'::character varying::text, 'SCREENSHOT'::character varying::text, 'NFO'::character varying::text, 'LYRICS'::character varying::text, 'SUBTITLE'::character varying::text, 'OTHER'::character varying::text]));
ALTER TABLE "omni"."content_assets" ADD CONSTRAINT "chk_content_assets_source" CHECK (file_node_id IS NOT NULL OR external_url IS NOT NULL);
ALTER TABLE "omni"."content_assets" ADD CONSTRAINT "chk_content_assets_size" CHECK ((width IS NULL OR width >= 0) AND (height IS NULL OR height >= 0));
ALTER TABLE "omni"."content_assets" ADD CONSTRAINT "chk_content_assets_resource_type" CHECK (resource_type::text = ANY (ARRAY['VIDEO_ITEM'::character varying::text, 'TV_SERIES'::character varying::text, 'TV_SEASON'::character varying::text, 'EPISODE'::character varying::text, 'MOVIE'::character varying::text, 'MUSIC_TRACK'::character varying::text, 'MUSIC_ALBUM'::character varying::text, 'MUSIC_ARTIST'::character varying::text, 'READER_ITEM'::character varying::text, 'READER_COLLECTION'::character varying::text]));

ALTER TABLE "omni"."content_assets" ADD CONSTRAINT "content_assets_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_download_offline_tasks_owner_status" ON "omni"."download_offline_tasks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_download_offline_tasks_task" ON "omni"."download_offline_tasks" USING btree (
  "task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."download_offline_tasks" ADD CONSTRAINT "download_offline_tasks_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_access_records_owner_time" ON "omni"."file_access_records" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "last_accessed_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."file_access_records" ADD CONSTRAINT "uniq_file_access_records_owner_node" UNIQUE ("owner_user_id", "file_node_id");

ALTER TABLE "omni"."file_access_records" ADD CONSTRAINT "chk_file_access_records_count" CHECK (access_count >= 0);

ALTER TABLE "omni"."file_access_records" ADD CONSTRAINT "file_access_records_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_favorites_owner_created" ON "omni"."file_favorites" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."file_favorites" ADD CONSTRAINT "uniq_file_favorites_owner_node" UNIQUE ("owner_user_id", "file_node_id");

ALTER TABLE "omni"."file_favorites" ADD CONSTRAINT "file_favorites_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_fmr_file_node" ON "omni"."file_move_records" USING btree (
  "file_node_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_fmr_operator" ON "omni"."file_move_records" USING btree (
  "operator_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."file_move_records" ADD CONSTRAINT "pk_file_move_records" PRIMARY KEY ("id");

CREATE INDEX "idx_file_node_permissions_grantee" ON "omni"."file_node_permissions" USING btree (
  "grantee_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE grantee_user_id IS NOT NULL;
CREATE INDEX "idx_file_node_permissions_node" ON "omni"."file_node_permissions" USING btree (
  "file_node_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_file_node_permissions_node_global" ON "omni"."file_node_permissions" USING btree (
  "file_node_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE grantee_user_id IS NULL;

ALTER TABLE "omni"."file_node_permissions" ADD CONSTRAINT "uk_file_node_permissions_node_grantee" UNIQUE ("file_node_id", "grantee_user_id");

ALTER TABLE "omni"."file_node_permissions" ADD CONSTRAINT "file_node_permissions_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_nodes_deleted" ON "omni"."file_nodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "deleted_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
) WHERE is_deleted = true;
CREATE INDEX "idx_file_nodes_shared_recycle" ON "omni"."file_nodes" USING btree (
  "deleted_by" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "deleted_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
) WHERE is_deleted = true AND space_type::text = 'SHARED'::text;
CREATE INDEX "idx_file_nodes_owner_image_created" ON "omni"."file_nodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST,
  "id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE is_deleted = false AND node_type::text = 'FILE'::text AND source_type::text <> 'DERIVED'::text AND mime_type::text ~~ 'image/%'::text;
CREATE INDEX "idx_file_nodes_owner_parent" ON "omni"."file_nodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "parent_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE is_deleted = false;
CREATE INDEX "idx_file_nodes_personal_category" ON "omni"."file_nodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "category" "pg_catalog"."text_ops" ASC NULLS LAST,
  "name" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE is_deleted = false AND space_type::text = 'PERSONAL'::text AND node_type::text = 'FILE'::text;
CREATE INDEX "idx_file_nodes_owner_path" ON "omni"."file_nodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "normalized_path" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_file_nodes_owner_purge" ON "omni"."file_nodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "is_deleted" "pg_catalog"."bool_ops" ASC NULLS LAST,
  "purge_state" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_file_nodes_purge_task" ON "omni"."file_nodes" USING btree (
  "purge_task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_file_nodes_shared_image_created" ON "omni"."file_nodes" USING btree (
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST,
  "id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE shared = true AND is_deleted = false AND node_type::text = 'FILE'::text AND source_type::text <> 'DERIVED'::text AND mime_type::text ~~ 'image/%'::text;
CREATE INDEX "idx_file_nodes_shared_space" ON "omni"."file_nodes" USING btree (
  "space_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "node_type" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE is_deleted = false AND space_type::text = 'SHARED'::text;
CREATE INDEX "idx_file_nodes_space_type" ON "omni"."file_nodes" USING btree (
  "space_type" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE is_deleted = false;
CREATE INDEX "idx_file_nodes_uploaded_by" ON "omni"."file_nodes" USING btree (
  "uploaded_by" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE space_type::text = 'SHARED'::text AND is_deleted = false;

ALTER TABLE "omni"."file_nodes" ADD CONSTRAINT "uniq_file_nodes_sibling_name" UNIQUE ("owner_user_id", "parent_id", "name", "is_deleted");

ALTER TABLE "omni"."file_nodes" ADD CONSTRAINT "chk_file_nodes_source" CHECK (source_type::text = ANY (ARRAY['LOCAL'::character varying::text, 'LOCAL_FILESYSTEM'::character varying::text, 'EXTERNAL'::character varying::text, 'DERIVED'::character varying::text, 'RCLONE'::character varying::text, 'SHARE'::character varying::text]));
ALTER TABLE "omni"."file_nodes" ADD CONSTRAINT "chk_file_nodes_type" CHECK (node_type::text = ANY (ARRAY['FILE'::character varying::text, 'FOLDER'::character varying::text]));
ALTER TABLE "omni"."file_nodes" ADD CONSTRAINT "chk_file_nodes_size" CHECK (size_bytes >= 0);
ALTER TABLE "omni"."file_nodes" ADD CONSTRAINT "chk_file_nodes_purge_state" CHECK (purge_state::text = ANY (ARRAY['NONE'::character varying::text, 'QUEUED'::character varying::text, 'RUNNING'::character varying::text, 'RETRY_WAIT'::character varying::text, 'FAILED'::character varying::text]));

ALTER TABLE "omni"."file_nodes" ADD CONSTRAINT "file_nodes_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_purge_entries_task_status" ON "omni"."file_purge_entries" USING btree (
  "task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uq_file_purge_entries_object" ON "omni"."file_purge_entries" USING btree (
  "task_id",
  "bucket_name",
  "object_key",
  COALESCE("minio_version_id", '')
);
ALTER TABLE "omni"."file_purge_entries" ADD CONSTRAINT "chk_file_purge_entries_status" CHECK (status::text = ANY (ARRAY['PENDING'::character varying::text, 'DELETED'::character varying::text, 'NOT_FOUND'::character varying::text, 'FAILED'::character varying::text]));
ALTER TABLE "omni"."file_purge_entries" ADD CONSTRAINT "chk_file_purge_entries_type" CHECK (entry_type::text = ANY (ARRAY['SOURCE'::character varying::text, 'VERSION'::character varying::text, 'DERIVED'::character varying::text, 'LEGACY'::character varying::text]));
ALTER TABLE "omni"."file_purge_entries" ADD CONSTRAINT "file_purge_entries_pkey" PRIMARY KEY ("id");

ALTER TABLE "omni"."file_objects" ADD CONSTRAINT "uniq_file_objects_bucket_key" UNIQUE ("bucket_name", "object_key");

ALTER TABLE "omni"."file_objects" ADD CONSTRAINT "chk_file_objects_size" CHECK (size_bytes >= 0);

ALTER TABLE "omni"."file_objects" ADD CONSTRAINT "file_objects_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_ingress_items_status_next_scan" ON "omni"."file_ingress_items" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "next_scan_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_file_ingress_items_owner_created" ON "omni"."file_ingress_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE UNIQUE INDEX "uq_file_ingress_items_quarantine_object" ON "omni"."file_ingress_items" USING btree (
  "quarantine_bucket",
  "quarantine_object_key"
);
CREATE UNIQUE INDEX "uq_file_ingress_items_upload_session" ON "omni"."file_ingress_items" USING btree (
  "upload_session_id"
) WHERE upload_session_id IS NOT NULL;
ALTER TABLE "omni"."file_ingress_items" ADD CONSTRAINT "chk_file_ingress_items_status" CHECK (status::text = ANY (ARRAY['PENDING_SCAN'::character varying::text, 'SCANNING'::character varying::text, 'CLEAN'::character varying::text, 'AVAILABLE'::character varying::text, 'REJECTED'::character varying::text, 'FAILED'::character varying::text]));
ALTER TABLE "omni"."file_ingress_items" ADD CONSTRAINT "chk_file_ingress_items_size" CHECK (size_bytes >= 0);
ALTER TABLE "omni"."file_ingress_items" ADD CONSTRAINT "file_ingress_items_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_share_recipients_user_created" ON "omni"."file_share_recipients" USING btree (
  "recipient_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."file_share_recipients" ADD CONSTRAINT "uniq_file_share_recipients_share_user" UNIQUE ("share_link_id", "recipient_user_id");

ALTER TABLE "omni"."file_share_recipients" ADD CONSTRAINT "file_share_recipients_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_upload_parts_owner_status" ON "omni"."file_upload_parts" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_file_upload_parts_session" ON "omni"."file_upload_parts" USING btree (
  "upload_session_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "part_number" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."file_upload_parts" ADD CONSTRAINT "uniq_file_upload_parts_session_part" UNIQUE ("upload_session_id", "part_number");

ALTER TABLE "omni"."file_upload_parts" ADD CONSTRAINT "chk_file_upload_parts_status" CHECK (status::text = ANY (ARRAY['PENDING'::character varying::text, 'COMPLETED'::character varying::text, 'FAILED'::character varying::text]));
ALTER TABLE "omni"."file_upload_parts" ADD CONSTRAINT "chk_file_upload_parts_number" CHECK (part_number > 0);
ALTER TABLE "omni"."file_upload_parts" ADD CONSTRAINT "chk_file_upload_parts_size" CHECK (size_bytes > 0);

ALTER TABLE "omni"."file_upload_parts" ADD CONSTRAINT "file_upload_parts_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_file_upload_sessions_owner_status" ON "omni"."file_upload_sessions" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_file_upload_sessions_upload_id" ON "omni"."file_upload_sessions" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "upload_id" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uq_file_upload_sessions_ingress_item" ON "omni"."file_upload_sessions" USING btree (
  "ingress_item_id"
) WHERE ingress_item_id IS NOT NULL;
CREATE INDEX "idx_file_upload_sessions_result_node" ON "omni"."file_upload_sessions" USING btree (
  "result_file_node_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE result_file_node_id IS NOT NULL;

ALTER TABLE "omni"."file_upload_sessions" ADD CONSTRAINT "chk_file_upload_sessions_status" CHECK (status::text = ANY (ARRAY['CREATED'::character varying::text, 'UPLOADING'::character varying::text, 'FINALIZING'::character varying::text, 'SCANNING'::character varying::text, 'COMPLETED'::character varying::text, 'REJECTED'::character varying::text, 'FAILED'::character varying::text, 'CANCELLED'::character varying::text, 'EXPIRED'::character varying::text]));
ALTER TABLE "omni"."file_upload_sessions" ADD CONSTRAINT "chk_file_upload_sessions_size" CHECK (total_size_bytes > 0 AND total_parts > 0 AND uploaded_parts >= 0);

ALTER TABLE "omni"."file_upload_sessions" ADD CONSTRAINT "file_upload_sessions_pkey" PRIMARY KEY ("id");

ALTER TABLE "omni"."file_versions" ADD CONSTRAINT "uniq_file_versions_file_no" UNIQUE ("file_node_id", "version_no");

ALTER TABLE "omni"."file_versions" ADD CONSTRAINT "chk_file_versions_change_type" CHECK (change_type::text = ANY (ARRAY['UPLOAD'::character varying::text, 'EDIT'::character varying::text, 'RESTORE'::character varying::text, 'DERIVED'::character varying::text]));

ALTER TABLE "omni"."file_versions" ADD CONSTRAINT "file_versions_pkey" PRIMARY KEY ("id");


CREATE UNIQUE INDEX "uk_integration_accounts_owner_type_provider" ON "omni"."integration_accounts" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "integration_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "provider" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uq_file_upload_sessions_quota_reservation" ON "omni"."file_upload_sessions" USING btree (
  "quota_reservation_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE (quota_reservation_id IS NOT NULL);

ALTER TABLE "omni"."integration_accounts" ADD CONSTRAINT "integration_accounts_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_movies_owner_updated" ON "omni"."media_movies" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE UNIQUE INDEX "uk_media_movies_local_identity" ON "omni"."media_movies" USING btree (
  "owner_user_id", "library_source_id", lower(title), COALESCE(release_date, DATE '0001-01-01')
) WHERE library_source_id IS NOT NULL;
CREATE UNIQUE INDEX "uk_movie_owner_tmdb" ON "omni"."media_movies" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "tmdb_id" "pg_catalog"."int4_ops" ASC NULLS LAST
) WHERE tmdb_id IS NOT NULL;

ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "ck_media_movies_cast_json_size" CHECK (octet_length(cast_members::text) <= 2097152);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "ck_media_movies_crew_json_size" CHECK (octet_length(crew_members::text) <= 2097152);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "ck_media_movies_studios_json_size" CHECK (octet_length(studios::text) <= 131072);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "ck_media_movies_countries_json_size" CHECK (octet_length(countries::text) <= 131072);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "ck_media_movies_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "ck_media_movies_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 2097152);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "ck_media_movies_genres_json_size" CHECK (octet_length(genres::text) <= 65536);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "chk_media_movies_metadata_status" CHECK (metadata_status::text = ANY (ARRAY['PENDING'::character varying::text, 'MATCHED'::character varying::text, 'MANUAL'::character varying::text, 'FAILED'::character varying::text]));
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "chk_media_movies_rating" CHECK (rating IS NULL OR rating >= 0::numeric AND rating <= 10::numeric);
ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "chk_media_movies_vote_count" CHECK (vote_count >= 0);

ALTER TABLE "omni"."media_movies" ADD CONSTRAINT "media_movies_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_nfo_exports_item_updated" ON "omni"."media_nfo_exports" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "video_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."media_nfo_exports" ADD CONSTRAINT "chk_media_nfo_exports_status" CHECK (status::text = ANY (ARRAY['PENDING'::character varying::text, 'GENERATED'::character varying::text, 'FAILED'::character varying::text]));

ALTER TABLE "omni"."media_nfo_exports" ADD CONSTRAINT "media_nfo_exports_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_playback_progresses_owner_type_updated" ON "omni"."media_playback_progresses" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "media_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_media_playback_progresses_owner_updated" ON "omni"."media_playback_progresses" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."media_playback_progresses" ADD CONSTRAINT "uniq_media_playback_progresses_owner_type_key" UNIQUE ("owner_user_id", "media_type", "media_key");

ALTER TABLE "omni"."media_playback_progresses" ADD CONSTRAINT "chk_media_playback_progresses_type" CHECK (media_type::text = ANY (ARRAY['video'::character varying, 'music'::character varying]::text[]));

ALTER TABLE "omni"."media_playback_progresses" ADD CONSTRAINT "media_playback_progresses_pkey" PRIMARY KEY ("id");

ALTER TABLE "omni"."media_series_favorites" ADD CONSTRAINT "uniq_media_series_favorites_owner_series" UNIQUE ("owner_user_id", "series_id");

ALTER TABLE "omni"."media_series_favorites" ADD CONSTRAINT "media_series_favorites_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_subtitle_tracks_video_order" ON "omni"."media_subtitle_tracks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "video_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "sort_order" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."media_subtitle_tracks" ADD CONSTRAINT "chk_media_subtitle_tracks_kind" CHECK (track_kind::text = ANY (ARRAY['SUBTITLE'::text, 'CAPTION'::text, 'EXTERNAL'::text]));

ALTER TABLE "omni"."media_subtitle_tracks" ADD CONSTRAINT "media_subtitle_tracks_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_tv_episodes_series" ON "omni"."media_tv_episodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "series_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "season_number" "pg_catalog"."int4_ops" ASC NULLS LAST,
  "episode_number" "pg_catalog"."int4_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_episode_owner_series_season_ep" ON "omni"."media_tv_episodes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "series_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "season_number" "pg_catalog"."int4_ops" ASC NULLS LAST,
  "episode_number" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."media_tv_episodes" ADD CONSTRAINT "ck_media_tv_episodes_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 1048576);
ALTER TABLE "omni"."media_tv_episodes" ADD CONSTRAINT "ck_media_tv_episodes_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."media_tv_episodes" ADD CONSTRAINT "chk_media_tv_episodes_season_number" CHECK (season_number >= 0);
ALTER TABLE "omni"."media_tv_episodes" ADD CONSTRAINT "chk_media_tv_episodes_episode_number" CHECK (episode_number >= 0);
ALTER TABLE "omni"."media_tv_episodes" ADD CONSTRAINT "chk_media_tv_episodes_rating" CHECK (rating IS NULL OR rating >= 0::numeric AND rating <= 10::numeric);
ALTER TABLE "omni"."media_tv_episodes" ADD CONSTRAINT "chk_media_tv_episodes_metadata_status" CHECK (metadata_status::text = ANY (ARRAY['PENDING'::character varying::text, 'MATCHED'::character varying::text, 'MANUAL'::character varying::text, 'FAILED'::character varying::text]));

ALTER TABLE "omni"."media_tv_episodes" ADD CONSTRAINT "media_tv_episodes_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_tv_seasons_series_number" ON "omni"."media_tv_seasons" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "series_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "season_number" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."media_tv_seasons" ADD CONSTRAINT "uniq_media_tv_seasons_series_number" UNIQUE ("owner_user_id", "series_id", "season_number");

ALTER TABLE "omni"."media_tv_seasons" ADD CONSTRAINT "ck_media_tv_seasons_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."media_tv_seasons" ADD CONSTRAINT "chk_media_tv_seasons_rating" CHECK (rating IS NULL OR rating >= 0::numeric AND rating <= 10::numeric);
ALTER TABLE "omni"."media_tv_seasons" ADD CONSTRAINT "chk_media_tv_seasons_number" CHECK (season_number >= 0);
ALTER TABLE "omni"."media_tv_seasons" ADD CONSTRAINT "chk_media_tv_seasons_episode_count" CHECK (episode_count >= 0);
ALTER TABLE "omni"."media_tv_seasons" ADD CONSTRAINT "ck_media_tv_seasons_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 1048576);

ALTER TABLE "omni"."media_tv_seasons" ADD CONSTRAINT "media_tv_seasons_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_tv_series_external_ids" ON "omni"."media_tv_series" USING gin (
  "external_ids" "pg_catalog"."jsonb_path_ops"
);
CREATE INDEX "idx_media_tv_series_owner_updated" ON "omni"."media_tv_series" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_media_tv_series_title" ON "omni"."media_tv_series" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "title" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_media_tv_series_local_identity" ON "omni"."media_tv_series" USING btree (
  "owner_user_id", "library_source_id", lower(title)
) WHERE library_source_id IS NOT NULL;
CREATE INDEX "idx_media_tv_series_type" ON "omni"."media_tv_series" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "series_type" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_series_owner_tmdb" ON "omni"."media_tv_series" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "tmdb_id" "pg_catalog"."int4_ops" ASC NULLS LAST
) WHERE tmdb_id IS NOT NULL;

ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "ck_media_tv_series_cast_json_size" CHECK (octet_length(cast_members::text) <= 2097152);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "ck_media_tv_series_crew_json_size" CHECK (octet_length(crew_members::text) <= 2097152);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "ck_media_tv_series_studios_json_size" CHECK (octet_length(studios::text) <= 131072);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "ck_media_tv_series_countries_json_size" CHECK (octet_length(countries::text) <= 131072);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "ck_media_tv_series_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "ck_media_tv_series_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 2097152);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "ck_media_tv_series_genres_json_size" CHECK (octet_length(genres::text) <= 65536);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "chk_media_tv_series_metadata_status" CHECK (metadata_status::text = ANY (ARRAY['PENDING'::character varying::text, 'MATCHED'::character varying::text, 'MANUAL'::character varying::text, 'FAILED'::character varying::text]));
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "chk_media_tv_series_type" CHECK (series_type::text = ANY (ARRAY['TV'::character varying::text, 'ANIME'::character varying::text, 'DOCUMENTARY'::character varying::text]));
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "chk_media_tv_series_rating" CHECK (rating IS NULL OR rating >= 0::numeric AND rating <= 10::numeric);
ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "chk_media_tv_series_vote_count" CHECK (vote_count >= 0);

ALTER TABLE "omni"."media_tv_series" ADD CONSTRAINT "media_tv_series_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_video_collection_items_collection" ON "omni"."media_video_collection_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "collection_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "sort_order" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."media_video_collection_items" ADD CONSTRAINT "uniq_media_video_collection_items" UNIQUE ("collection_id", "video_item_id");

ALTER TABLE "omni"."media_video_collection_items" ADD CONSTRAINT "media_video_collection_items_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_video_collections_owner_updated" ON "omni"."media_video_collections" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."media_video_collections" ADD CONSTRAINT "chk_media_video_collections_type" CHECK (collection_type::text = ANY (ARRAY['MANUAL'::character varying::text, 'AUTO'::character varying::text]));

ALTER TABLE "omni"."media_video_collections" ADD CONSTRAINT "media_video_collections_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_video_favorites_owner_created" ON "omni"."media_video_favorites" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."media_video_favorites" ADD CONSTRAINT "uniq_media_video_favorites_owner_item" UNIQUE ("owner_user_id", "video_item_id");

ALTER TABLE "omni"."media_video_favorites" ADD CONSTRAINT "media_video_favorites_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_video_items_episode_id" ON "omni"."media_video_items" USING btree (
  "episode_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE episode_id IS NOT NULL;
CREATE INDEX "idx_media_video_items_metadata_status" ON "omni"."media_video_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "metadata_status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_media_video_items_library_source" ON "omni"."media_video_items" USING btree (
  "owner_user_id", "library_source_id"
) WHERE library_source_id IS NOT NULL;
CREATE INDEX "idx_media_video_items_movie_id" ON "omni"."media_video_items" USING btree (
  "movie_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
) WHERE movie_id IS NOT NULL;
CREATE INDEX "idx_media_video_items_owner_type_updated" ON "omni"."media_video_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "media_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_media_video_items_series_episode" ON "omni"."media_video_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "series_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "season_number" "pg_catalog"."int4_ops" ASC NULLS LAST,
  "episode_number" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."media_video_items" ADD CONSTRAINT "uniq_media_video_items_file" UNIQUE ("file_node_id");

ALTER TABLE "omni"."media_video_items" ADD CONSTRAINT "chk_media_video_items_nfo_status" CHECK (nfo_status::text = ANY (ARRAY['DISABLED'::character varying::text, 'PENDING'::character varying::text, 'GENERATED'::character varying::text, 'FAILED'::character varying::text]));
ALTER TABLE "omni"."media_video_items" ADD CONSTRAINT "chk_media_video_items_runtime" CHECK (runtime_seconds IS NULL OR runtime_seconds >= 0);
ALTER TABLE "omni"."media_video_items" ADD CONSTRAINT "chk_media_video_items_resolution" CHECK ((resolution_width IS NULL OR resolution_width >= 0) AND (resolution_height IS NULL OR resolution_height >= 0));
ALTER TABLE "omni"."media_video_items" ADD CONSTRAINT "chk_media_video_items_type" CHECK (media_type::text = ANY (ARRAY['MOVIE'::character varying::text, 'EPISODE'::character varying::text]));
ALTER TABLE "omni"."media_video_items" ADD CONSTRAINT "chk_media_video_items_metadata_status" CHECK (metadata_status::text = ANY (ARRAY['PENDING'::character varying::text, 'MATCHED'::character varying::text, 'MANUAL'::character varying::text, 'FAILED'::character varying::text]));

ALTER TABLE "omni"."media_video_items" ADD CONSTRAINT "media_video_items_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_media_watch_history_owner_item" ON "omni"."media_watch_history" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "video_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "played_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_media_watch_history_owner_played" ON "omni"."media_watch_history" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "played_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."media_watch_history" ADD CONSTRAINT "ck_media_watch_history_metadata_json_size" CHECK (octet_length(metadata::text) <= 65536);

ALTER TABLE "omni"."media_watch_history" ADD CONSTRAINT "media_watch_history_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_albums_external_ids" ON "omni"."music_albums" USING gin (
  "external_ids" "pg_catalog"."jsonb_path_ops"
);
CREATE INDEX "idx_music_albums_owner_release" ON "omni"."music_albums" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "release_date" "pg_catalog"."date_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_music_albums_owner_updated" ON "omni"."music_albums" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."music_albums" ADD CONSTRAINT "ck_music_albums_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 524288);
ALTER TABLE "omni"."music_albums" ADD CONSTRAINT "ck_music_albums_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."music_albums" ADD CONSTRAINT "chk_music_albums_total_duration" CHECK (total_duration IS NULL OR total_duration >= 0);
ALTER TABLE "omni"."music_albums" ADD CONSTRAINT "chk_music_albums_track_count" CHECK (track_count >= 0);

ALTER TABLE "omni"."music_albums" ADD CONSTRAINT "music_albums_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_artists_external_ids" ON "omni"."music_artists" USING gin (
  "external_ids" "pg_catalog"."jsonb_path_ops"
);
CREATE INDEX "idx_music_artists_owner_name" ON "omni"."music_artists" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "name" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_music_artists_owner_tracks" ON "omni"."music_artists" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "track_count" "pg_catalog"."int4_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."music_artists" ADD CONSTRAINT "ck_music_artists_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 524288);
ALTER TABLE "omni"."music_artists" ADD CONSTRAINT "ck_music_artists_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."music_artists" ADD CONSTRAINT "chk_music_artists_album_count" CHECK (album_count >= 0);
ALTER TABLE "omni"."music_artists" ADD CONSTRAINT "chk_music_artists_track_count" CHECK (track_count >= 0);

ALTER TABLE "omni"."music_artists" ADD CONSTRAINT "music_artists_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_favorites_owner_created" ON "omni"."music_favorites" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE UNIQUE INDEX "uk_music_favorites_owner_track" ON "omni"."music_favorites" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "track_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."music_favorites" ADD CONSTRAINT "music_favorites_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_play_history_owner_key_played" ON "omni"."music_play_history" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "playable_key" "pg_catalog"."text_ops" ASC NULLS LAST,
  "played_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_music_play_history_owner_played" ON "omni"."music_play_history" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "played_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_music_play_history_owner_track" ON "omni"."music_play_history" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "track_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."music_play_history" ADD CONSTRAINT "music_play_history_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_playlist_items_playlist" ON "omni"."music_playlist_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "playlist_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "sort_order" "pg_catalog"."int4_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_music_playlist_items_track" ON "omni"."music_playlist_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "playlist_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "track_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."music_playlist_items" ADD CONSTRAINT "music_playlist_items_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_playlists_owner_updated" ON "omni"."music_playlists" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."music_playlists" ADD CONSTRAINT "music_playlists_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_scan_jobs_owner_created" ON "omni"."music_scan_jobs" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_music_scan_jobs_task" ON "omni"."music_scan_jobs" USING btree (
  "task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."music_scan_jobs" ADD CONSTRAINT "ck_music_scan_jobs_details_json_size" CHECK (octet_length(details::text) <= 262144);

ALTER TABLE "omni"."music_scan_jobs" ADD CONSTRAINT "music_scan_jobs_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_music_tracks_external_ids" ON "omni"."music_tracks" USING gin (
  "external_ids" "pg_catalog"."jsonb_path_ops"
);
CREATE INDEX "idx_music_tracks_owner_album" ON "omni"."music_tracks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "album_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_music_tracks_owner_artist" ON "omni"."music_tracks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "artist_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_music_tracks_owner_title" ON "omni"."music_tracks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "title" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_music_tracks_owner_updated" ON "omni"."music_tracks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."music_tracks" ADD CONSTRAINT "uniq_music_tracks_file" UNIQUE ("file_node_id");

ALTER TABLE "omni"."music_tracks" ADD CONSTRAINT "ck_music_tracks_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."music_tracks" ADD CONSTRAINT "chk_music_tracks_media_values" CHECK ((duration_seconds IS NULL OR duration_seconds >= 0) AND (bitrate IS NULL OR bitrate >= 0) AND (sample_rate IS NULL OR sample_rate >= 0) AND (file_size IS NULL OR file_size >= 0));
ALTER TABLE "omni"."music_tracks" ADD CONSTRAINT "chk_music_tracks_metadata_status" CHECK (metadata_status::text = ANY (ARRAY['PENDING'::character varying::text, 'MATCHED'::character varying::text, 'MANUAL'::character varying::text, 'FAILED'::character varying::text]));
ALTER TABLE "omni"."music_tracks" ADD CONSTRAINT "chk_music_tracks_numbers" CHECK ((track_number IS NULL OR track_number >= 0) AND (disc_number IS NULL OR disc_number >= 0));
ALTER TABLE "omni"."music_tracks" ADD CONSTRAINT "ck_music_tracks_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 524288);

ALTER TABLE "omni"."music_tracks" ADD CONSTRAINT "music_tracks_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_notification_messages_recipient_created" ON "omni"."notification_messages" USING btree (
  "recipient_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."notification_messages" ADD CONSTRAINT "ck_notification_messages_metadata_json_size" CHECK (octet_length(metadata::text) <= 65536);

ALTER TABLE "omni"."notification_messages" ADD CONSTRAINT "notification_messages_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_notification_types_enabled" ON "omni"."notification_types" USING btree (
  "enabled" "pg_catalog"."bool_ops" ASC NULLS LAST,
  "sort_order" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."notification_types" ADD CONSTRAINT "notification_types_type_code_key" UNIQUE ("type_code");

ALTER TABLE "omni"."notification_types" ADD CONSTRAINT "notification_types_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_album_items_album" ON "omni"."photo_album_items" USING btree (
  "album_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_album_items_photo" ON "omni"."photo_album_items" USING btree (
  "photo_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_album_items" ADD CONSTRAINT "uk_photo_album_items" UNIQUE ("album_id", "photo_id");

ALTER TABLE "omni"."photo_album_items" ADD CONSTRAINT "photo_album_items_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_albums_owner" ON "omni"."photo_albums" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_albums" ADD CONSTRAINT "photo_albums_photo_count_check" CHECK (photo_count >= 0);

ALTER TABLE "omni"."photo_albums" ADD CONSTRAINT "photo_albums_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_batch_tasks_owner" ON "omni"."photo_batch_tasks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_photo_batch_tasks_task" ON "omni"."photo_batch_tasks" USING btree (
  "task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_batch_tasks" ADD CONSTRAINT "ck_photo_batch_tasks_result_json_size" CHECK (octet_length(result::text) <= 1048576);
ALTER TABLE "omni"."photo_batch_tasks" ADD CONSTRAINT "ck_photo_batch_tasks_params_json_size" CHECK (octet_length(params::text) <= 65536);

ALTER TABLE "omni"."photo_batch_tasks" ADD CONSTRAINT "photo_batch_tasks_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_edit_versions_photo" ON "omni"."photo_edit_versions" USING btree (
  "photo_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_edit_versions" ADD CONSTRAINT "ck_photo_edit_versions_params_json_size" CHECK (octet_length(edit_params::text) <= 65536);

ALTER TABLE "omni"."photo_edit_versions" ADD CONSTRAINT "photo_edit_versions_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_face_clusters_owner" ON "omni"."photo_face_clusters" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_face_clusters" ADD CONSTRAINT "photo_face_clusters_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_faces_cluster" ON "omni"."photo_faces" USING btree (
  "cluster_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_faces_owner" ON "omni"."photo_faces" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_faces_photo" ON "omni"."photo_faces" USING btree (
  "photo_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_faces" ADD CONSTRAINT "photo_faces_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_favorites_owner" ON "omni"."photo_favorites" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_favorites_owner_created" ON "omni"."photo_favorites" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_photo_favorites_photo" ON "omni"."photo_favorites" USING btree (
  "photo_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_favorites" ADD CONSTRAINT "uk_photo_favorites" UNIQUE ("owner_user_id", "photo_id");

ALTER TABLE "omni"."photo_favorites" ADD CONSTRAINT "photo_favorites_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_items_date_taken" ON "omni"."photo_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "date_taken" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_photo_items_metadata_status" ON "omni"."photo_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "metadata_status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_items_owner" ON "omni"."photo_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_items_owner_created" ON "omni"."photo_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_photo_items_owner_format" ON "omni"."photo_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "format" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_items_owner_location_city" ON "omni"."photo_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  (gps_location ->> 'city'::text) "pg_catalog"."text_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "uk_photo_items_file_node" UNIQUE ("file_node_id");

ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "ck_photo_items_provider_metadata_json_size" CHECK (octet_length(provider_metadata::text) <= 1048576);
ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "photo_items_iso_check" CHECK (iso >= 0);
ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "photo_items_file_size_check" CHECK (file_size >= 0);
ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "photo_items_metadata_status_check" CHECK (metadata_status::text = ANY (ARRAY['PENDING'::character varying::text, 'MATCHED'::character varying::text, 'FAILED'::character varying::text, 'MANUAL'::character varying::text]));
ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "photo_items_width_check" CHECK (width >= 0);
ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "photo_items_height_check" CHECK (height >= 0);
ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "ck_photo_items_gps_location_json_size" CHECK (octet_length(gps_location::text) <= 65536);

ALTER TABLE "omni"."photo_items" ADD CONSTRAINT "photo_items_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_scan_jobs_owner_created" ON "omni"."photo_scan_jobs" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_photo_scan_jobs_task" ON "omni"."photo_scan_jobs" USING btree (
  "task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."photo_scan_jobs" ADD CONSTRAINT "ck_photo_scan_jobs_details_json_size" CHECK (octet_length(details::text) <= 262144);
ALTER TABLE "omni"."photo_scan_jobs" ADD CONSTRAINT "photo_scan_jobs_status_check" CHECK (status::text = ANY (ARRAY['QUEUED'::character varying::text, 'RUNNING'::character varying::text, 'COMPLETED'::character varying::text, 'FAILED'::character varying::text, 'CANCELLED'::character varying::text, 'DLQ'::character varying::text]));

ALTER TABLE "omni"."photo_scan_jobs" ADD CONSTRAINT "photo_scan_jobs_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_photo_tags_owner_tag" ON "omni"."photo_tags" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "tag" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_photo_tags_owner_tag_created" ON "omni"."photo_tags" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "tag" "pg_catalog"."text_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_photo_tags_photo" ON "omni"."photo_tags" USING btree (
  "photo_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

CREATE INDEX "idx_photo_content_analysis_runs_photo" ON "omni"."photo_content_analysis_runs" USING btree (
  "owner_user_id",
  "photo_id",
  "status",
  "created_at" DESC
);

CREATE INDEX "idx_photo_content_labels_photo" ON "omni"."photo_content_labels" USING btree (
  "owner_user_id",
  "photo_id",
  "state",
  "namespace",
  "label_code"
);

CREATE INDEX "idx_photo_content_labels_run" ON "omni"."photo_content_labels" USING btree (
  "run_id"
);

ALTER TABLE "omni"."photo_tags" ADD CONSTRAINT "uk_photo_tags" UNIQUE ("owner_user_id", "photo_id", "tag");

ALTER TABLE "omni"."photo_tags" ADD CONSTRAINT "photo_tags_pkey" PRIMARY KEY ("id");

ALTER TABLE "omni"."photo_content_analysis_runs" ADD CONSTRAINT "photo_content_analysis_runs_pkey" PRIMARY KEY ("id");
ALTER TABLE "omni"."photo_content_analysis_runs" ADD CONSTRAINT "photo_content_analysis_runs_status_check"
    CHECK ("status"::text = ANY (ARRAY['RUNNING'::character varying::text, 'SUCCEEDED'::character varying::text,
        'FAILED'::character varying::text, 'SUPERSEDED'::character varying::text]));
ALTER TABLE "omni"."photo_content_labels" ADD CONSTRAINT "photo_content_labels_pkey" PRIMARY KEY ("id");
ALTER TABLE "omni"."photo_content_labels" ADD CONSTRAINT "photo_content_labels_namespace_check"
    CHECK ("namespace"::text = ANY (ARRAY['SUBJECT'::character varying::text, 'SCENE'::character varying::text,
        'STYLE'::character varying::text, 'FACE'::character varying::text, 'TECHNICAL'::character varying::text]));
ALTER TABLE "omni"."photo_content_labels" ADD CONSTRAINT "photo_content_labels_state_check"
    CHECK ("state"::text = ANY (ARRAY['AUTO'::character varying::text, 'CANDIDATE'::character varying::text,
        'CONFIRMED'::character varying::text, 'REJECTED'::character varying::text]));
ALTER TABLE "omni"."photo_content_labels" ADD CONSTRAINT "photo_content_labels_confidence_check"
    CHECK ("confidence" >= 0 AND "confidence" <= 1);
ALTER TABLE "omni"."photo_content_labels" ADD CONSTRAINT "photo_content_labels_boxes_json_size"
    CHECK (octet_length("boxes"::text) <= 65536);

CREATE INDEX "idx_reader_annotations_item" ON "omni"."reader_annotations" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_annotations_item_chapter" ON "omni"."reader_annotations" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "chapter_id" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_reader_annotations_client_operation" ON "omni"."reader_annotations" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "client_operation_id" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE client_operation_id IS NOT NULL;

ALTER TABLE "omni"."reader_annotations" ADD CONSTRAINT "reader_annotations_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_bookmarks_item" ON "omni"."reader_bookmarks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_reader_bookmarks_client_operation" ON "omni"."reader_bookmarks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "client_operation_id" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE client_operation_id IS NOT NULL;

ALTER TABLE "omni"."reader_bookmarks" ADD CONSTRAINT "reader_bookmarks_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_bookshelf_owner" ON "omni"."reader_bookshelf" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."reader_bookshelf" ADD CONSTRAINT "uniq_reader_bookshelf_owner_item" UNIQUE ("owner_user_id", "reader_item_id");

ALTER TABLE "omni"."reader_bookshelf" ADD CONSTRAINT "reader_bookshelf_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_catalog_nodes_item" ON "omni"."reader_catalog_nodes" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_catalog_nodes_key" ON "omni"."reader_catalog_nodes" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "catalog_key" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_catalog_nodes_parent" ON "omni"."reader_catalog_nodes" USING btree (
  "parent_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_catalog_nodes_source" ON "omni"."reader_catalog_nodes" USING btree (
  "source_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."reader_catalog_nodes" ADD CONSTRAINT "reader_catalog_nodes_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_item_sources_item" ON "omni"."reader_item_sources" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."reader_item_sources" ADD CONSTRAINT "uq_reader_item_sources_item_file" UNIQUE ("reader_item_id", "file_node_id");

ALTER TABLE "omni"."reader_item_sources" ADD CONSTRAINT "reader_item_sources_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_items_content_hash" ON "omni"."reader_items" USING btree (
  "content_hash" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE content_hash IS NOT NULL;
CREATE INDEX "idx_reader_items_owner_title" ON "omni"."reader_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "title" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_items_owner_type" ON "omni"."reader_items" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "item_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."reader_items" ADD CONSTRAINT "uniq_reader_items_owner_file" UNIQUE ("owner_user_id", "file_node_id");

ALTER TABLE "omni"."reader_items" ADD CONSTRAINT "ck_reader_items_genres_json_size" CHECK (octet_length(genres::text) <= 65536);
ALTER TABLE "omni"."reader_items" ADD CONSTRAINT "ck_reader_items_external_ids_json_size" CHECK (octet_length(external_ids::text) <= 65536);
ALTER TABLE "omni"."reader_items" ADD CONSTRAINT "reader_items_content_kind_check" CHECK (content_kind::text = ANY (ARRAY['TEXT'::character varying, 'COMIC'::character varying]::text[]));
ALTER TABLE "omni"."reader_items" ADD CONSTRAINT "reader_items_item_type_check" CHECK (item_type::text = ANY (ARRAY['EPUB'::character varying::text, 'TXT'::character varying::text, 'CBZ'::character varying::text, 'ZIP'::character varying::text, 'PDF'::character varying::text]));
ALTER TABLE "omni"."reader_items" ADD CONSTRAINT "chk_reader_items_rating" CHECK (rating IS NULL OR rating >= 0::numeric AND rating <= 10::numeric);

ALTER TABLE "omni"."reader_items" ADD CONSTRAINT "reader_items_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_text_chapters_item" ON "omni"."reader_text_chapters" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "chapter_index" "pg_catalog"."int4_ops" ASC NULLS LAST
);
ALTER TABLE "omni"."reader_text_chapters" ADD CONSTRAINT "uniq_reader_text_chapters_item_index"
  UNIQUE ("reader_item_id", "chapter_index");
ALTER TABLE "omni"."reader_text_chapters" ADD CONSTRAINT "uniq_reader_text_chapters_item_key"
  UNIQUE ("reader_item_id", "chapter_key");
ALTER TABLE "omni"."reader_text_chapters" ADD CONSTRAINT "chk_reader_text_chapters_offsets"
  CHECK (source_start_offset IS NULL OR source_end_offset IS NULL OR source_end_offset >= source_start_offset);
ALTER TABLE "omni"."reader_text_chapters" ADD CONSTRAINT "reader_text_chapters_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_notes_item" ON "omni"."reader_notes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_reader_notes_client_operation" ON "omni"."reader_notes" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "client_operation_id" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE client_operation_id IS NOT NULL;

ALTER TABLE "omni"."reader_notes" ADD CONSTRAINT "reader_notes_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_page_assets_item" ON "omni"."reader_page_assets" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_page_assets_source" ON "omni"."reader_page_assets" USING btree (
  "source_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_reader_page_assets_page_version" ON "omni"."reader_page_assets" USING btree (
  "page_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "manifest_version" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."reader_page_assets" ADD CONSTRAINT "reader_page_assets_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_pages_catalog" ON "omni"."reader_pages" USING btree (
  "catalog_node_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_pages_catalog_key" ON "omni"."reader_pages" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "catalog_key" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_pages_item" ON "omni"."reader_pages" USING btree (
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_pages_source" ON "omni"."reader_pages" USING btree (
  "source_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reader_pages_source_page" ON "omni"."reader_pages" USING btree (
  "source_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "source_page_index" "pg_catalog"."int4_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."reader_pages" ADD CONSTRAINT "reader_pages_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reader_progress_owner" ON "omni"."reader_progress" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."reader_progress" ADD CONSTRAINT "uniq_reader_progress_owner_item" UNIQUE ("owner_user_id", "reader_item_id");

ALTER TABLE "omni"."reader_progress" ADD CONSTRAINT "chk_reader_progress_mode" CHECK (reading_mode::text = ANY (ARRAY['scroll'::character varying, 'page'::character varying]::text[]));
ALTER TABLE "omni"."reader_progress" ADD CONSTRAINT "chk_reader_progress_range" CHECK (progress_percent >= 0::numeric AND progress_percent <= 1::numeric);

ALTER TABLE "omni"."reader_progress" ADD CONSTRAINT "reader_progress_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_reading_sessions_item" ON "omni"."reader_reading_sessions" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "reader_item_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_reading_sessions_user" ON "omni"."reader_reading_sessions" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "started_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uk_reading_sessions_client_session" ON "omni"."reader_reading_sessions" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "client_session_id" "pg_catalog"."text_ops" ASC NULLS LAST
) WHERE client_session_id IS NOT NULL;

ALTER TABLE "omni"."reader_reading_sessions" ADD CONSTRAINT "reader_reading_sessions_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_search_index_states_owner" ON "omni"."search_index_states" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."search_index_states" ADD CONSTRAINT "search_index_states_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_share_links_owner_created" ON "omni"."share_links" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);

ALTER TABLE "omni"."share_links" ADD CONSTRAINT "uniq_share_links_token_hash" UNIQUE ("token_hash");

ALTER TABLE "omni"."share_links" ADD CONSTRAINT "share_links_pkey" PRIMARY KEY ("id");

ALTER TABLE "omni"."shared_space_permissions" ADD CONSTRAINT "uk_shared_space_permissions_role" UNIQUE ("role_id");

ALTER TABLE "omni"."shared_space_permissions" ADD CONSTRAINT "pk_shared_space_permissions" PRIMARY KEY ("id");

ALTER TABLE "omni"."shared_space_usage" ADD CONSTRAINT "pk_shared_space_usage" PRIMARY KEY ("id");

CREATE INDEX "idx_storage_external_accounts_owner" ON "omni"."storage_external_accounts" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."storage_external_accounts" ADD CONSTRAINT "storage_external_accounts_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_import_tasks_owner" ON "omni"."storage_import_tasks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_import_tasks_status" ON "omni"."storage_import_tasks" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_import_tasks_task" ON "omni"."storage_import_tasks" USING btree (
  "task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."storage_import_tasks" ADD CONSTRAINT "storage_import_tasks_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_metadata_cache_account_path" ON "omni"."storage_remote_metadata_cache" USING btree (
  "external_account_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "remote_path" "pg_catalog"."text_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."storage_remote_metadata_cache" ADD CONSTRAINT "ck_storage_remote_metadata_json_size" CHECK (octet_length(metadata_json::text) <= 1048576);

ALTER TABLE "omni"."storage_remote_metadata_cache" ADD CONSTRAINT "storage_remote_metadata_cache_pkey" PRIMARY KEY ("id");

CREATE UNIQUE INDEX "uq_sync_event_checkpoints_key" ON "omni"."sync_event_checkpoints" USING btree (
  "checkpoint_key" "pg_catalog"."text_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."sync_event_checkpoints" ADD CONSTRAINT "ck_sync_event_checkpoints_sequence" CHECK (sequence_no >= 0);

ALTER TABLE "omni"."sync_event_checkpoints" ADD CONSTRAINT "sync_event_checkpoints_pkey" PRIMARY KEY ("id");


CREATE INDEX "idx_sync_events_publish_available" ON "omni"."sync_events" USING btree (
  "publish_status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "available_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST,
  "sequence_no" "pg_catalog"."int8_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sync_events_publish_created" ON "omni"."sync_events" USING btree (
  "publish_status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "created_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sync_events_publish_locked" ON "omni"."sync_events" USING btree (
  "publish_status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "locked_until" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sync_events_recipient_sequence" ON "omni"."sync_events" USING btree (
  "recipient_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "sequence_no" "pg_catalog"."int8_ops" ASC NULLS LAST
);
CREATE UNIQUE INDEX "uq_sync_events_sequence_no" ON "omni"."sync_events" USING btree (
  "sequence_no" "pg_catalog"."int8_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."sync_events" ADD CONSTRAINT "ck_sync_events_publish_attempts" CHECK (publish_attempts >= 0);
ALTER TABLE "omni"."sync_events" ADD CONSTRAINT "ck_sync_events_publish_status" CHECK (publish_status::text = ANY (ARRAY['PENDING'::character varying, 'PUBLISHING'::character varying, 'PUBLISHED'::character varying]::text[]));
ALTER TABLE "omni"."sync_events" ADD CONSTRAINT "ck_sync_events_payload_json_size" CHECK (octet_length(payload::text) <= 65536);

ALTER TABLE "omni"."sync_events" ADD CONSTRAINT "sync_events_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_sys_tasks_created" ON "omni"."sys_tasks" USING btree (
  "created_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_sys_tasks_owner" ON "omni"."sys_tasks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sys_tasks_status" ON "omni"."sys_tasks" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sys_tasks_status_updated" ON "omni"."sys_tasks" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sys_tasks_type_status" ON "omni"."sys_tasks" USING btree (
  "task_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sys_tasks_resource" ON "omni"."sys_tasks" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "task_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "resource_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "resource_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "updated_at" "pg_catalog"."timestamptz_ops" DESC NULLS FIRST
);
CREATE INDEX "idx_sys_tasks_retry" ON "omni"."sys_tasks" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "next_retry_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sys_tasks_heartbeat" ON "omni"."sys_tasks" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "heartbeat_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."sys_tasks" ADD CONSTRAINT "ck_sys_tasks_result_json_size" CHECK (octet_length(result) <= 1048576);
ALTER TABLE "omni"."sys_tasks" ADD CONSTRAINT "ck_sys_tasks_error_summary_json_size" CHECK (octet_length(error_summary) <= 65536);
ALTER TABLE "omni"."sys_tasks" ADD CONSTRAINT "ck_sys_tasks_payload_json_size" CHECK (octet_length(payload) <= 262144);

ALTER TABLE "omni"."sys_tasks" ADD CONSTRAINT "sys_tasks_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_sys_task_dispatches_available" ON "omni"."sys_task_dispatches" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "next_attempt_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sys_task_dispatches_lease" ON "omni"."sys_task_dispatches" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "locked_until" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
CREATE INDEX "idx_sys_task_dispatches_task" ON "omni"."sys_task_dispatches" USING btree (
  "task_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
ALTER TABLE "omni"."sys_task_dispatches" ADD CONSTRAINT "chk_sys_task_dispatches_status" CHECK (status::text = ANY (ARRAY['PENDING'::character varying::text, 'PUBLISHING'::character varying::text, 'PUBLISHED'::character varying::text]));
ALTER TABLE "omni"."sys_task_dispatches" ADD CONSTRAINT "sys_task_dispatches_pkey" PRIMARY KEY ("id");

CREATE INDEX "idx_user_prefs_owner" ON "omni"."user_preferences" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);

ALTER TABLE "omni"."user_preferences" ADD CONSTRAINT "uniq_user_prefs_owner_scope" UNIQUE ("owner_user_id", "scope");

ALTER TABLE "omni"."user_preferences" ADD CONSTRAINT "ck_user_preferences_json_size" CHECK (octet_length(preferences::text) <= 65536);

ALTER TABLE "omni"."user_preferences" ADD CONSTRAINT "user_preferences_pkey" PRIMARY KEY ("id");

CREATE UNIQUE INDEX "uq_storage_quota_reservations_source" ON "omni"."storage_quota_reservations" USING btree (
  "source_type" "pg_catalog"."text_ops" ASC NULLS LAST,
  "source_id" "pg_catalog"."uuid_ops" ASC NULLS LAST
);
CREATE INDEX "idx_storage_quota_reservations_owner_status" ON "omni"."storage_quota_reservations" USING btree (
  "owner_user_id" "pg_catalog"."uuid_ops" ASC NULLS LAST,
  "status" "pg_catalog"."text_ops" ASC NULLS LAST
);
CREATE INDEX "idx_storage_quota_reservations_expiry" ON "omni"."storage_quota_reservations" USING btree (
  "status" "pg_catalog"."text_ops" ASC NULLS LAST,
  "expires_at" "pg_catalog"."timestamptz_ops" ASC NULLS LAST
);
ALTER TABLE "omni"."storage_quota_reservations" ADD CONSTRAINT "chk_storage_quota_reservations_bytes" CHECK (
  reserved_bytes >= 0 AND committed_bytes >= 0 AND committed_bytes <= reserved_bytes
);
ALTER TABLE "omni"."storage_quota_reservations" ADD CONSTRAINT "chk_storage_quota_reservations_status" CHECK (
  status::text = ANY (ARRAY['RESERVED'::character varying, 'COMMITTED'::character varying, 'RELEASED'::character varying, 'EXPIRED'::character varying]::text[])
);
ALTER TABLE "omni"."storage_quota_reservations" ADD CONSTRAINT "storage_quota_reservations_pkey" PRIMARY KEY ("id");

CREATE TABLE "omni"."system_instances" (
  "id" uuid NOT NULL,
  "installation_id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "setup_state" varchar(32) NOT NULL DEFAULT 'SETUP_REQUIRED',
  "instance_name" varchar(120) NOT NULL DEFAULT 'OmniNest',
  "default_locale" varchar(20) NOT NULL DEFAULT 'zh-CN',
  "default_timezone" varchar(64) NOT NULL DEFAULT 'Asia/Shanghai',
  "setup_completed_by" uuid,
  "setup_completed_at" timestamptz(6),
  "created_at" timestamptz(6) NOT NULL DEFAULT now(),
  "updated_at" timestamptz(6) NOT NULL DEFAULT now(),
  "version" int8 NOT NULL DEFAULT 0,
  CONSTRAINT "system_instances_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "uniq_system_instances_installation_id" UNIQUE ("installation_id"),
  CONSTRAINT "chk_system_instances_setup_state"
    CHECK ("setup_state" IN ('SETUP_REQUIRED', 'READY'))
);

COMMENT ON TABLE "omni"."system_instances" IS '系统实例单例表，保存首次安装完成状态和实例基础信息';
COMMENT ON COLUMN "omni"."system_instances"."id" IS '系统实例单例主键';
COMMENT ON COLUMN "omni"."system_instances"."installation_id" IS '部署实例的稳定公开标识';
COMMENT ON COLUMN "omni"."system_instances"."setup_state" IS '首次安装状态';
COMMENT ON COLUMN "omni"."system_instances"."instance_name" IS '部署实例展示名称';
COMMENT ON COLUMN "omni"."system_instances"."default_locale" IS '实例默认语言区域';
COMMENT ON COLUMN "omni"."system_instances"."default_timezone" IS '实例默认时区';
COMMENT ON COLUMN "omni"."system_instances"."setup_completed_by" IS '完成首次安装的超级管理员标识';
COMMENT ON COLUMN "omni"."system_instances"."setup_completed_at" IS '首次安装完成时间';
COMMENT ON COLUMN "omni"."system_instances"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."system_instances"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."system_instances"."version" IS '乐观锁版本号';

-- 基线表与字段注释补全。
COMMENT ON COLUMN "omni"."auth_active_sessions"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."auth_login_audit"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_move_records"."id" IS '移动记录唯一标识，主键';
COMMENT ON COLUMN "omni"."file_move_records"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_nodes"."shared" IS '是否已通过共享链接或定向授权共享';
COMMENT ON COLUMN "omni"."file_nodes"."shared_at" IS '最近一次启用共享的时间';
COMMENT ON COLUMN "omni"."file_purge_entries"."id" IS '永久删除清单条目唯一标识，主键';
COMMENT ON COLUMN "omni"."file_purge_entries"."owner_user_id" IS '条目所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."file_purge_entries"."file_node_id" IS '来源文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."file_purge_entries"."object_id" IS '文件对象ID，关联file_objects';
COMMENT ON COLUMN "omni"."file_purge_entries"."bucket_name" IS '待删除对象所在存储桶';
COMMENT ON COLUMN "omni"."file_purge_entries"."object_key" IS '待删除对象键';
COMMENT ON COLUMN "omni"."file_purge_entries"."minio_version_id" IS '待删除的MinIO对象版本ID';
COMMENT ON COLUMN "omni"."file_purge_entries"."attempt_count" IS '对象删除尝试次数';
COMMENT ON COLUMN "omni"."file_purge_entries"."last_error_code" IS '最近一次删除失败的稳定错误码';
COMMENT ON COLUMN "omni"."file_purge_entries"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."file_purge_entries"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."file_purge_entries"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."integration_accounts"."id" IS '外部平台账号映射唯一标识，主键';
COMMENT ON COLUMN "omni"."integration_accounts"."external_user_id" IS '外部平台用户标识';
COMMENT ON COLUMN "omni"."integration_accounts"."display_name" IS '外部平台展示名称';
COMMENT ON COLUMN "omni"."integration_accounts"."avatar_url" IS '外部平台头像地址';
COMMENT ON COLUMN "omni"."integration_accounts"."status" IS '账号映射状态';
COMMENT ON COLUMN "omni"."integration_accounts"."last_verified_at" IS '最近一次凭据验证时间';
COMMENT ON COLUMN "omni"."integration_accounts"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."integration_accounts"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."integration_accounts"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."media_video_items"."duration_seconds" IS '视频时长，单位为秒';

COMMENT ON TABLE "omni"."photo_album_items" IS '相册照片关联表，保存照片在相册中的顺序';
COMMENT ON COLUMN "omni"."photo_album_items"."id" IS '相册照片关联唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_album_items"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_album_items"."album_id" IS '相册ID，关联photo_albums';
COMMENT ON COLUMN "omni"."photo_album_items"."photo_id" IS '照片ID，关联photo_items';
COMMENT ON COLUMN "omni"."photo_album_items"."sort_order" IS '照片在相册中的排序值';
COMMENT ON COLUMN "omni"."photo_album_items"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_album_items"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."photo_albums" IS '照片相册表，保存用户维护的照片集合';
COMMENT ON COLUMN "omni"."photo_albums"."id" IS '相册唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_albums"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_albums"."name" IS '相册名称';
COMMENT ON COLUMN "omni"."photo_albums"."description" IS '相册描述';
COMMENT ON COLUMN "omni"."photo_albums"."cover_file_id" IS '相册封面文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."photo_albums"."photo_count" IS '相册当前照片数量';
COMMENT ON COLUMN "omni"."photo_albums"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_albums"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."photo_albums"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."photo_batch_tasks" IS '照片批量处理任务表，记录批量操作进度与结果';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."id" IS '照片批量任务唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."task_type" IS '批量任务类型';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."status" IS '任务状态';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."total_items" IS '待处理照片总数';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."processed_items" IS '已处理照片数量';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."params" IS '任务参数，JSONB格式';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."result" IS '任务结果摘要，JSONB格式';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."error_message" IS '任务失败摘要';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."photo_batch_tasks"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."photo_edit_versions" IS '照片编辑版本表，保存非破坏性编辑参数和派生文件';
COMMENT ON COLUMN "omni"."photo_edit_versions"."id" IS '照片编辑版本唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_edit_versions"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_edit_versions"."photo_id" IS '照片ID，关联photo_items';
COMMENT ON COLUMN "omni"."photo_edit_versions"."version_number" IS '照片编辑版本序号';
COMMENT ON COLUMN "omni"."photo_edit_versions"."edit_type" IS '编辑类型';
COMMENT ON COLUMN "omni"."photo_edit_versions"."edit_params" IS '编辑参数，JSONB格式';
COMMENT ON COLUMN "omni"."photo_edit_versions"."file_id" IS '编辑结果文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."photo_edit_versions"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_edit_versions"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."photo_face_clusters" IS '照片人脸聚类表，保存同一人物的人脸集合';
COMMENT ON COLUMN "omni"."photo_face_clusters"."id" IS '人脸聚类唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_face_clusters"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_face_clusters"."name" IS '人物显示名称';
COMMENT ON COLUMN "omni"."photo_face_clusters"."cover_face_id" IS '聚类封面人脸ID，关联photo_faces';
COMMENT ON COLUMN "omni"."photo_face_clusters"."face_count" IS '聚类包含的人脸数量';
COMMENT ON COLUMN "omni"."photo_face_clusters"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_face_clusters"."updated_at" IS '更新时间';

COMMENT ON TABLE "omni"."photo_faces" IS '照片人脸检测结果表，保存位置、特征向量和聚类关系';
COMMENT ON COLUMN "omni"."photo_faces"."id" IS '人脸检测结果唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_faces"."photo_id" IS '照片ID，关联photo_items';
COMMENT ON COLUMN "omni"."photo_faces"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_faces"."bbox_x" IS '人脸边界框左上角横坐标比例';
COMMENT ON COLUMN "omni"."photo_faces"."bbox_y" IS '人脸边界框左上角纵坐标比例';
COMMENT ON COLUMN "omni"."photo_faces"."bbox_w" IS '人脸边界框宽度比例';
COMMENT ON COLUMN "omni"."photo_faces"."bbox_h" IS '人脸边界框高度比例';
COMMENT ON COLUMN "omni"."photo_faces"."embedding" IS '人脸特征向量';
COMMENT ON COLUMN "omni"."photo_faces"."cluster_id" IS '所属人脸聚类ID，关联photo_face_clusters';
COMMENT ON COLUMN "omni"."photo_faces"."created_at" IS '创建时间';

COMMENT ON TABLE "omni"."photo_favorites" IS '照片收藏表，保存用户收藏的照片';
COMMENT ON COLUMN "omni"."photo_favorites"."id" IS '照片收藏唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_favorites"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_favorites"."photo_id" IS '照片ID，关联photo_items';
COMMENT ON COLUMN "omni"."photo_favorites"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_favorites"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."photo_items" IS '照片条目表，保存文件引用、拍摄参数、定位和元数据状态';
COMMENT ON COLUMN "omni"."photo_items"."id" IS '照片唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_items"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_items"."file_node_id" IS '原始照片文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."photo_items"."title" IS '照片标题';
COMMENT ON COLUMN "omni"."photo_items"."description" IS '照片描述';
COMMENT ON COLUMN "omni"."photo_items"."width" IS '照片像素宽度';
COMMENT ON COLUMN "omni"."photo_items"."height" IS '照片像素高度';
COMMENT ON COLUMN "omni"."photo_items"."orientation" IS 'EXIF方向值';
COMMENT ON COLUMN "omni"."photo_items"."date_taken" IS '照片拍摄时间';
COMMENT ON COLUMN "omni"."photo_items"."camera_make" IS '相机制造商';
COMMENT ON COLUMN "omni"."photo_items"."camera_model" IS '相机型号';
COMMENT ON COLUMN "omni"."photo_items"."aperture" IS '拍摄光圈值';
COMMENT ON COLUMN "omni"."photo_items"."shutter_speed" IS '拍摄快门速度';
COMMENT ON COLUMN "omni"."photo_items"."iso" IS '拍摄ISO感光度';
COMMENT ON COLUMN "omni"."photo_items"."focal_length" IS '拍摄焦距';
COMMENT ON COLUMN "omni"."photo_items"."gps_latitude" IS 'GPS纬度';
COMMENT ON COLUMN "omni"."photo_items"."gps_longitude" IS 'GPS经度';
COMMENT ON COLUMN "omni"."photo_items"."format" IS '照片文件格式';
COMMENT ON COLUMN "omni"."photo_items"."file_size" IS '照片文件字节数';
COMMENT ON COLUMN "omni"."photo_items"."cover_file_id" IS '展示缩略图或封面文件节点ID';
COMMENT ON COLUMN "omni"."photo_items"."metadata_status" IS '元数据处理状态';
COMMENT ON COLUMN "omni"."photo_items"."provider_metadata" IS '解析器或外部提供方元数据，JSONB格式';
COMMENT ON COLUMN "omni"."photo_items"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_items"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."photo_items"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."photo_items"."flash" IS '闪光灯模式或状态';
COMMENT ON COLUMN "omni"."photo_items"."white_balance" IS '白平衡模式';
COMMENT ON COLUMN "omni"."photo_items"."metering_mode" IS '测光模式';
COMMENT ON COLUMN "omni"."photo_items"."lens_model" IS '镜头型号';
COMMENT ON COLUMN "omni"."photo_items"."gps_location" IS '照片地理位置 JSON，保存 GPS 反向地理编码结果';

COMMENT ON TABLE "omni"."photo_scan_jobs" IS '照片库扫描任务表，记录扫描进度和执行结果';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."id" IS '照片扫描任务唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."status" IS '扫描任务状态';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."scanned_files" IS '已扫描文件数量';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."message" IS '当前阶段简要说明';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."details" IS '扫描详情，JSONB格式';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."photo_scan_jobs"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."geo_dataset" IS 'GeoNames 离线地理数据集版本表，管理导入、验证与发布生命周期';
COMMENT ON COLUMN "omni"."geo_dataset"."id" IS '数据集唯一标识，主键';
COMMENT ON COLUMN "omni"."geo_dataset"."dataset_version" IS '数据集版本号，全局唯一';
COMMENT ON COLUMN "omni"."geo_dataset"."source_dump_date" IS 'GeoNames dump 日期';
COMMENT ON COLUMN "omni"."geo_dataset"."dataset_type" IS '数据集类型，如 cities5000';
COMMENT ON COLUMN "omni"."geo_dataset"."source_hash" IS '源文件摘要，用于追溯';
COMMENT ON COLUMN "omni"."geo_dataset"."status" IS '数据集状态：IMPORTING / READY / PUBLISHED / ARCHIVED / FAILED';
COMMENT ON COLUMN "omni"."geo_dataset"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."geo_dataset"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."geo_dataset"."published_at" IS '发布时间';
COMMENT ON COLUMN "omni"."geo_dataset"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."geo_cities" IS 'GeoNames 城市表，按数据集分版本保存城市双语名称与坐标';
COMMENT ON COLUMN "omni"."geo_cities"."dataset_id" IS '所属数据集ID，关联geo_dataset';
COMMENT ON COLUMN "omni"."geo_cities"."geoname_id" IS 'GeoNames 城市唯一ID';
COMMENT ON COLUMN "omni"."geo_cities"."name" IS 'GeoNames 主名称';
COMMENT ON COLUMN "omni"."geo_cities"."name_zh" IS '城市中文名，选优自 alternateNames';
COMMENT ON COLUMN "omni"."geo_cities"."country_code" IS 'ISO 国家码';
COMMENT ON COLUMN "omni"."geo_cities"."country_name_en" IS '国家英文名';
COMMENT ON COLUMN "omni"."geo_cities"."country_name_zh" IS '国家中文名';
COMMENT ON COLUMN "omni"."geo_cities"."province_name_en" IS '一级行政区英文名';
COMMENT ON COLUMN "omni"."geo_cities"."province_name_zh" IS '一级行政区中文名';
COMMENT ON COLUMN "omni"."geo_cities"."latitude" IS '纬度';
COMMENT ON COLUMN "omni"."geo_cities"."longitude" IS '经度';
COMMENT ON COLUMN "omni"."geo_cities"."population" IS '人口数量';
COMMENT ON COLUMN "omni"."geo_cities"."feature_code" IS 'GeoNames 地物类型代码';
COMMENT ON COLUMN "omni"."geo_cities"."created_at" IS '创建时间';

COMMENT ON TABLE "omni"."photo_tags" IS '照片标签表，保存人工或自动生成的标签';
COMMENT ON COLUMN "omni"."photo_tags"."id" IS '照片标签唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_tags"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_tags"."photo_id" IS '照片ID，关联photo_items';
COMMENT ON COLUMN "omni"."photo_tags"."tag" IS '标签文本';
COMMENT ON COLUMN "omni"."photo_tags"."created_at" IS '创建时间';

COMMENT ON TABLE "omni"."photo_content_analysis_runs" IS '照片图像分析运行记录，保存分析版本、状态和失败信息';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."id" IS '图像分析运行唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."photo_id" IS '照片ID，关联photo_items';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."content_hash" IS '分析输入内容摘要，用于幂等和重分析判断';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."pipeline_version" IS '图像分析流水线版本';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."status" IS '分析状态：运行中、成功、失败或已被新运行替代';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."error_code" IS '分析失败稳定错误码';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."error_message" IS '分析失败摘要，不保存完整堆栈';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."started_at" IS '分析开始时间';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."completed_at" IS '分析完成时间';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."photo_content_analysis_runs"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."photo_content_labels" IS '照片图像分析自动标签，按主体、场景、风格等命名空间保存';
COMMENT ON COLUMN "omni"."photo_content_labels"."id" IS '图像分析标签唯一标识，主键';
COMMENT ON COLUMN "omni"."photo_content_labels"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."photo_content_labels"."photo_id" IS '照片ID，关联photo_items';
COMMENT ON COLUMN "omni"."photo_content_labels"."run_id" IS '分析运行ID，关联photo_content_analysis_runs';
COMMENT ON COLUMN "omni"."photo_content_labels"."namespace" IS '标签命名空间：主体、场景、风格、人脸或技术属性';
COMMENT ON COLUMN "omni"."photo_content_labels"."label_code" IS '稳定标签编码';
COMMENT ON COLUMN "omni"."photo_content_labels"."confidence" IS '模型置信度，范围为0到1';
COMMENT ON COLUMN "omni"."photo_content_labels"."source" IS '产生标签的检测器或模型';
COMMENT ON COLUMN "omni"."photo_content_labels"."model_version" IS '模型版本';
COMMENT ON COLUMN "omni"."photo_content_labels"."boxes" IS '归一化边界框数组，JSONB格式';
COMMENT ON COLUMN "omni"."photo_content_labels"."state" IS '标签状态：自动、候选、已确认或已拒绝';
COMMENT ON COLUMN "omni"."photo_content_labels"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."photo_content_labels"."updated_at" IS '更新时间';

COMMENT ON COLUMN "omni"."reader_annotations"."id" IS '阅读批注唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_annotations"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."reader_annotations"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_annotations"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_annotations"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."reader_annotations"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."reader_bookmarks"."id" IS '阅读书签唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_bookmarks"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."reader_bookmarks"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_bookmarks"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_bookshelf"."id" IS '书架关联唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_bookshelf"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."reader_bookshelf"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_bookshelf"."created_at" IS '加入书架时间';

COMMENT ON TABLE "omni"."reader_catalog_nodes" IS '阅读目录节点表，保存书籍和漫画的层级目录及页面范围';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."id" IS '目录节点唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."parent_id" IS '父目录节点ID，根节点时为空';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."node_type" IS '目录节点类型';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."title" IS '目录节点标题';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."sort_index" IS '同级目录排序值';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."page_count" IS '目录节点包含的页面数量';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."source_id" IS '漫画来源ID，关联reader_item_sources';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."catalog_key" IS '来源内稳定目录键';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."page_start_index" IS '目录覆盖的全局起始页索引';
COMMENT ON COLUMN "omni"."reader_catalog_nodes"."page_end_index" IS '目录覆盖的全局结束页索引';

COMMENT ON TABLE "omni"."reader_item_sources" IS '阅读条目来源表，保存多卷、多章节文件和解析生命周期';
COMMENT ON COLUMN "omni"."reader_item_sources"."id" IS '阅读来源唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_item_sources"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_item_sources"."file_node_id" IS '原始来源文件节点ID，关联file_nodes';
COMMENT ON COLUMN "omni"."reader_item_sources"."content_hash" IS '来源文件内容摘要';
COMMENT ON COLUMN "omni"."reader_item_sources"."file_format" IS '来源文件格式';
COMMENT ON COLUMN "omni"."reader_item_sources"."source_name" IS '来源显示名称';
COMMENT ON COLUMN "omni"."reader_item_sources"."page_count" IS '来源解析出的页面数量';
COMMENT ON COLUMN "omni"."reader_item_sources"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_item_sources"."source_sort_key" IS '多来源合并时的稳定排序键';
COMMENT ON COLUMN "omni"."reader_item_sources"."status" IS '解析状态：PENDING / PARSING / READY / FAILED';
COMMENT ON COLUMN "omni"."reader_item_sources"."error_code" IS '解析失败的稳定错误码';
COMMENT ON COLUMN "omni"."reader_item_sources"."error_message" IS '解析失败的有界摘要';
COMMENT ON COLUMN "omni"."reader_item_sources"."retry_count" IS '解析任务重试次数';
COMMENT ON COLUMN "omni"."reader_item_sources"."season_no" IS '来源所属季编号';
COMMENT ON COLUMN "omni"."reader_item_sources"."volume_no" IS '来源所属卷编号';
COMMENT ON COLUMN "omni"."reader_item_sources"."chapter_start" IS '来源覆盖的起始章节编号';
COMMENT ON COLUMN "omni"."reader_item_sources"."chapter_end" IS '来源覆盖的结束章节编号';
COMMENT ON COLUMN "omni"."reader_item_sources"."extra_order" IS '无法归入季卷章节时的附加排序值';
COMMENT ON COLUMN "omni"."reader_item_sources"."reading_direction" IS '漫画阅读方向：LTR / RTL / VERTICAL';

COMMENT ON COLUMN "omni"."reader_items"."id" IS '阅读条目唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_items"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."reader_items"."content_hash" IS '主来源内容摘要';
COMMENT ON COLUMN "omni"."reader_items"."title" IS '书籍或漫画标题';
COMMENT ON COLUMN "omni"."reader_items"."author_name" IS '作者名称';
COMMENT ON COLUMN "omni"."reader_items"."description" IS '内容简介';
COMMENT ON COLUMN "omni"."reader_items"."publisher" IS '出版方名称';
COMMENT ON COLUMN "omni"."reader_items"."language" IS '内容语言';
COMMENT ON COLUMN "omni"."reader_items"."release_date" IS '出版或发行日期';
COMMENT ON COLUMN "omni"."reader_items"."rating" IS '用户或外部元数据评分';
COMMENT ON COLUMN "omni"."reader_items"."genres" IS '题材分类集合，JSONB格式';
COMMENT ON COLUMN "omni"."reader_items"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_items"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."reader_items"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."reader_items"."content_kind" IS '内容形态：TEXT / COMIC';
COMMENT ON COLUMN "omni"."reader_items"."manifest_version" IS '当前可用解析清单版本号';
COMMENT ON COLUMN "omni"."reader_items"."import_status" IS '导入解析状态';
COMMENT ON COLUMN "omni"."reader_items"."parse_error_code" IS '最近一次解析失败的稳定错误码';
COMMENT ON COLUMN "omni"."reader_items"."parse_error_message" IS '最近一次解析失败的有界摘要';
COMMENT ON COLUMN "omni"."reader_items"."parsed_at" IS '最近一次解析成功时间';

COMMENT ON COLUMN "omni"."reader_text_chapters"."id" IS '文本章节唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_text_chapters"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_text_chapters"."chapter_index" IS '章节顺序索引';
COMMENT ON COLUMN "omni"."reader_text_chapters"."chapter_key" IS '来源内稳定章节键';
COMMENT ON COLUMN "omni"."reader_text_chapters"."title" IS '章节标题';
COMMENT ON COLUMN "omni"."reader_text_chapters"."char_count" IS '章节Unicode字符数量';
COMMENT ON COLUMN "omni"."reader_text_chapters"."level" IS '章节目录层级';
COMMENT ON COLUMN "omni"."reader_text_chapters"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_text_chapters"."version" IS '乐观锁版本号';

COMMENT ON COLUMN "omni"."reader_notes"."id" IS '阅读笔记唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_notes"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."reader_notes"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_notes"."title" IS '笔记标题';
COMMENT ON COLUMN "omni"."reader_notes"."content" IS '笔记正文';
COMMENT ON COLUMN "omni"."reader_notes"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_notes"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."reader_notes"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."reader_pages" IS '漫画页面清单表，保存跨来源合并后的稳定阅读顺序';
COMMENT ON COLUMN "omni"."reader_pages"."id" IS '漫画页面唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_pages"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_pages"."source_id" IS '漫画来源ID，关联reader_item_sources';
COMMENT ON COLUMN "omni"."reader_pages"."catalog_node_id" IS '所属目录节点ID，关联reader_catalog_nodes';
COMMENT ON COLUMN "omni"."reader_pages"."page_index" IS '条目内全局页面索引';
COMMENT ON COLUMN "omni"."reader_pages"."source_path" IS '归档内图片路径或来源页路径';
COMMENT ON COLUMN "omni"."reader_pages"."width" IS '页面像素宽度';
COMMENT ON COLUMN "omni"."reader_pages"."height" IS '页面像素高度';
COMMENT ON COLUMN "omni"."reader_pages"."fingerprint" IS '页面内容与来源位置指纹';
COMMENT ON COLUMN "omni"."reader_pages"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."reader_pages"."entry_index" IS '归档条目顺序索引';
COMMENT ON COLUMN "omni"."reader_pages"."mime_type" IS '页面图片MIME类型';
COMMENT ON COLUMN "omni"."reader_pages"."byte_size" IS '页面原始字节数';
COMMENT ON COLUMN "omni"."reader_pages"."source_page_index" IS '页面在来源文件中的索引';
COMMENT ON COLUMN "omni"."reader_pages"."catalog_key" IS '来源内稳定目录键';

COMMENT ON COLUMN "omni"."reader_progress"."id" IS '阅读进度唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_progress"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."reader_progress"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_progress"."updated_at" IS '最近一次进度更新时间';
COMMENT ON COLUMN "omni"."reader_progress"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."reader_reading_sessions"."id" IS '阅读会话唯一标识，主键';
COMMENT ON COLUMN "omni"."reader_reading_sessions"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."reader_reading_sessions"."reader_item_id" IS '阅读条目ID，关联reader_items';
COMMENT ON COLUMN "omni"."reader_reading_sessions"."started_at" IS '阅读会话开始时间';
COMMENT ON COLUMN "omni"."reader_reading_sessions"."ended_at" IS '阅读会话结束时间';
COMMENT ON COLUMN "omni"."reader_reading_sessions"."duration_seconds" IS '有效阅读时长，单位为秒';
COMMENT ON COLUMN "omni"."reader_reading_sessions"."created_at" IS '创建时间';

COMMENT ON COLUMN "omni"."shared_space_permissions"."id" IS '共享空间角色权限唯一标识，主键';
COMMENT ON COLUMN "omni"."shared_space_permissions"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."shared_space_permissions"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."shared_space_permissions"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."shared_space_usage"."id" IS '共享空间用量单例主键';
COMMENT ON COLUMN "omni"."shared_space_usage"."used_bytes" IS '共享空间已使用字节数';
COMMENT ON COLUMN "omni"."shared_space_usage"."file_count" IS '共享空间活动文件数量';
COMMENT ON COLUMN "omni"."shared_space_usage"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."shared_space_usage"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."shared_space_usage"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."storage_import_tasks" IS '外部存储导入任务表，记录目录扫描、传输和安全入库进度';
COMMENT ON COLUMN "omni"."storage_import_tasks"."id" IS '外部导入任务唯一标识，主键';
COMMENT ON COLUMN "omni"."storage_import_tasks"."owner_user_id" IS '所属用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."storage_import_tasks"."external_account_id" IS '外部存储账号ID，关联storage_external_accounts';
COMMENT ON COLUMN "omni"."storage_import_tasks"."source_path" IS '外部存储来源路径';
COMMENT ON COLUMN "omni"."storage_import_tasks"."target_parent_id" IS '目标父文件节点ID，根目录时为空';
COMMENT ON COLUMN "omni"."storage_import_tasks"."rclone_job_id" IS 'Rclone异步作业ID';
COMMENT ON COLUMN "omni"."storage_import_tasks"."rclone_group" IS 'Rclone统计分组名称';
COMMENT ON COLUMN "omni"."storage_import_tasks"."file_name" IS '当前来源文件或任务显示名称';
COMMENT ON COLUMN "omni"."storage_import_tasks"."total_bytes" IS '预计导入总字节数';
COMMENT ON COLUMN "omni"."storage_import_tasks"."transferred_bytes" IS '已传输并通过入库处理的字节数';
COMMENT ON COLUMN "omni"."storage_import_tasks"."speed_bytes" IS '当前传输速度，单位为字节每秒';
COMMENT ON COLUMN "omni"."storage_import_tasks"."status" IS '导入任务状态';
COMMENT ON COLUMN "omni"."storage_import_tasks"."error_summary" IS '导入失败的有界摘要';
COMMENT ON COLUMN "omni"."storage_import_tasks"."completed_file_id" IS '导入完成后的文件或目录节点ID';
COMMENT ON COLUMN "omni"."storage_import_tasks"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."storage_import_tasks"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."storage_import_tasks"."version" IS '乐观锁版本号';
COMMENT ON COLUMN "omni"."storage_import_tasks"."space_type" IS '目标空间类型：PERSONAL / SHARED';

COMMENT ON TABLE "omni"."storage_remote_metadata_cache" IS '外部存储目录元数据缓存表，减少重复远端列表请求';
COMMENT ON COLUMN "omni"."storage_remote_metadata_cache"."id" IS '远端元数据缓存唯一标识，主键';
COMMENT ON COLUMN "omni"."storage_remote_metadata_cache"."external_account_id" IS '外部存储账号ID，关联storage_external_accounts';
COMMENT ON COLUMN "omni"."storage_remote_metadata_cache"."remote_path" IS '远端目录路径';
COMMENT ON COLUMN "omni"."storage_remote_metadata_cache"."metadata_json" IS '远端目录元数据快照，JSONB格式';
COMMENT ON COLUMN "omni"."storage_remote_metadata_cache"."cached_at" IS '缓存生成时间';
COMMENT ON COLUMN "omni"."storage_remote_metadata_cache"."expires_at" IS '缓存过期时间';

COMMENT ON TABLE "omni"."sync_event_checkpoints" IS '同步事件检查点表，保存服务端消费者的消费水位';
COMMENT ON COLUMN "omni"."sync_event_checkpoints"."id" IS '同步检查点唯一标识，主键';
COMMENT ON COLUMN "omni"."sync_event_checkpoints"."checkpoint_key" IS '消费者或用途检查点键';
COMMENT ON COLUMN "omni"."sync_event_checkpoints"."sequence_no" IS '最近已处理的同步事件序号';
COMMENT ON COLUMN "omni"."sync_event_checkpoints"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."sync_event_checkpoints"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."sync_event_checkpoints"."version" IS '乐观锁版本号';

COMMENT ON TABLE "omni"."sync_events" IS '跨端同步事件表，保存可增量拉取并可靠发布的资源变更';
COMMENT ON COLUMN "omni"."sync_events"."id" IS '同步事件唯一标识，主键';
COMMENT ON COLUMN "omni"."sync_events"."sequence_no" IS '全局单调递增事件序号';
COMMENT ON COLUMN "omni"."sync_events"."recipient_user_id" IS '事件接收用户ID，关联auth_users';
COMMENT ON COLUMN "omni"."sync_events"."scope" IS '事件业务作用域';
COMMENT ON COLUMN "omni"."sync_events"."resource_type" IS '变更资源类型';
COMMENT ON COLUMN "omni"."sync_events"."resource_id" IS '变更资源ID';
COMMENT ON COLUMN "omni"."sync_events"."action" IS '资源变更动作';
COMMENT ON COLUMN "omni"."sync_events"."resource_version" IS '资源变更后的版本号';
COMMENT ON COLUMN "omni"."sync_events"."payload" IS '同步所需的有界事件载荷，JSONB格式';
COMMENT ON COLUMN "omni"."sync_events"."publish_status" IS '实时事件发布状态';
COMMENT ON COLUMN "omni"."sync_events"."publish_attempts" IS '实时事件发布尝试次数';
COMMENT ON COLUMN "omni"."sync_events"."available_at" IS '允许再次发布的时间';
COMMENT ON COLUMN "omni"."sync_events"."locked_by" IS '当前发布租约持有实例标识';
COMMENT ON COLUMN "omni"."sync_events"."locked_until" IS '当前发布租约到期时间';
COMMENT ON COLUMN "omni"."sync_events"."published_at" IS '实时事件发布成功时间';
COMMENT ON COLUMN "omni"."sync_events"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."sync_events"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."sync_events"."version" IS '乐观锁版本号';

COMMENT ON COLUMN "omni"."sys_task_dispatches"."id" IS '任务投递记录唯一标识，主键';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."task_id" IS '系统任务ID，关联sys_tasks';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."exchange_name" IS 'RabbitMQ目标交换机名称';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."routing_key" IS 'RabbitMQ投递路由键';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."payload" IS '待投递消息载荷，JSON文本';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."attempt_count" IS '消息投递尝试次数';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."next_attempt_at" IS '下次允许投递时间';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."locked_by" IS '当前投递租约持有实例标识';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."locked_until" IS '当前投递租约到期时间';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."published_at" IS '消息投递成功时间';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."last_error_code" IS '最近一次投递失败的稳定错误码';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."created_at" IS '创建时间';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."updated_at" IS '更新时间';
COMMENT ON COLUMN "omni"."sys_task_dispatches"."version" IS '乐观锁版本号';
