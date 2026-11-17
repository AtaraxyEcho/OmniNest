package com.omninest.modules.user.util;

import com.omninest.common.security.Roles;
import com.omninest.common.user.UserAvatarAssetPort;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AuthUserDto;
import java.time.Duration;
import java.util.Collection;
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
        return toDto(user, avatarUrl, permissionCodesByRoleId, null);
    }

    /**
     * 将 AuthUser 转换为 AuthUserDto，并附带两步验证启用状态。
     *
     * @param twoFactorEnabled  是否已确认启用两步验证；由管理用户列表按页批量查询后传入
     */
    public static AuthUserDto toDto(
            AuthUser user,
            String avatarUrl,
            Map<UUID, Set<String>> permissionCodesByRoleId,
            Boolean twoFactorEnabled) {
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
                user.getUsedBytes(),
                user.getCreatedAt(),
                twoFactorEnabled
        );
    }

    /**
     * 以头像所有者身份解析短期下载地址。
     *
     * <p>地址由文件模块按 {@code file_objects} 行签发：对象键约定收在属主模块里，
     * 读取侧不再各自拼装；时长沿用资料接口历来的 24 小时，避免客户端在资料不重拉
     * 期间拿到已过期地址。</p>
     *
     * @param user 用户实体
     * @param avatars 头像资产端口
     * @return 头像 URL，未设置头像时返回 null
     */
    public static String resolveAvatarUrl(AuthUser user, UserAvatarAssetPort avatars) {
        UUID avatarFileId = user.getAvatarFileId();
        if (avatarFileId == null) {
            return null;
        }
        return avatars.downloadUrls(
                user.getId(),
                List.of(avatarFileId),
                AVATAR_URL_TTL
        ).get(avatarFileId);
    }

    /**
     * 整页批量解析头像地址，返回按用户 ID 取用的映射。
     *
     * <p>逐户签发会让一页最多 100 个用户各自回查一次节点与对象行。</p>
     *
     * @param users 同一页的用户实体
     * @param avatars 头像资产端口
     * @return 用户 ID 到头像 URL 的映射；无头像的用户不出现在结果里
     */
    public static Map<UUID, String> resolveAvatarUrls(
            Collection<AuthUser> users,
            UserAvatarAssetPort avatars
    ) {
        Map<UUID, UUID> nodeByUser = new LinkedHashMap<>();
        for (AuthUser user : users) {
            if (user.getAvatarFileId() != null) {
                nodeByUser.put(user.getId(), user.getAvatarFileId());
            }
        }
        if (nodeByUser.isEmpty()) {
            return Map.of();
        }
        Map<UUID, String> urlByNode =
                avatars.downloadUrlsForManagedNodes(nodeByUser.values(), AVATAR_URL_TTL);
        Map<UUID, String> urlByUser = new LinkedHashMap<>();
        nodeByUser.forEach((userId, fileId) -> {
            String url = urlByNode.get(fileId);
            if (url != null) {
                urlByUser.put(userId, url);
            }
        });
        return urlByUser;
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
