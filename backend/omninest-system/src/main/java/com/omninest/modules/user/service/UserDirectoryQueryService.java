package com.omninest.modules.user.service;

import com.omninest.common.api.PageResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserAuthorizationProfile;
import com.omninest.modules.user.dto.UserDirectoryDtos.UserDirectoryEntry;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 向业务模块提供最小化用户授权与候选查询，避免泄露完整管理 DTO。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserDirectoryQueryService {

    private final AuthUserRepository userRepository;

    /** 查询用户角色和权限。 */
    @Transactional(readOnly = true)
    public UserAuthorizationProfile requireAuthorizationProfile(UUID userId) {
        AuthUser user = userRepository.findWithRolesAndPermissionsById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FORBIDDEN, "用户不存在或不可用"));
        Set<String> roles = user.getRoles().stream()
                .filter(AuthRole::isEnabled)
                .map(AuthRole::getCode)
                .collect(Collectors.toUnmodifiableSet());
        Set<String> permissions = user.getRoles().stream()
                .filter(AuthRole::isEnabled)
                .flatMap(role -> role.getPermissions().stream())
                .filter(AuthPermission::isEnabled)
                .map(AuthPermission::getCode)
                .collect(Collectors.toUnmodifiableSet());
        return new UserAuthorizationProfile(user.getId(), user.getStatus(), roles, permissions);
    }

    /** 分页搜索活动用户的最小公开字段。 */
    @Transactional(readOnly = true)
    public PageResponse<UserDirectoryEntry> findActiveUsers(String query, int page, int size) {
        int safePage = Math.max(0, page);
        int safeSize = com.omninest.common.api.PageClamps.safeSize(size);
        String normalizedQuery = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
        Page<AuthUser> users = userRepository.searchByStatus(
                UserStatus.ACTIVE.getValue(),
                normalizedQuery,
                PageRequest.of(safePage, safeSize, Sort.by(Sort.Direction.ASC, "username"))
        );
        return PageResponse.of(
                users.getContent().stream()
                        .map(user -> new UserDirectoryEntry(
                                user.getId(),
                                user.getUsername(),
                                user.getDisplayName(),
                                user.getStatus()
                        ))
                        .toList(),
                safePage,
                safeSize,
                users.getTotalElements()
        );
    }
}
