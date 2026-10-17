package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.repository.AuthPermissionRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理台角色与权限绑定维护。
 *
 * <p>角色权限直接决定绑定用户的有效权限，因此所有写操作都要复核操作者当前身份，
 * 并把授予范围限制在操作者自身权限之内；内置角色的权限矩阵只能由超级管理员维护。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class AdminRoleService {

    /**
     * 自定义角色编码规则：ROLE_ 前缀加大写字母、数字与下划线。
     */
    private static final Pattern CUSTOM_ROLE_CODE_PATTERN = Pattern.compile("^ROLE_[A-Z0-9_]+$");
    private static final Set<String> ROLE_BASE_TEMPLATES = Set.of("NONE", "MEMBER", "ADMIN");
    private static final Map<String, String> ROLE_TEMPLATE_CODES = Map.of(
            "MEMBER", Roles.MEMBER,
            "ADMIN", Roles.ADMIN
    );

    private final AuthRoleRepository authRoleRepository;
    private final AuthUserRepository authUserRepository;
    private final AuthPermissionRepository authPermissionRepository;
    private final AdminAuditLogService auditLogService;
    private final UserSessionRevocationService userSessionRevocationService;
    private final AdminActorGuard adminActorGuard;

    @Transactional(readOnly = true)
    public AdminOperationsDto.RoleManagementView roles() {
        List<AdminOperationsDto.RoleDetail> roles = authRoleRepository
                .findAllWithPermissions(Sort.by(Sort.Direction.ASC, "code"))
                .stream()
                .map(this::toRoleDetail)
                .toList();
        List<AdminOperationsDto.PermissionDetail> permissions = authPermissionRepository
                .findAll(Sort.by(Sort.Direction.ASC, "module", "code"))
                .stream()
                .map(this::toPermissionDetail)
                .toList();
        return new AdminOperationsDto.RoleManagementView(roles, permissions);
    }

    /**
     * 整体替换角色的权限绑定集合，并吊销受影响用户的会话使新权限立即生效。
     *
     * @param actorUserId 操作者用户标识
     * @param roleCode 角色编码
     * @param request 权限编码集合
     * @return 更新后的角色详情
     */
    @Transactional(rollbackFor = Exception.class)
    public AdminOperationsDto.RoleDetail updateRolePermissions(
            UUID actorUserId,
            String roleCode,
            AdminOperationsDto.UpdateRolePermissionsRequest request
    ) {
        AuthUser actor = adminActorGuard.requireFreshAdminActor(actorUserId);
        String normalizedRoleCode = normalizeRoleCode(roleCode);
        if (Roles.SUPER_ADMIN.equals(normalizedRoleCode)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员权限由系统权限全集维护");
        }
        AuthRole role = authRoleRepository.findByCode(normalizedRoleCode)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "角色不存在"));
        boolean actorIsSuperAdmin = adminActorGuard.isSuperAdmin(actor);
        if (!actorIsSuperAdmin && role.isBuiltIn()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "内置角色的权限矩阵只能由超级管理员维护");
        }
        Set<String> requestedCodes = normalizeCodes(request.permissions());
        if (!actorIsSuperAdmin) {
            adminActorGuard.requireGrantWithinActorScope(actor, requestedCodes);
        }
        Set<AuthPermission> permissions = requestedCodes.isEmpty()
                ? Set.of()
                : authPermissionRepository.findByCodeIn(requestedCodes);
        if (permissions.size() != requestedCodes.size()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "权限编码不存在");
        }
        List<String> previousCodes = toRoleDetail(role).permissions();
        role.getPermissions().clear();
        role.getPermissions().addAll(permissions);
        authRoleRepository.save(role);
        List<UUID> affectedUserIds = authUserRepository.findAllByRoles_Code(normalizedRoleCode)
                .stream()
                .map(AuthUser::getId)
                .toList();
        userSessionRevocationService.revokeAll(affectedUserIds, "管理员更新角色权限");
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("oldValue", previousCodes);
        payload.put("newValue", toRoleDetail(role).permissions());
        payload.put("changeBy", actorUserId.toString());
        auditLogService.recordWithPayload(
                actorUserId, "ADMIN_ROLE_PERMISSIONS_UPDATE", "auth_roles", role.getId(), payload);
        return toRoleDetail(role);
    }

    /**
     * 创建自定义角色。
     *
     * <p>编码必须以 ROLE_ 开头且仅含大写字母、数字与下划线，长度 3-64 且全局唯一；
     * baseTemplate 指定初始权限来源：none 为空权限，member / admin 克隆对应内置角色
     * 的当前权限绑定集合。模板角色缺失说明内置目录未初始化，按系统内部错误返回。
     * 非超级管理员克隆的模板权限不得超过其自身权限范围，否则可以用模板造出比自己也
     * 更大的角色再绑回自身完成提权。新角色固定 builtIn=false、enabled=true。</p>
     *
     * @param actorUserId 操作者用户标识
     * @param request 创建请求
     * @return 新角色详情
     */
    @Transactional(rollbackFor = Exception.class)
    public AdminOperationsDto.RoleDetail createRole(
            UUID actorUserId,
            AdminOperationsDto.CreateRoleRequest request
    ) {
        AuthUser actor = adminActorGuard.requireFreshAdminActor(actorUserId);
        String code = normalizeNewRoleCode(request.code());
        String name = normalizeText(request.name(), "角色名称不能为空");
        if (name.length() > 64) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "角色名称长度不能超过 64 个字符");
        }
        String baseTemplate = normalizeBaseTemplate(request.baseTemplate());
        if (authRoleRepository.existsByCode(code)) {
            throw new BusinessException(ErrorCode.CONFLICT, "角色编码已存在");
        }
        Set<AuthPermission> templatePermissions = baseTemplatePermissions(baseTemplate);
        if (!adminActorGuard.isSuperAdmin(actor)) {
            adminActorGuard.requireGrantWithinActorScope(actor, templatePermissions.stream()
                    .map(AuthPermission::getCode)
                    .collect(Collectors.toSet()));
        }
        AuthRole role = new AuthRole();
        role.setCode(code);
        role.setName(name);
        role.setDescription(normalizeOptionalText(request.description(), 500));
        role.setBuiltIn(false);
        role.setEnabled(true);
        role.getPermissions().addAll(templatePermissions);
        authRoleRepository.save(role);
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("code", code);
        payload.put("baseTemplate", baseTemplate);
        payload.put("permissionCount", templatePermissions.size());
        auditLogService.recordWithPayload(actorUserId, "ADMIN_ROLE_CREATE", "auth_roles", role.getId(), payload);
        return toRoleDetail(role);
    }

    /**
     * 删除自定义角色。
     *
     * <p>内置角色不可删除；仍有用户绑定时拒绝并提示先解绑。数据库无外键，
     * auth_role_permissions 绑定行由应用层级联处理：清空权限集合使 Hibernate
     * 在删除角色行之前先移除全部绑定行。绑定用户数为零时 auth_user_roles 不存在孤儿行；
     * 校验与删除之间存在并发绑定窗口，属管理员操作可接受残余风险。</p>
     *
     * @param actorUserId 操作者用户标识
     * @param roleCode 角色编码
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteRole(UUID actorUserId, String roleCode) {
        adminActorGuard.requireFreshAdminActor(actorUserId);
        String normalizedRoleCode = normalizeRoleCode(roleCode);
        AuthRole role = authRoleRepository.findWithPermissionsByCode(normalizedRoleCode)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "角色不存在"));
        if (role.isBuiltIn()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "内置角色不能删除");
        }
        if (authUserRepository.existsByRoles_Code(normalizedRoleCode)) {
            throw new BusinessException(ErrorCode.RESOURCE_IN_USE, "仍有用户绑定该角色，请先解绑后再删除");
        }
        int permissionCount = role.getPermissions().size();
        role.getPermissions().clear();
        authRoleRepository.delete(role);
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("code", normalizedRoleCode);
        payload.put("permissionCount", permissionCount);
        auditLogService.recordWithPayload(actorUserId, "ADMIN_ROLE_DELETE", "auth_roles", role.getId(), payload);
    }

    private AdminOperationsDto.RoleDetail toRoleDetail(AuthRole role) {
        List<String> permissions = role.getPermissions().stream()
                .filter(AuthPermission::isEnabled)
                .map(AuthPermission::getCode)
                .sorted()
                .toList();
        return new AdminOperationsDto.RoleDetail(
                role.getCode(),
                role.getName(),
                role.getDescription(),
                role.isBuiltIn(),
                role.isEnabled(),
                permissions
        );
    }

    private AdminOperationsDto.PermissionDetail toPermissionDetail(AuthPermission permission) {
        return new AdminOperationsDto.PermissionDetail(
                permission.getCode(),
                permission.getName(),
                permission.getModule(),
                permission.getDescription(),
                permission.isEnabled()
        );
    }

    private Set<String> normalizeCodes(Set<String> rawCodes) {
        if (rawCodes == null || rawCodes.isEmpty()) {
            return Set.of();
        }
        return rawCodes.stream()
                .map(code -> code == null ? "" : code.trim())
                .filter(code -> !code.isEmpty())
                .sorted(Comparator.naturalOrder())
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    private String normalizeRoleCode(String roleCode) {
        String normalized = roleCode == null ? "" : roleCode.trim().toUpperCase(Locale.ROOT);
        if (normalized.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "角色编码不能为空");
        }
        return normalized;
    }

    /**
     * 校验并归一化自定义角色编码：去除空白并大写化后必须满足 ROLE_ 前缀规则。
     */
    private String normalizeNewRoleCode(String rawCode) {
        String code = rawCode == null ? "" : rawCode.trim().toUpperCase(Locale.ROOT);
        if (code.length() < 3 || code.length() > 64) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "角色编码长度必须在 3 到 64 个字符之间");
        }
        if (!CUSTOM_ROLE_CODE_PATTERN.matcher(code).matches()) {
            throw new BusinessException(
                    ErrorCode.PARAM_ERROR, "角色编码必须以 ROLE_ 开头且仅含大写字母、数字或下划线");
        }
        return code;
    }

    /**
     * 归一化权限模板编码，空白视为 none。
     */
    private String normalizeBaseTemplate(String rawTemplate) {
        if (rawTemplate == null || rawTemplate.isBlank()) {
            return "NONE";
        }
        String template = rawTemplate.trim().toUpperCase(Locale.ROOT);
        if (!ROLE_BASE_TEMPLATES.contains(template)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "权限模板必须是 none、member 或 admin");
        }
        return template;
    }

    /**
     * 读取模板角色当前绑定的权限集合，模板角色未初始化时按内部错误返回。
     */
    private Set<AuthPermission> baseTemplatePermissions(String baseTemplate) {
        if ("NONE".equals(baseTemplate)) {
            return Set.of();
        }
        String templateCode = ROLE_TEMPLATE_CODES.get(baseTemplate);
        AuthRole template = authRoleRepository.findWithPermissionsByCode(templateCode)
                .orElseThrow(() -> new BusinessException(ErrorCode.INTERNAL_ERROR, "模板角色未初始化"));
        return Set.copyOf(template.getPermissions());
    }

    /**
     * 归一化可选文本：去空白，空值返回 null，超长返回参数错误。
     */
    private String normalizeOptionalText(String value, int maxLength) {
        String normalized = value == null ? "" : value.trim();
        if (normalized.isEmpty()) {
            return null;
        }
        if (normalized.length() > maxLength) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "文本长度不能超过 " + maxLength + " 个字符");
        }
        return normalized;
    }

    private String normalizeText(String value, String errorMessage) {
        String normalized = value == null ? "" : value.trim();
        if (normalized.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, errorMessage);
        }
        return normalized;
    }
}
