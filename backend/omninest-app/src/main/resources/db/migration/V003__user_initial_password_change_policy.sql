ALTER TABLE "omni"."auth_users"
    ADD COLUMN "password_change_required" boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN "omni"."auth_users"."password_change_required"
    IS '是否要求用户在首次登录后立即修改密码';

UPDATE "omni"."config_entries"
SET "config_value" = 'SUPER_ADMIN',
    "updated_at" = now()
WHERE "config_key" = 'auth.two-factor.required-roles';
