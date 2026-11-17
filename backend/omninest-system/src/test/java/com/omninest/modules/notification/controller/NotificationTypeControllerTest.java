package com.omninest.modules.notification.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.audit.AdminAuditRecorder;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.modules.notification.domain.NotificationType;
import com.omninest.modules.notification.repository.NotificationTypeRepository;
import com.omninest.modules.notification.service.NotificationTypeService;
import com.omninest.common.security.FreshAdminActorVerifier;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;

/**
 * 通知类型控制器测试。
 *
 * @author OmniNest
 */
class NotificationTypeControllerTest {

    private final NotificationTypeRepository repository = mock(NotificationTypeRepository.class);
    private final NotificationTypeService service = new NotificationTypeService(repository);
    private final CurrentUserContext currentUserContext = mock(CurrentUserContext.class);
    private final FreshAdminActorVerifier adminActorGuard = mock(FreshAdminActorVerifier.class);
    private final AdminAuditRecorder adminAuditRecorder = mock(AdminAuditRecorder.class);
    private final NotificationTypeController controller = new NotificationTypeController(
            service,
            currentUserContext,
            adminActorGuard,
            adminAuditRecorder
    );

    @Test
    void listEnabled_returnsOnlyEnabledTypes() {
        NotificationType enabled = type("TASK_COMPLETED", "任务完成", true);
        when(repository.findByEnabledTrueOrderBySortOrderAsc()).thenReturn(List.of(enabled));

        var response = controller.listEnabled();

        assertThat(response.getData()).hasSize(1);
        assertThat(response.getData().get(0).typeCode()).isEqualTo("TASK_COMPLETED");
    }

    @Test
    void listAll_returnsAllTypes() {
        NotificationType enabled = type("TASK_COMPLETED", "任务完成", true);
        NotificationType disabled = type("TASK_FAILED", "任务失败", false);
        when(repository.findAll()).thenReturn(List.of(enabled, disabled));

        var response = controller.listAll();

        assertThat(response.getData()).hasSize(2);
    }

    @Test
    void update_updatesExistingType() {
        UUID id = UUID.randomUUID();
        UUID actorUserId = UUID.randomUUID();
        NotificationType existing = type(id, "TASK_COMPLETED", "任务完成", true);
        when(currentUserContext.requireCurrentUserId()).thenReturn(actorUserId);
        when(repository.findById(id)).thenReturn(Optional.of(existing));
        when(repository.save(ArgumentMatchers.any(NotificationType.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var request = new NotificationTypeController.UpdateTypeRequest(
                "任务完成（更新）", "新描述", "new_icon", "#FFFFFF", 10, false
        );
        var response = controller.update(id, request);

        assertThat(response.getData().label()).isEqualTo("任务完成（更新）");
        assertThat(response.getData().description()).isEqualTo("新描述");
        assertThat(response.getData().icon()).isEqualTo("new_icon");
        assertThat(response.getData().color()).isEqualTo("#FFFFFF");
        assertThat(response.getData().sortOrder()).isEqualTo(10);
        assertThat(response.getData().enabled()).isFalse();
        verify(adminActorGuard).requireFreshAdminActor(actorUserId);
        verify(adminAuditRecorder).recordWithMetadata(
                eq(actorUserId),
                eq("ADMIN_NOTIFICATION_TYPE_UPDATE"),
                eq("notification_types"),
                eq(id),
                any()
        );
        verify(repository).save(existing);
    }

    private NotificationType type(String typeCode, String label, boolean enabled) {
        return type(UUID.randomUUID(), typeCode, label, enabled);
    }

    private NotificationType type(UUID id, String typeCode, String label, boolean enabled) {
        NotificationType t = new NotificationType();
        t.setId(id);
        t.setTypeCode(typeCode);
        t.setLabel(label);
        t.setDescription("描述");
        t.setIcon("icon");
        t.setColor("#000000");
        t.setSortOrder(1);
        t.setEnabled(enabled);
        t.setCreatedAt(Instant.parse("2026-05-27T10:00:00Z"));
        return t;
    }
}
