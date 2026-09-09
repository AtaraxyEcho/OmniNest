package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.user.domain.UserStatus;
import com.omninest.common.security.Permissions;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.repository.AuthUserRepository;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 管理同步事件服务测试。
 *
 * @author OmniNest
 */
class AdminSyncEventServiceTest {

    private static final UUID ADMIN_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID RESOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final UserSyncEventRecorder syncEventRecorder = mock(UserSyncEventRecorder.class);
    private final AdminSyncEventService service = new AdminSyncEventService(
            authUserRepository,
            syncEventRecorder
    );

    @Test
    void userActionTargetsUsersWithUserReadPermission() {
        AuthUser admin = new AuthUser();
        admin.setId(ADMIN_ID);
        when(authUserRepository.findDistinctByRoles_Permissions_CodeAndStatus(
                Permissions.SYSTEM_USER_READ,
                UserStatus.ACTIVE.getValue()
        )).thenReturn(List.of(admin));

        service.record("ADMIN_USER_STATUS_UPDATE", "auth_users", RESOURCE_ID);

        ArgumentCaptor<SyncEventCommand> commandCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        verify(syncEventRecorder).record(commandCaptor.capture());
        SyncEventCommand command = commandCaptor.getValue();
        assertThat(command.recipientUserId()).isEqualTo(ADMIN_ID);
        assertThat(command.scope()).isEqualTo(SyncScope.ADMIN);
        assertThat(command.resourceType()).isEqualTo("auth_users");
        assertThat(command.resourceId()).isEqualTo(RESOURCE_ID.toString());
        assertThat(command.action()).isEqualTo(SyncAction.UPDATED);
        assertThat(command.hints()).containsEntry("action", "ADMIN_USER_STATUS_UPDATE");
    }

    @Test
    void taskActionTargetsUsersWithTaskAdminPermission() {
        when(authUserRepository.findDistinctByRoles_Permissions_CodeAndStatus(
                Permissions.TASK_ADMIN,
                UserStatus.ACTIVE.getValue()
        )).thenReturn(List.of());

        service.record("ADMIN_TASK_RETRY", "sys_tasks", RESOURCE_ID);

        verify(authUserRepository).findDistinctByRoles_Permissions_CodeAndStatus(
                Permissions.TASK_ADMIN,
                UserStatus.ACTIVE.getValue()
        );
    }
}
