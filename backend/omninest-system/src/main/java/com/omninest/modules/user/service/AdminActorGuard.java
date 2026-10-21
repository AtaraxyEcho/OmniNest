package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.Roles;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.AuthUserMapper;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 管理台操作者边界：以数据库当前状态复核操作者权限，并约束其可授予的权限范围。
 *
 * <p>访问令牌里的 roles/permissions 声明签发后不再更新，管理台写操作必须以
 * {@code auth_users}/{@code auth_roles} 的当前绑定为准，否则被降权的用户在其令牌
 * 有效期内仍能继续改角色。</p>
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class AdminActorGuard {

    private final AuthUserRepository authUserRepository;

    /**
     * 读取操作者当前角色与权限，校验其仍具备管理台身份。
     *
     * @param actorUserId 操作者用户标识
     * @return 已加载角色与权限的用户实体
     */
    public AuthUser requireFreshAdminActor(UUID actorUserId) {
        AuthUser actor = authUserRepository.findWithRolesAndPermissionsById(actorUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "操作者不存在"));
        if (!UserStatus.ACTIVE.getValue().equals(actor.getStatus())) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "操作者不可用");
        }
        Set<String> roleCodes = AuthUserMapper.roleCodes(actor);
        if (!roleCodes.contains(Roles.SUPER_ADMIN) && !roleCodes.contains(Roles.ADMIN)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "操作者已失去管理权限");
        }
        return actor;
    }

    /**
     * 判断操作者是否为超级管理员。
     *
     * @param actor 已由 {@link #requireFreshAdminActor(UUID)} 加载的操作者
     * @return 是否超级管理员
     */
    public boolean isSuperAdmin(AuthUser actor) {
        return AuthUserMapper.roleCodes(actor).contains(Roles.SUPER_ADMIN);
    }

    /**
     * 校验对管理员账户的敏感操作只能由超级管理员发起。
     *
     * <p>普通管理员之间互为同级，改状态、重置验证器或强制吊销会话都足以把对方挡在门外，
     * 因此这类操作必须更高层级把关；操作自己的账户不受约束。</p>
     *
     * @param actor 已由 {@link #requireFreshAdminActor(UUID)} 加载的操作者
     * @param target 目标用户
     * @param action 操作描述，用于错误文案
     */
    public void requireSuperAdminForAdminTarget(AuthUser actor, AuthUser target, String action) {
        if (actor.getId().equals(target.getId())) {
            return;
        }
        Set<String> targetRoles = AuthUserMapper.roleCodes(target);
        if (!targetRoles.contains(Roles.ADMIN) && !targetRoles.contains(Roles.SUPER_ADMIN)) {
            return;
        }
        if (!isSuperAdmin(actor)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "仅超级管理员可" + action);
        }
    }

    /**
     * 校验待授予的权限编码是操作者自身权限集合的子集，阻止自助提权。
     *
     * <p>角色权限只影响绑定到该角色的用户，操作者将自己角色的权限放大等同于给自己授权，
     * 因此授予范围不得超过其当前生效的权限；超级管理员持有权限全集，不受该约束。</p>
     *
     * @param actor 已由 {@link #requireFreshAdminActor(UUID)} 加载的操作者
     * @param requestedCodes 待授予的权限编码集合
     */
    public void requireGrantWithinActorScope(AuthUser actor, Set<String> requestedCodes) {
        if (requestedCodes.isEmpty()) {
            return;
        }
        Set<String> actorCodes = AuthUserMapper.permissionCodes(actor);
        List<String> exceeded = requestedCodes.stream()
                .filter(code -> !actorCodes.contains(code))
                .sorted(Comparator.naturalOrder())
                .toList();
        if (!exceeded.isEmpty()) {
            throw new BusinessException(ErrorCode.FORBIDDEN,
                    "不能授予操作者自身不具备的权限：" + String.join(", ", exceeded));
        }
    }
}
