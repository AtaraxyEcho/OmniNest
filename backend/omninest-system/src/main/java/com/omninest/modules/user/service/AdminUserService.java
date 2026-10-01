package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Roles;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AdminBatchUserStatusResult;
import com.omninest.modules.user.dto.AdminCreateUserRequest;
import com.omninest.modules.user.dto.AuthUserDto;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.util.AuthUserMapper;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.ArrayList;
import java.util.HashSet;
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
    private static final int MAX_FILTER_LENGTH = 100;
    private static final int MAX_SEARCH_LENGTH = 200;

    /**
     * 排序字段白名单：请求字段（大小写不敏感）到实体属性的映射，
     * 白名单外的取值回退为用户名升序。
     */
    private static final Map<String, String> SORT_FIELDS = Map.of(
            "username", "username",
            "email", "email",
            "status", "status",
            "usedbytes", "usedBytes",
            "quotabytes", "quotaBytes",
            "createdat", "createdAt");

    private final AuthUserRepository authUserRepository;
    private final AuthRoleRepository authRoleRepository;
    private final AuthTotpCredentialRepository authTotpCredentialRepository;
    private final PasswordEncoder passwordEncoder;
    private final PasswordPolicy passwordPolicy;
    private final AdminAuditLogService auditLogService;
    private final CurrentUserContext currentUserContext;
    private final StorageQuotaService storageQuotaService;
    private final UserSessionRevocationService userSessionRevocationService;

    /**
     * 分页查询用户，支持按用户名、展示名、邮箱模糊搜索、角色编码精确过滤
     * 与白名单字段排序（默认用户名升序，id 倒序兜底保证翻页稳定）。
     *
     * @param page 页码
     * @param size 每页数量
     * @param query 搜索词，匹配 username/displayName/email，空表示不限
     * @param role 角色编码，ALL 或空表示不过滤
     * @param sort 排序字段，白名单外回退为 username
     * @param dir 排序方向，asc/desc，默认 asc
     * @return 用户分页
     */
    @Transactional(readOnly = true)
    public Page<AuthUserDto> listUsers(int page, int size, String query, String role, String sort, String dir) {
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(1, size <= 0 ? 50 : size), 100);
        PageRequest pageable = PageRequest.of(safePage, safeSize, userSort(sort, dir));
        Page<AuthUser> users = authUserRepository.searchAdminUsers(
                userSearchPattern(query), roleFilter(role), pageable);
        Set<UUID> roleIds = users.getContent()
                .stream()
                .flatMap(user -> user.getRoles().stream())
                .map(AuthRole::getId)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        Map<UUID, Set<String>> permissionCodesByRoleId =
                authRoleRepository.findPermissionCodesByRoleIds(roleIds);
        Set<UUID> twoFactorUserIds = twoFactorEnabledUserIds(users);
        return users.map(user -> AuthUserMapper.toDto(
                user, null, permissionCodesByRoleId, twoFactorUserIds.contains(user.getId())));
    }

    /**
     * 构建用户列表排序：字段仅允许白名单（大小写不敏感），方向仅
     * asc/desc（默认 asc），并追加 id 倒序兜底保证同值翻页稳定。
     */
    private Sort userSort(String sort, String dir) {
        String requested = sort == null ? "" : sort.toLowerCase(Locale.ROOT);
        String property = SORT_FIELDS.getOrDefault(requested, "username");
        Sort.Direction direction = "desc".equalsIgnoreCase(dir) ? Sort.Direction.DESC : Sort.Direction.ASC;
        return Sort.by(direction, property).and(Sort.by(Sort.Direction.DESC, "id"));
    }

    private Set<UUID> twoFactorEnabledUserIds(Page<AuthUser> users) {
        List<UUID> userIds = users.getContent()
                .stream()
                .map(AuthUser::getId)
                .collect(Collectors.toList());
        if (userIds.isEmpty()) {
            return Set.of();
        }
        return authTotpCredentialRepository.findByUserIdInAndEnabledTrue(userIds)
                .stream()
                .map(credential -> credential.getUserId())
                .collect(Collectors.toCollection(HashSet::new));
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
     * 批量更新用户状态：逐项独立提交，单行失败跳过不中断。
     *
     * <p>复用单行守卫与副作用（超级管理员拒改、成功后撤销该用户全部会话并记审计）；
     * 不刻意包整体事务——逐项独立提交保证某行中途失败时已成功项不回滚，
     * 失败项（不存在、超级管理员或更新异常）计入 failedIds 供前端逐项反馈。</p>
     *
     * @param userIds 用户标识列表
     * @param rawStatus 目标状态
     * @return 成功数量与失败用户 ID 列表
     */
    public AdminBatchUserStatusResult batchUpdateUserStatus(List<UUID> userIds, String rawStatus) {
        // 状态合法性前置校验：非法值整体拒绝，不逐项吞为失败项。
        normalizeStatus(rawStatus);
        int successCount = 0;
        List<UUID> failedIds = new ArrayList<>();
        for (UUID userId : userIds) {
            try {
                updateUserStatus(userId, rawStatus);
                successCount++;
            } catch (RuntimeException ex) {
                failedIds.add(userId);
            }
        }
        return new AdminBatchUserStatusResult(successCount, failedIds);
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

    /**
     * 归一化用户搜索词：小写化并包裹模糊通配符，口径与长度限制和管理端日志分页一致。
     */
    private String userSearchPattern(String query) {
        if (query == null || query.isBlank()) {
            return "";
        }
        String normalized = query.trim().toLowerCase(Locale.ROOT);
        if (normalized.length() > MAX_SEARCH_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "搜索条件长度不能超过 200 个字符");
        }
        return "%" + normalized + "%";
    }

    /**
     * 归一化角色筛选：ALL 或空白表示不过滤，其余按大写角色编码精确匹配。
     */
    private String roleFilter(String role) {
        if (role == null || role.isBlank() || "ALL".equalsIgnoreCase(role.trim())) {
            return "";
        }
        String normalized = role.trim().toUpperCase(Locale.ROOT);
        if (normalized.length() > MAX_FILTER_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "筛选条件长度不能超过 100 个字符");
        }
        return normalized;
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
        if (roleCode.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "角色编码不能为空");
        }
        if (Roles.SUPER_ADMIN.equals(roleCode)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员角色不能通过管理端授予");
        }
        return roleCode;
    }

    private AuthRole loadRole(String roleCode) {
        return authRoleRepository.findByCode(roleCode)
                .orElseThrow(() -> new BusinessException(ErrorCode.PARAM_ERROR, "角色不存在: " + roleCode));
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
