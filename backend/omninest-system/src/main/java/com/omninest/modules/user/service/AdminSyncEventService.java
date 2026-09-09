package com.omninest.modules.user.service;

import com.omninest.modules.user.domain.UserStatus;
import com.omninest.common.security.Permissions;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 将管理审计动作转换为有权限用户可见的持久同步事件。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class AdminSyncEventService {

    private final AuthUserRepository authUserRepository;
    private final UserSyncEventRecorder syncEventRecorder;

    /**
     * 记录管理数据更新事件。
     *
     * @param action 管理动作
     * @param resourceType 资源类型
     * @param resourceId 资源标识
     */
    public void record(String action, String resourceType, UUID resourceId) {
        String permission = resolveReadPermission(action);
        List<AuthUser> recipients = authUserRepository.findDistinctByRoles_Permissions_CodeAndStatus(
                permission,
                UserStatus.ACTIVE.getValue()
        );
        recipients.forEach(user -> syncEventRecorder.record(new SyncEventCommand(
                user.getId(),
                SyncScope.ADMIN,
                resourceType,
                resourceId == null ? null : resourceId.toString(),
                SyncAction.UPDATED,
                null,
                Map.of("action", action)
        )));
    }

    private String resolveReadPermission(String action) {
        if (action.contains("USER") || action.contains("ROLE")
                || action.contains("SESSION") || action.contains("LOGIN")) {
            return Permissions.SYSTEM_USER_READ;
        }
        if (action.contains("TASK") || action.contains("DLQ")) {
            return Permissions.TASK_ADMIN;
        }
        return Permissions.SYSTEM_CONFIG_READ;
    }
}
