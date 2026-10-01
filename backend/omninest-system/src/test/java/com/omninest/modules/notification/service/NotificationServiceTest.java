package com.omninest.modules.notification.service;

import java.util.function.Supplier;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.cache.ReadThroughCache;
import com.omninest.common.error.BusinessException;
import com.omninest.common.preferences.UserPreferenceQuery;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.notification.domain.NotificationMessage;
import com.omninest.modules.notification.domain.NotificationType;
import com.omninest.modules.notification.dto.NotificationDto;
import com.omninest.modules.notification.repository.NotificationRepository;
import com.omninest.modules.notification.repository.NotificationTypeRepository;
import java.time.Instant;
import java.time.LocalTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.data.domain.Pageable;
import org.springframework.transaction.PlatformTransactionManager;

class NotificationServiceTest {

    private final NotificationRepository notificationRepository = mock(NotificationRepository.class);
    private final NotificationTypeRepository notificationTypeRepository = mock(NotificationTypeRepository.class);
    private final UserPreferenceQuery userPreferenceQuery = mock(UserPreferenceQuery.class);
    private final UserSyncEventRecorder syncEventRecorder = mock(UserSyncEventRecorder.class);
    private final ReadThroughCache readThroughCache = mock(ReadThroughCache.class, invocation -> {
        if ("getOrLoad".equals(invocation.getMethod().getName())) {
            Supplier<?> loader = invocation.getArgument(2);
            return loader.get();
        }
        return null;
    });
    private final PlatformTransactionManager transactionManager = mock(PlatformTransactionManager.class);
    private final NotificationService service = new NotificationService(
            notificationRepository,
            notificationTypeRepository,
            userPreferenceQuery,
            readThroughCache,
            syncEventRecorder,
            transactionManager
    );

    @Test
    void create_typeDisabled_throwsException() {
        UUID userId = UUID.randomUUID();
        NotificationType disabledType = type("TASK_COMPLETED", false);
        when(notificationTypeRepository.findByTypeCode("TASK_COMPLETED")).thenReturn(Optional.of(disabledType));

        assertThatThrownBy(() ->
                service.create(userId, "TASK_COMPLETED", "标题", "内容", null)
        ).isInstanceOf(BusinessException.class)
                .hasMessageContaining("已禁用");
    }

    @Test
    void create_typeNotFound_throwsException() {
        UUID userId = UUID.randomUUID();
        when(notificationTypeRepository.findByTypeCode("UNKNOWN")).thenReturn(Optional.empty());

        assertThatThrownBy(() ->
                service.create(userId, "UNKNOWN", "标题", "内容", null)
        ).isInstanceOf(BusinessException.class)
                .hasMessageContaining("不存在");
    }

    @Test
    void create_userDisabledType_returnsNull() {
        UUID userId = UUID.randomUUID();
        NotificationType enabledType = type("TASK_COMPLETED", true);
        when(notificationTypeRepository.findByTypeCode("TASK_COMPLETED")).thenReturn(Optional.of(enabledType));
        when(userPreferenceQuery.findValues(userId, "notification")).thenReturn(
                Map.of(
                        "enabled", true,
                        "types", Map.of("TASK_COMPLETED", false)
                )
        );

        NotificationDto result = service.create(userId, "TASK_COMPLETED", "标题", "内容", null);

        assertThat(result).isNull();
        verify(notificationRepository, never()).save(any());
    }

    @Test
    void create_globalDisabled_returnsNull() {
        UUID userId = UUID.randomUUID();
        NotificationType enabledType = type("TASK_COMPLETED", true);
        when(notificationTypeRepository.findByTypeCode("TASK_COMPLETED")).thenReturn(Optional.of(enabledType));
        when(userPreferenceQuery.findValues(userId, "notification")).thenReturn(
                Map.of("enabled", false)
        );

        NotificationDto result = service.create(userId, "TASK_COMPLETED", "标题", "内容", null);

        assertThat(result).isNull();
        verify(notificationRepository, never()).save(any());
    }

    @Test
    void create_normalCase_persistsAndRecordsEvent() {
        UUID userId = UUID.randomUUID();
        NotificationType enabledType = type("TASK_COMPLETED", true);
        when(notificationTypeRepository.findByTypeCode("TASK_COMPLETED")).thenReturn(Optional.of(enabledType));
        when(userPreferenceQuery.findValues(userId, "notification")).thenReturn(
                Map.of("enabled", true)
        );
        when(notificationRepository.save(any(NotificationMessage.class)))
                .thenAnswer(invocation -> {
                    NotificationMessage msg = invocation.getArgument(0);
                    msg.setId(UUID.randomUUID());
                    msg.setCreatedAt(Instant.now());
                    return msg;
                });

        NotificationDto result = service.create(userId, "TASK_COMPLETED", "标题", "内容", Map.of("key", "val"));

        assertThat(result).isNotNull();
        assertThat(result.title()).isEqualTo("标题");
        verify(notificationRepository).save(any());
        ArgumentCaptor<SyncEventCommand> eventCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        verify(syncEventRecorder).record(eventCaptor.capture());
        assertThat(eventCaptor.getValue().scope()).isEqualTo(SyncScope.NOTIFICATIONS);
        assertThat(eventCaptor.getValue().action()).isEqualTo(SyncAction.CREATED);
    }

