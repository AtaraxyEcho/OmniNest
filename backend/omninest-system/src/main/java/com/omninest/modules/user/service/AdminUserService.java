package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Roles;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AdminCreateUserRequest;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.util.AuthUserMapper;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理端用户维护服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class AdminUserService {
    private static final Set<String> DATABASE_ROLE_CODES = Set.of(Roles.ADMIN, Roles.MEMBER, Roles.GUEST);

    private final AuthUserRepository authUserRepository;
    private final AuthRoleRepository authRoleRepository;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final AdminAuditLogService auditLogService;
    private final CurrentUserContext currentUserContext;
    private final StorageQuotaService storageQuotaService;
    private final UserSessionRevocationService userSessionRevocationService;

    /**
     * 分页查询用户。
     *
     * @param page 页码
     * @param size 每页数量
     * @return 用户分页
     */
    @Transactional(readOnly = true)
    public Page<AuthUserDto> listUsers(int page, int size) {
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(1, size <= 0 ? 50 : size), 100);
        PageRequest pageable = PageRequest.of(safePage, safeSize, Sort.by(Sort.Direction.ASC, "username"));
        Page<AuthUser> users = authUserRepository.findAll(pageable);
        Set<UUID> roleIds = users.getContent()
                .stream()
                .flatMap(user -> user.getRoles().stream())
                .map(AuthRole::getId)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        Map<UUID, Set<String>> permissionCodesByRoleId =
                authRoleRepository.findPermissionCodesByRoleIds(roleIds);
        return users.map(user -> AuthUserMapper.toDto(user, null, permissionCodesByRoleId));
    }

    /**
     * 创建用户。
     *
     * @param request 创建请求
     * @return 新创建用户
     */
    @Transactional(rollbackFor = Exception.class)
    public AuthUserDto createUser(AdminCreateUserRequest request) {
        String username = normalizeUsername(request.username());
        if (authUserRepository.existsByUsername(username)) {
            throw new BusinessException(ErrorCode.CONFLICT, "用户名已存在");
        }
        passwordPolicy.validate(username, request.password());
        AuthUser user = new AuthUser();
        user.setUsername(username);
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setDisplayName(normalizeDisplayName(request.displayName(), username));
        user.setEmail(normalizeEmail(request.email()));
        user.setStatus(normalizeStatus(request.status()));
        user.setQuotaBytes(storageQuotaService.getDefaultQuotaBytes());
        resolveRoles(request.roles()).forEach(user.getRoles()::add);
        AuthUserDto saved = toDto(authUserRepository.save(user));
        auditLogService.recordWithMetadata(
                currentUserContext.requireCurrentUserId(),
                "ADMIN_USER_CREATE", "auth_users", saved.id(),
                Map.of("username", saved.username()));
        return saved;
    }

    /**
     * 更新用户状态并撤销既有会话。
     *
     * @param userId 用户标识
     * @param rawStatus 目标状态
     * @return 更新后用户
     */
    @Transactional(rollbackFor = Exception.class)
    public AuthUserDto updateUserStatus(UUID userId, String rawStatus) {
        AuthUser user = authUserRepository.findWithRolesById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        if (AuthUserMapper.roleCodes(user).contains(Roles.SUPER_ADMIN)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员状态不能通过管理端修改");
        }
        user.setStatus(normalizeStatus(rawStatus));
        AuthUserDto saved = toDto(authUserRepository.save(user));
        userSessionRevocationService.revokeAll(List.of(userId), "管理员更新用户状态");
        auditLogService.recordWithMetadata(
                currentUserContext.requireCurrentUserId(),
                "ADMIN_USER_STATUS_UPDATE", "auth_users", userId,
                Map.of("status", saved.status()));
        return saved;
    }

    /**
     * 更新用户角色并撤销既有会话。
     *
     * @param userId 用户标识
     * @param requestedRoles 目标角色编码
     * @return 更新后用户
     */
    @Transactional(rollbackFor = Exception.class)
    public AuthUserDto updateUserRoles(UUID userId, Set<String> requestedRoles) {
        AuthUser user = authUserRepository.findWithRolesById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        if (AuthUserMapper.roleCodes(user).contains(Roles.SUPER_ADMIN)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员角色不能通过管理端修改");
        }
        user.getRoles().clear();
        resolveRoles(requestedRoles).forEach(user.getRoles()::add);
        AuthUserDto saved = toDto(authUserRepository.save(user));
        userSessionRevocationService.revokeAll(List.of(userId), "管理员更新用户角色");
        auditLogService.recordWithMetadata(
                currentUserContext.requireCurrentUserId(),
                "ADMIN_USER_ROLES_UPDATE", "auth_users", userId,
                Map.of("roles", saved.roles()));
        return saved;
    }

    private Set<AuthRole> resolveRoles(Set<String> requestedRoles) {
        Set<String> roleCodes = requestedRoles == null || requestedRoles.isEmpty()
                ? Set.of(Roles.MEMBER)
                : requestedRoles;
        return roleCodes.stream()
                .map(this::normalizeRoleCode)
                .map(this::loadRole)
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    private String normalizeRoleCode(String rawRoleCode) {
        String roleCode = rawRoleCode == null ? "" : rawRoleCode.trim().toUpperCase(Locale.ROOT);
        if (!DATABASE_ROLE_CODES.contains(roleCode)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "角色不支持写入数据库");
        }
        return roleCode;
    }

    private AuthRole loadRole(String roleCode) {
        return authRoleRepository.findByCode(roleCode)
                .orElseThrow(() -> new BusinessException(ErrorCode.INTERNAL_ERROR, "角色未初始化"));
    }

    private String normalizeUsername(String rawUsername) {
        String username = rawUsername == null ? "" : rawUsername.trim();
        if (username.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "用户名不能为空");
        }
        return username;
    }

    private String normalizeDisplayName(String rawDisplayName, String username) {
        String displayName = rawDisplayName == null ? "" : rawDisplayName.trim();
        return displayName.isEmpty() ? username : displayName;
    }

    private String normalizeEmail(String rawEmail) {
        String email = rawEmail == null ? "" : rawEmail.trim();
        return email.isEmpty() ? null : email;
    }

    private String normalizeStatus(String rawStatus) {
        String status = rawStatus == null || rawStatus.isBlank()
                ? "ACTIVE"
                : rawStatus.trim().toUpperCase(Locale.ROOT);
        if (!Set.of("ACTIVE", "DISABLED").contains(status)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "用户状态不合法");
        }
        return status;
    }

    private AuthUserDto toDto(AuthUser user) {
        return authUserRepository.findWithRolesAndPermissionsById(user.getId())
                .map(found -> AuthUserMapper.toDto(found, null))
                .orElseGet(() -> AuthUserMapper.toDto(user, null));
    }
}
