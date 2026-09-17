package com.omninest.modules.user.service;

import com.omninest.common.security.Roles;
import com.omninest.common.user.UserAccountDetails;
import com.omninest.common.user.UserAccountQuery;
import com.omninest.common.user.UserAccountSummary;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.AuthUserMapper;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 用户账户查询服务，向其他模块提供不可变账户摘要。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserAccountQueryService implements UserAccountQuery {

    private final AuthUserRepository authUserRepository;

    /**
     * 查询用户账户摘要。
     *
     * @param userId 用户 ID
     * @return 用户摘要，不存在时返回空
     */
    @Override
    @Transactional(readOnly = true)
    public Optional<UserAccountSummary> findById(UUID userId) {
        return authUserRepository.findWithRolesById(userId)
                .map(this::toSummary);
    }

    /**
     * 查询用户账户详情。
     *
     * @param userId 用户 ID
     * @return 用户详情，不存在时返回空
     */
    @Override
    @Transactional(readOnly = true)
    public Optional<UserAccountDetails> findDetailsById(UUID userId) {
        return authUserRepository.findWithRolesAndPermissionsById(userId)
                .map(this::toDetails);
    }

    /**
     * 查询单个用户名。
     *
     * @param userId 用户 ID
     * @return 用户名，不存在时返回空
     */
    @Override
    @Transactional(readOnly = true)
    public Optional<String> findUsername(UUID userId) {
        return authUserRepository.findById(userId)
                .map(AuthUser::getUsername);
    }

    /**
     * 批量查询用户名。
     *
     * @param userIds 用户 ID 集合
     * @return 以用户 ID 为键的用户名映射
     */
    @Override
    @Transactional(readOnly = true)
    public Map<UUID, String> findUsernames(Collection<UUID> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, String> usernames = new LinkedHashMap<>();
        for (AuthUser user : authUserRepository.findAllById(userIds)) {
            usernames.put(user.getId(), user.getUsername());
        }
        return Map.copyOf(usernames);
    }

    /**
     * 按用户标识游标查询一批账户标识。
     *
     * @param exclusiveCursor 排他游标，首次查询传 null
     * @param limit 最大返回数量
     * @return 按用户标识升序排列的账户标识
     */
    @Override
    @Transactional(readOnly = true)
    public List<UUID> findIdsAfter(UUID exclusiveCursor, int limit) {
        int boundedLimit = Math.max(1, Math.min(limit, 500));
        if (exclusiveCursor == null) {
            return List.copyOf(authUserRepository.findFirstUserIds(boundedLimit));
        }
        return List.copyOf(authUserRepository.findUserIdsAfter(exclusiveCursor, boundedLimit));
    }

    private UserAccountSummary toSummary(AuthUser user) {
        return new UserAccountSummary(
                user.getId(),
                user.getUsername(),
                user.getRoles().stream().map(AuthRole::getId).collect(Collectors.toSet()),
                user.getRoles().stream().anyMatch(role -> Roles.SUPER_ADMIN.equals(role.getCode())),
                user.getQuotaBytes(),
                user.getUsedBytes()
        );
    }

    private UserAccountDetails toDetails(AuthUser user) {
        AuthUserDto dto = AuthUserMapper.toDto(user, null);
        return new UserAccountDetails(
                dto.id(),
                dto.username(),
                dto.displayName(),
                dto.avatarUrl(),
                dto.email(),
                dto.status(),
                dto.role(),
                dto.roles(),
                dto.permissions(),
                dto.quotaBytes(),
                dto.usedBytes()
        );
    }
}