    @Test
    void create_typeNotInPrefs_defaultsToEnabled() {
        UUID userId = UUID.randomUUID();
        NotificationType enabledType = type("SYSTEM_MESSAGE", true);
        when(notificationTypeRepository.findByTypeCode("SYSTEM_MESSAGE")).thenReturn(Optional.of(enabledType));
        // types 为空，表示全部启用
        when(userPreferenceQuery.findValues(userId, "notification")).thenReturn(
                Map.of("enabled", true)
        );
        when(notificationRepository.save(any(NotificationMessage.class)))
                .thenAnswer(invocation -> {
                    NotificationMessage msg = invocation.getArgument(0);
                    msg.setId(UUID.randomUUID());
                    msg.setCreatedAt(Instant.now());
                    return msg;
                });

        NotificationDto result = service.create(userId, "SYSTEM_MESSAGE", "系统消息", "内容", null);

        assertThat(result).isNotNull();
        verify(notificationRepository).save(any());
    }

    @Test
    void notifyOrLog_doesNotThrowWhenCreateFails() {
        // Arrange: make create() throw
        when(notificationTypeRepository.findByTypeCode(any())).thenThrow(new RuntimeException("DB error"));
        // Act & Assert: should not throw
        assertDoesNotThrow(() -> service.notifyOrLog(UUID.randomUUID(), "TASK_COMPLETED", "title", "msg", Map.of()));
    }

    @Test
    void markRead_onlyUpdatesCurrentUserNotifications() {
        UUID userId = UUID.randomUUID();
        UUID notificationId = UUID.randomUUID();
        List<UUID> notificationIds = List.of(notificationId);
        when(notificationRepository.markRead(eq(userId), eq(notificationIds), any(Instant.class))).thenReturn(1);

        int updated = service.markRead(userId, notificationIds);

        assertThat(updated).isEqualTo(1);
        verify(notificationRepository).markRead(eq(userId), eq(notificationIds), any(Instant.class));
        verify(readThroughCache).invalidate("omninest:notification:unread:" + userId);
    }

    @Test
    void deleteOnlyRemovesCurrentUsersNotification() {
        UUID userId = UUID.randomUUID();
        UUID notificationId = UUID.randomUUID();
        when(notificationRepository.deleteForRecipient(userId, notificationId)).thenReturn(1);

        int deleted = service.delete(userId, notificationId);

        assertThat(deleted).isEqualTo(1);
        verify(notificationRepository).deleteForRecipient(userId, notificationId);
        verify(readThroughCache).invalidate("omninest:notification:unread:" + userId);
        ArgumentCaptor<SyncEventCommand> eventCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        verify(syncEventRecorder).record(eventCaptor.capture());
        assertThat(eventCaptor.getValue().action()).isEqualTo(SyncAction.DELETED);
        assertThat(eventCaptor.getValue().resourceId()).isEqualTo(notificationId.toString());
    }

    @Test
    void clearAllUsesBulkDeleteAndRecordsDeletedCount() {
        UUID userId = UUID.randomUUID();
        when(notificationRepository.deleteAllForRecipient(userId)).thenReturn(12);

        int deleted = service.clearAll(userId);

        assertThat(deleted).isEqualTo(12);
        verify(notificationRepository).deleteAllForRecipient(userId);
        verify(readThroughCache).invalidate("omninest:notification:unread:" + userId);
        ArgumentCaptor<SyncEventCommand> eventCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        verify(syncEventRecorder).record(eventCaptor.capture());
        assertThat(eventCaptor.getValue().action()).isEqualTo(SyncAction.DELETED);
        assertThat(eventCaptor.getValue().hints()).containsEntry("deletedCount", 12);
    }

    @Test
    void list_unreadOnly_usesUnreadQueryAndCount() {
        UUID userId = UUID.randomUUID();
        when(notificationRepository.findByRecipientUserIdAndReadAtIsNullOrderByCreatedAtDesc(
                eq(userId), any(Pageable.class)))
                .thenReturn(List.of());
        when(notificationRepository.countByRecipientUserIdAndReadAtIsNull(userId)).thenReturn(3L);

        var items = service.list(userId, 0, 20, true);
        long total = service.totalCount(userId, true);

        assertThat(items).isEmpty();
        assertThat(total).isEqualTo(3L);
        verify(notificationRepository, never())
                .findByRecipientUserIdOrderByCreatedAtDesc(eq(userId), any(Pageable.class));
        verify(notificationRepository, never()).countByRecipientUserId(userId);
    }

    @Test
    void list_all_usesGeneralQueryAndCount() {
        UUID userId = UUID.randomUUID();
        when(notificationRepository.findByRecipientUserIdOrderByCreatedAtDesc(
                eq(userId), any(Pageable.class)))
                .thenReturn(List.of());
        when(notificationRepository.countByRecipientUserId(userId)).thenReturn(18L);

        service.list(userId, 0, 20, false);
        long total = service.totalCount(userId, false);

        assertThat(total).isEqualTo(18L);
        verify(notificationRepository, never())
                .findByRecipientUserIdAndReadAtIsNullOrderByCreatedAtDesc(eq(userId), any(Pageable.class));
        verify(notificationRepository, never()).countByRecipientUserIdAndReadAtIsNull(userId);
    }

    private NotificationType type(String typeCode, boolean enabled) {
        NotificationType t = new NotificationType();
        t.setId(UUID.randomUUID());
        t.setTypeCode(typeCode);
        t.setLabel("标签");
        t.setEnabled(enabled);
        t.setSortOrder(1);
        t.setCreatedAt(Instant.now());
        return t;
    }
}
