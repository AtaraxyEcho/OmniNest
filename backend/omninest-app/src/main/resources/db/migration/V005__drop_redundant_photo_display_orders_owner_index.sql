-- V005: 删除 V004 中被 uk_photo_display_orders_owner_context (owner_user_id, context_key) 前缀覆盖的冗余索引
DROP INDEX IF EXISTS omni.idx_photo_display_orders_owner;
