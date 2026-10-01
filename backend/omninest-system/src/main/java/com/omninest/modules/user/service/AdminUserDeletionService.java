package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Roles;
import com.omninest.modules.notification.port.NotificationMaintenance;
import com.omninest.modules.preferences.service.UserPreferenceService;
import com.omninest.modules.quota.service.StorageQuotaReservationService;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AdminUserContentGuardRepository;
import com.omninest.modules.user.repository.AuthBackupCodeRepository;
import com.omninest.modules.user.repository.AuthTotpCredentialRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.util.AuthUserMapper;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理端用户物理删除服务。
 *
 * <p>删除采取安全门槛：目标用户不得是操作者本人或超级管理员，且必须是无任何业务
 * 内容占用的空账户（存储用量清零、关键内容表无归属记录），否则返回业务错误并
 * 提示先转移或清空内容。空账户删除时同步移除会话、会话撤销记录、两步验证凭据、
 * 备份码、角色绑定、配额预留、偏好与站内通知；操作审计与登录审计按追溯要求保留，
 * 未随账户删除。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class AdminUserDeletionService {
    private static final String DELETE_AUDIT_ACTION = "ADMIN_USER_DELETE";

    private final AuthUserRepository authUserRepository;
    private final ActiveSessionRepository activeSessionRepository;
    private final UserSessionRevocationService userSessionRevocationService;
    private final AuthTotpCredentialRepository authTotpCredentialRepository;
    private final AuthBackupCodeRepository authBackupCodeRepository;
    private final StorageQuotaReservationService storageQuotaReservationService;
    private final UserPreferenceService userPreferenceService;
    private final NotificationMaintenance notificationMaintenance;
    private final AdminUserContentGuardRepository adminUserContentGuardRepository;
    private final AdminAuditLogService auditLogService;
    private final CurrentUserContext currentUserContext;

    /**
     * 物理删除空账户用户。
     *
     * <p>删除前先撤销该用户全部令牌：撤销记录保留至保留期清理，已签发 access token
 * 即刻被认证过滤器拒绝。各模块观看历史、
     * 播放进度等用户活动记录不阻塞删除也不会被清理，作为已声明的残余孤儿风险
     * 由对应模块的保留策略兜底。</p>
     *
     * @param userId 目标用户标识
     */
    @Transactional(rollbackFor = Exception.class)
    public void deleteUser(UUID userId) {
        UUID actorUserId = currentUserContext.requireCurrentUserId();
        if (actorUserId.equals(userId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "不能删除当前登录账户");
        }
        AuthUser user = authUserRepository.findWithRolesById(userId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "用户不存在"));
        if (AuthUserMapper.roleCodes(user).contains(Roles.SUPER_ADMIN)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员账户不能删除");
        }
        requireEmptyAccount(user);
        // 先撤销全部令牌并保留撤销记录：认证过滤器按撤销记录拒绝已签发
        // access token（记录随保留期清理），避免删除会话行后旧令牌在 TTL
        // 窗口内继续可用。
        userSessionRevocationService.revokeAll(List.of(userId), "管理员删除用户");
        notificationMaintenance.adminPurgeForUser(userId);
        userPreferenceService.adminPurgeForUser(userId);
        storageQuotaReservationService.adminPurgeForUser(userId);
        authTotpCredentialRepository.deleteByUserId(userId);
        authBackupCodeRepository.deleteByUserId(userId);
        activeSessionRepository.deleteByUserId(userId);
        // 数据库无外键，auth_user_roles 绑定行由应用层级联处理：
        // 清空角色集合使 Hibernate 在删除用户行之前先移除全部绑定行。
        user.getRoles().clear();
        authUserRepository.delete(user);
        auditLogService.recordWithPayload(
                actorUserId,
                DELETE_AUDIT_ACTION,
                "auth_users",
                userId,
                Map.of("username", user.getUsername())
        );
    }

    /**
     * 校验目标是空账户：存储用量清零且关键内容表无归属记录。
     */
    private void requireEmptyAccount(AuthUser user) {
        if (user.getUsedBytes() > 0 || user.getReservedBytes() > 0) {
            throw new BusinessException(ErrorCode.RESOURCE_IN_USE, "用户存储用量未清零，请先转移或清空内容");
        }
        Map<String, Long> ownedContent = adminUserContentGuardRepository.countOwnedContent(user.getId());
        if (!ownedContent.isEmpty()) {
            throw new BusinessException(
                    ErrorCode.RESOURCE_IN_USE,
                    "用户仍持有业务内容（" + String.join("、", ownedContent.keySet()) + "），请先转移或清空"
            );
        }
    }
}
