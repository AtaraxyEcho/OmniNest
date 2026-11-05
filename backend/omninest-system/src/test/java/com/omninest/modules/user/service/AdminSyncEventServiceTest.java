package com.omninest.modules.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.user.domain.UserStatus;
import com.omninest.common.security.Permissions;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
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
    private static final UUID SECOND_ADMIN_ID = UUID.fromString("10000000-0000-0000-0000-000000000002");
    private static final UUID RESOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final AuthUserRepository authUserRepository = mock(AuthUserRepository.class);
    private final UserSyncEventRecorder syncEventRecorder = mock(UserSyncEventRecorder.class);
    private final AdminSyncEventService service = new AdminSyncEventService(
            authUserRepository,
            syncEventRecorder
    );

    @Test
    void userActionTargetsUsersWithUserReadPermission() {
        when(authUserRepository.findIdsByPermissionCodeAndStatus(
                Permissions.SYSTEM_USER_READ,
                UserStatus.ACTIVE.getValue()
        )).thenReturn(List.of(ADMIN_ID));

        service.record("ADMIN_USER_STATUS_UPDATE", "auth_users", RESOURCE_ID);

        ArgumentCaptor<List<SyncEventCommand>> captor = commandListCaptor();
        verify(syncEventRecorder).recordAll(captor.capture());
        SyncEventCommand command = captor.getValue().getFirst();
        assertThat(command.recipientUserId()).isEqualTo(ADMIN_ID);
        assertThat(command.scope()).isEqualTo(SyncScope.ADMIN);
        assertThat(command.resourceType()).isEqualTo("auth_users");
        assertThat(command.resourceId()).isEqualTo(RESOURCE_ID.toString());
        assertThat(command.action()).isEqualTo(SyncAction.UPDATED);
        assertThat(command.hints()).containsEntry("action", "ADMIN_USER_STATUS_UPDATE");
    }

    @Test
    void allRecipientsGoOutInOneBatch() {
        when(authUserRepository.findIdsByPermissionCodeAndStatus(
                Permissions.SYSTEM_CONFIG_READ,
                UserStatus.ACTIVE.getValue()
        )).thenReturn(List.of(ADMIN_ID, SECOND_ADMIN_ID));

        service.record("ADMIN_CONFIG_UPDATE", "config_entries", RESOURCE_ID);

        ArgumentCaptor<List<SyncEventCommand>> captor = commandListCaptor();
        verify(syncEventRecorder).recordAll(captor.capture());
        assertThat(captor.getValue())
                .extracting(SyncEventCommand::recipientUserId)
                .containsExactly(ADMIN_ID, SECOND_ADMIN_ID);
        // 逐个记录会把一次审计放大成 N 次 insert，广播必须走批量入口。
        verify(syncEventRecorder, never()).record(org.mockito.ArgumentMatchers.any());
    }

    @Test
    void taskActionTargetsUsersWithTaskAdminPermission() {
        when(authUserRepository.findIdsByPermissionCodeAndStatus(
                Permissions.TASK_ADMIN,
                UserStatus.ACTIVE.getValue()
        )).thenReturn(List.of());

        service.record("ADMIN_TASK_RETRY", "sys_tasks", RESOURCE_ID);

        verify(authUserRepository).findIdsByPermissionCodeAndStatus(
                Permissions.TASK_ADMIN,
                UserStatus.ACTIVE.getValue()
        );
        // 没有收件人时不应产生空批次的写入调用。
        verify(syncEventRecorder, never()).recordAll(anyList());
    }

    @SuppressWarnings("unchecked")
    private static ArgumentCaptor<List<SyncEventCommand>> commandListCaptor() {
        return ArgumentCaptor.forClass(List.class);
    }
}
