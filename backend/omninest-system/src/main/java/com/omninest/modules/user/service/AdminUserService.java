package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.domain.UserStatus;
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
import org.springframework.transaction.support.TransactionTemplate;

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
    private final TwoFactorService twoFactorService;
    private final AdminActorGuard adminActorGuard;
    private final CurrentUserService currentUserService;
    private final TransactionTemplate transactionTemplate;
    private final ObjectStorageClient objectStorageClient;
    private final ObjectStorageBuckets objectStorageBuckets;

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
                user,
                AuthUserMapper.resolveAvatarUrl(user, objectStorageClient, objectStorageBuckets),
                permissionCodesByRoleId,
                twoFactorUserIds.contains(user.getId())));
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
        UUID actorUserId = currentUserContext.requireCurrentUserId();
        AuthUser actor = adminActorGuard.requireFreshAdminActor(actorUserId);
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
        resolveRolesForActor(actor, request.roles()).forEach(user.getRoles()::add);
        AuthUserDto saved = toDto(authUserRepository.save(user));
        auditLogService.recordWithMetadata(
                actorUserId,
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
        return executeUpdateUserStatus(userId, rawStatus);
    }

    /**
     * 单行状态变更的实际实现：状态落库、会话撤销与审计必须在同一个事务里。
     *
     * <p>批量入口经 {@code TransactionTemplate} 调用本方法；直接自调用公开方法会被
     * Spring AOP 代理绕过，注解事务不生效，那时「状态已改但会话未吊销」会各自提交。</p>
     */
    private AuthUserDto executeUpdateUserStatus(UUID userId, String rawStatus) {
        AuthUser actor = adminActorGuard.requireFreshAdminActor(currentUserContext.requireCurrentUserId());
        AuthUser user = authUserRepository.findWithRolesById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        if (AuthUserMapper.roleCodes(user).contains(Roles.SUPER_ADMIN)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员状态不能通过管理端修改");
        }
        adminActorGuard.requireSuperAdminForAdminTarget(actor, user, "修改管理员账户状态");
        String normalizedStatus = normalizeStatus(rawStatus);
        if (actor.getId().equals(userId) && !UserStatus.ACTIVE.getValue().equals(normalizedStatus)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "不能禁用当前登录的管理员账号");
        }
        user.setStatus(normalizedStatus);
        AuthUserDto saved = toDto(authUserRepository.save(user));
        userSessionRevocationService.revokeAll(List.of(userId), "管理员更新用户状态");
        currentUserService.evictProfileCache(userId);
        auditLogService.recordWithMetadata(
                actor.getId(),
                "ADMIN_USER_STATUS_UPDATE", "auth_users", userId,
                Map.of("status", saved.status()));
        return saved;
    }

    /**
     * 重置用户两步验证：清除 TOTP 凭据与备份码，并撤销该用户全部会话。
     *
     * <p>恢复路径用途：认证器丢失，或凭据加密密钥轮换后密文无法解密时，用户完不成两步验证登录，
     * 只能由管理员清零后重新开启。超级管理员同样可被重置，否则单实例部署会在换密钥后把自己锁在门外；
     * 重置不等于取得访问——登录仍需要该用户的密码。</p>
     *
     * <p>普通管理员不得重置其他管理员的验证器：清掉 TOTP 并吊销全部会话，
     * 已足够把一个同级账户挡在门外。</p>
     *
     * @param userId 用户标识
     */
    @Transactional(rollbackFor = Exception.class)
    public void resetTwoFactor(UUID userId) {
        AuthUser actor = adminActorGuard.requireFreshAdminActor(currentUserContext.requireCurrentUserId());
        AuthUser user = authUserRepository.findWithRolesById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        adminActorGuard.requireSuperAdminForAdminTarget(actor, user, "重置管理员两步验证");
        twoFactorService.resetByAdmin(user.getId());
        userSessionRevocationService.revokeAll(List.of(user.getId()), "管理员重置两步验证");
        currentUserService.evictProfileCache(user.getId());
        auditLogService.recordWithMetadata(
                actor.getId(),
                "ADMIN_USER_2FA_RESET", "auth_users", user.getId(),
                Map.of("username", user.getUsername()));
    }

    /**
     * 批量更新用户状态：逐项独立提交，单行失败跳过不中断。
     *
     * <p>复用单行守卫与副作用（超级管理员拒改、成功后撤销该用户全部会话并记审计）；
     * 不刻意包整体事务——逐项独立提交保证某行中途失败时已成功项不回滚，
     * 失败项（不存在、超级管理员或更新异常）计入 failedIds 供前端逐项反馈。</p>
     *
     * <p>单行必须通过 {@code TransactionTemplate} 进入事务：同类自调用不走 AOP 代理，
     * 注解事务会失效，那时某行的会话撤销失败只留下已提交的状态变更。</p>
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
                transactionTemplate.executeWithoutResult(status -> executeUpdateUserStatus(userId, rawStatus));
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
        AuthUser actor = adminActorGuard.requireFreshAdminActor(currentUserContext.requireCurrentUserId());
        AuthUser user = authUserRepository.findWithRolesById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        if (AuthUserMapper.roleCodes(user).contains(Roles.SUPER_ADMIN)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员角色不能通过管理端修改");
        }
        adminActorGuard.requireSuperAdminForAdminTarget(actor, user, "修改管理员角色");
        Set<AuthRole> resolvedRoles = resolveRolesForActor(actor, requestedRoles);
        if (actor.getId().equals(userId)
                && resolvedRoles.stream().noneMatch(role -> Roles.ADMIN.equals(role.getCode())
                        || Roles.SUPER_ADMIN.equals(role.getCode()))) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "不能移除当前登录账号的管理员角色");
        }
        user.getRoles().clear();
        resolvedRoles.forEach(user.getRoles()::add);
        AuthUserDto saved = toDto(authUserRepository.save(user));
        userSessionRevocationService.revokeAll(List.of(userId), "管理员更新用户角色");
        currentUserService.evictProfileCache(userId);
        auditLogService.recordWithMetadata(
                actor.getId(),
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
        // 剥离 LIKE 通配符，避免管理端搜索被构造成全表模糊扫描
        String sanitized = normalized.replace("%", "").replace("_", "");
        return "%" + sanitized + "%";
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

    /**
     * 按操作者身份解析待授予角色。
     *
     * <p>普通管理员既不能授予管理员角色，也不能授予自身不具备的权限：自定义角色的
     * 权限集合可能宽于操作者本人，直接落库等同于让低权管理员给自己造一个高权账户。</p>
     */
    private Set<AuthRole> resolveRolesForActor(AuthUser actor, Set<String> requestedRoles) {
        Set<AuthRole> roles = resolveRoles(requestedRoles);
        if (adminActorGuard.isSuperAdmin(actor)) {
            return roles;
        }
        if (roles.stream().anyMatch(role -> Roles.ADMIN.equals(role.getCode()))) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "仅超级管理员可授予管理员角色");
        }
        Set<UUID> roleIds = roles.stream()
                .map(AuthRole::getId)
                .collect(Collectors.toCollection(LinkedHashSet::new));
        Set<String> grantedPermissions = authRoleRepository.findPermissionCodesByRoleIds(roleIds)
                .values()
                .stream()
                .flatMap(Set::stream)
                .collect(Collectors.toCollection(HashSet::new));
        adminActorGuard.requireGrantWithinActorScope(actor, grantedPermissions);
        return roles;
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
        // 与登录入口同一口径：唯一索引建在 lower(username) 上，大小写变体不能注册成两个账户。
        String username = rawUsername == null ? "" : rawUsername.trim().toLowerCase(Locale.ROOT);
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
                .map(found -> AuthUserMapper.toDto(
                        found, AuthUserMapper.resolveAvatarUrl(found, objectStorageClient, objectStorageBuckets)))
                .orElseGet(() -> AuthUserMapper.toDto(
                        user, AuthUserMapper.resolveAvatarUrl(user, objectStorageClient, objectStorageBuckets)));
    }
}
