package com.omninest.modules.user.util;

import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AuthUserDto;
import java.time.Duration;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * AuthUser -> AuthUserDto 映射工具类。
 * 消除 AuthService / CurrentUserService / AdminUserService / StorageQuotaService 中的重复映射逻辑。
 */
public final class AuthUserMapper {

    private static final Duration AVATAR_URL_TTL = Duration.ofHours(24);
    private static final List<String> AVATAR_EXTENSIONS = List.of("jpg", "png", "webp");

    private AuthUserMapper() {
        // 工具类不可实例化
    }

    /**
     * 将 AuthUser 转换为 AuthUserDto（从实体关联读取权限，调用方须已初始化 permissions）。
     *
     * @param user      用户实体
     * @param avatarUrl 已解析的头像 URL，可为 null
     * @return DTO 对象
     */
    public static AuthUserDto toDto(AuthUser user, String avatarUrl) {
        return toDto(user, avatarUrl, permissionCodesByRoleId(user));
    }

    /**
     * 将 AuthUser 转换为 AuthUserDto（权限来自页级批量查询结果）。
     *
     * @param user                      用户实体
     * @param avatarUrl                 已解析的头像 URL，可为 null
     * @param permissionCodesByRoleId   角色 ID 到权限编码集合的映射
     * @return DTO 对象
     */
    public static AuthUserDto toDto(
            AuthUser user,
            String avatarUrl,
            Map<UUID, Set<String>> permissionCodesByRoleId) {
        Set<String> roles = roleCodes(user);
        Set<String> permissions = user.getRoles().stream()
                .filter(AuthRole::isEnabled)
                .flatMap(role -> permissionCodesByRoleId
                        .getOrDefault(role.getId(), Set.<String>of())
                        .stream())
                .sorted(Comparator.naturalOrder())
                .collect(Collectors.toCollection(LinkedHashSet::new));
        return new AuthUserDto(
                user.getId(),
                user.getUsername(),
                user.getDisplayName(),
                avatarUrl,
                user.getEmail(),
                user.getStatus(),
                primaryRole(roles),
                roles,
                permissions,
                user.getQuotaBytes(),
                user.getUsedBytes()
        );
    }

    /**
     * 解析用户头像的 presigned 下载 URL。
     * 依次尝试 jpg / png / webp 扩展名，返回第一个存在的对象 URL。
     *
     * @param user               用户实体
     * @param objectStorageClient 对象存储客户端
     * @param objectStorageBuckets 对象存储桶名称
     * @return 头像 URL，未找到时返回 null
     */
    public static String resolveAvatarUrl(AuthUser user,
                                          ObjectStorageClient objectStorageClient,
                                          ObjectStorageBuckets objectStorageBuckets) {
        if (user.getAvatarFileId() == null) {
            return null;
        }
        String bucket = objectStorageBuckets.derivedAssets();
        for (String ext : AVATAR_EXTENSIONS) {
            String objectKey = "avatars/" + user.getId() + "/avatar." + ext;
            ObjectStorageKey key = new ObjectStorageKey(bucket, objectKey);
            if (objectStorageClient.objectExists(key)) {
                return objectStorageClient.createDownloadUrl(key, AVATAR_URL_TTL).toString();
            }
        }
        return null;
    }

    /**
     * 计算用户的主要角色（优先级：SUPER_ADMIN > ADMIN > MEMBER > 其他 > GUEST）。
     *
     * @param user 用户实体
     * @return 主要角色代码
     */
    public static String primaryRole(AuthUser user) {
        return primaryRole(roleCodes(user));
    }

    /**
     * 从已有的角色代码集合中计算主要角色。
     *
     * @param roles 角色代码集合
     * @return 主要角色代码
     */
    public static String primaryRole(Set<String> roles) {
        if (roles.contains(Roles.SUPER_ADMIN)) {
            return Roles.SUPER_ADMIN;
        }
        if (roles.contains(Roles.ADMIN)) {
            return Roles.ADMIN;
        }
        if (roles.contains(Roles.MEMBER)) {
            return Roles.MEMBER;
        }
        return roles.stream().findFirst().orElse(Roles.GUEST);
    }

    /**
     * 提取用户已启用角色的代码集合（自然排序）。
     *
     * @param user 用户实体
     * @return 角色代码集合
     */
    public static Set<String> roleCodes(AuthUser user) {
        return user.getRoles().stream()
                .filter(AuthRole::isEnabled)
                .map(AuthRole::getCode)
                .sorted(Comparator.naturalOrder())
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    /**
     * 提取用户所有已启用角色对应的已启用权限代码集合（自然排序）。
     *
     * @param user 用户实体
     * @return 权限代码集合
     */
    public static Set<String> permissionCodes(AuthUser user) {
        return permissionCodesByRoleId(user).values()
                .stream()
                .flatMap(Set::stream)
                .sorted(Comparator.naturalOrder())
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    /**
     * 从实体关联构建 roleId -> 权限编码映射（permissions 须已初始化）。
     *
     * @param user 用户实体
     * @return 角色 ID 到权限编码集合
     */
    public static Map<UUID, Set<String>> permissionCodesByRoleId(AuthUser user) {
        Map<UUID, Set<String>> byRoleId = new LinkedHashMap<>();
        for (AuthRole role : user.getRoles()) {
            if (!role.isEnabled()) {
                continue;
            }
            Set<String> codes = role.getPermissions().stream()
                    .filter(AuthPermission::isEnabled)
                    .map(AuthPermission::getCode)
                    .sorted(Comparator.naturalOrder())
                    .collect(Collectors.toCollection(LinkedHashSet::new));
            byRoleId.put(role.getId(), codes);
        }
        return byRoleId;
    }
}
