package com.omninest.modules.user.util;

import java.util.UUID;

/**
 * 用户头像对象键的唯一定义。
 *
 * <p>键形如 {@code avatars/{userId}/{avatarFileId}}：扩展名不进键，Content-Type 由对象元数据
 * 携带，头像标识就是 {@code auth_users.avatar_file_id}。旧方案按扩展名落
 * {@code avatar.{ext}} 并把整键哈希成 UUID，读取侧只能按 jpg→png→webp 固定顺序探测，
 * 用户换过一次格式后旧对象就永久遮蔽新头像，每次映射还要多打几次对象存储 HEAD。</p>
 *
 * @author OmniNest
 */
public final class UserAvatarObjectKeys {

    private static final String AVATAR_PREFIX = "avatars/";

    private UserAvatarObjectKeys() {
    }

    /**
     * 组装头像对象键。
     *
     * @param userId 用户 ID
     * @param avatarFileId 头像标识
     * @return 对象键
     */
    public static String objectKey(UUID userId, UUID avatarFileId) {
        return AVATAR_PREFIX + userId + "/" + avatarFileId;
    }

    /**
     * 从对象键解析头像标识。
     *
     * @param objectKey 对象键
     * @return 头像标识；非本方案对象键（含旧的 {@code avatar.{ext}}）返回 null
     */
    public static UUID parseAvatarFileId(String objectKey) {
        if (objectKey == null || !objectKey.startsWith(AVATAR_PREFIX)) {
            return null;
        }
        int lastSlash = objectKey.lastIndexOf('/');
        if (lastSlash < AVATAR_PREFIX.length() || lastSlash == objectKey.length() - 1) {
            return null;
        }
        try {
            return UUID.fromString(objectKey.substring(lastSlash + 1));
        } catch (IllegalArgumentException exception) {
            return null;
        }
    }
}
