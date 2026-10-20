package com.omninest.modules.user.service;

import com.omninest.modules.configcenter.service.ConfigHistoryRetentionService;
import com.omninest.modules.notification.port.NotificationMaintenance;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.user.config.SystemHistoryRetentionProperties;
import com.omninest.modules.user.port.PurgeHistoryRetention;
import com.omninest.modules.user.repository.AuditLogRetentionRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;

/**
 * 系统历史保留清理测试。
 *
 * @author OmniNest
 */
class SystemHistoryRetentionServiceTest {
    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = Mockito.mock(TaskDispatchService.class);
    private final AuditLogRetentionRepository auditLogRepository = Mockito.mock(AuditLogRetentionRepository.class);
    private final ConfigHistoryRetentionService configHistoryRetentionService =
            Mockito.mock(ConfigHistoryRetentionService.class);
    private final PurgeHistoryRetention purgeHistoryRetention = Mockito.mock(PurgeHistoryRetention.class);
    private final NotificationMaintenance notificationMaintenance = Mockito.mock(NotificationMaintenance.class);
    private final SystemHistoryRetentionProperties properties = new SystemHistoryRetentionProperties();
    private final SystemHistoryRetentionService service = new SystemHistoryRetentionService(
            taskRecordService,
            taskDispatchService,
            auditLogRepository,
            configHistoryRetentionService,
            purgeHistoryRetention,
            notificationMaintenance,
            properties
    );

    @BeforeEach
    void setUp() {
        properties.setEnabled(true);
        properties.setTaskMaximumAge(Duration.ofDays(30));
        properties.setAuditMaximumAge(Duration.ofDays(365));
        properties.setConfigMaximumAge(Duration.ofDays(365));
        properties.setDispatchMaximumAge(Duration.ofDays(30));
        properties.setPurgeEntryMaximumAge(Duration.ofDays(30));
        properties.setNotificationMaximumAge(Duration.ofDays(90));
        properties.setConfigMinimumVersions(20);
        properties.setBatchSize(2);
        properties.setMaximumBatches(3);
    }

    @Test
    void cleanupDeletesBoundedTaskAndAuditBatches() {
        UUID first = UUID.randomUUID();
        UUID second = UUID.randomUUID();
        UUID third = UUID.randomUUID();
        Mockito.when(taskRecordService.deleteTerminalTaskBatchUpdatedBefore(
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq(2)
        )).thenReturn(2, 1);
        Mockito.when(auditLogRepository.findIdsCreatedBefore(
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.any()
        )).thenReturn(List.of(first, second)).thenReturn(List.of(third));
        Mockito.when(auditLogRepository.deleteByIds(List.of(first, second))).thenReturn(2);
        Mockito.when(auditLogRepository.deleteByIds(List.of(third))).thenReturn(1);
        Mockito.when(configHistoryRetentionService.deleteExpiredBatch(
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq(20),
                ArgumentMatchers.eq(2)
        )).thenReturn(2, 1);

        service.cleanup();

        Mockito.verify(taskRecordService, Mockito.times(2))
                .deleteTerminalTaskBatchUpdatedBefore(ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2));
        Mockito.verify(auditLogRepository).deleteByIds(List.of(first, second));
        Mockito.verify(auditLogRepository).deleteByIds(List.of(third));
        Mockito.verify(configHistoryRetentionService, Mockito.times(2))
                .deleteExpiredBatch(
                        ArgumentMatchers.any(Instant.class),
                        ArgumentMatchers.eq(20),
                        ArgumentMatchers.eq(2)
                );
    }

    /**
     * Outbox 投递行与物理删除条目同样按批次回收：两张表都保存完整载荷或明细行，
     * 不清理会无限增长。
     */
    @Test
    void cleanupDeletesDispatchAndPurgeEntryBatches() {
        Mockito.when(taskDispatchService.deletePublishedBatchBefore(
                ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2))).thenReturn(2, 1);
        Mockito.when(purgeHistoryRetention.deleteCompletedEntriesBefore(
                ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2))).thenReturn(2, 1);

        service.cleanup();

        Mockito.verify(taskDispatchService, Mockito.times(2))
                .deletePublishedBatchBefore(ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2));
        Mockito.verify(purgeHistoryRetention, Mockito.times(2))
                .deleteCompletedEntriesBefore(ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2));
    }

    /**
     * 已读站内通知按保留期分批回收：通知行带 jsonb 元数据且写入频繁。
     */
    @Test
    void cleanupDeletesReadNotificationBatches() {
        Mockito.when(notificationMaintenance.deleteReadNotificationsBefore(
                ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2))).thenReturn(2, 1);

        service.cleanup();

        Mockito.verify(notificationMaintenance, Mockito.times(2))
                .deleteReadNotificationsBefore(ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2));
    }

    @Test
    void cleanupSkipsRetentionsWithInvalidAge() {
        properties.setDispatchMaximumAge(Duration.ofDays(-1));
        properties.setPurgeEntryMaximumAge(Duration.ZERO);
        properties.setNotificationMaximumAge(null);

        service.cleanup();

        Mockito.verifyNoInteractions(taskDispatchService, purgeHistoryRetention, notificationMaintenance);
    }

    @Test
    void cleanupStopsAtConfiguredMaximumBatches() {
        properties.setMaximumBatches(2);
        Mockito.when(taskRecordService.deleteTerminalTaskBatchUpdatedBefore(
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq(2)
        )).thenReturn(2);
        Mockito.when(auditLogRepository.findIdsCreatedBefore(
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.any()
        )).thenReturn(List.of(UUID.randomUUID(), UUID.randomUUID()));
        Mockito.when(auditLogRepository.deleteByIds(ArgumentMatchers.anyList())).thenReturn(2);
        Mockito.when(configHistoryRetentionService.deleteExpiredBatch(
                ArgumentMatchers.any(Instant.class),
                ArgumentMatchers.eq(20),
                ArgumentMatchers.eq(2)
        )).thenReturn(2);

        service.cleanup();

        Mockito.verify(taskRecordService, Mockito.times(2))
                .deleteTerminalTaskBatchUpdatedBefore(ArgumentMatchers.any(Instant.class), ArgumentMatchers.eq(2));
        Mockito.verify(auditLogRepository, Mockito.times(2)).deleteByIds(ArgumentMatchers.anyList());
        Mockito.verify(configHistoryRetentionService, Mockito.times(2))
                .deleteExpiredBatch(
                        ArgumentMatchers.any(Instant.class),
                        ArgumentMatchers.eq(20),
                        ArgumentMatchers.eq(2)
                );
    }

    @Test
    void cleanupDoesNothingWhenDisabled() {
        properties.setEnabled(false);

        service.cleanup();

        Mockito.verifyNoInteractions(taskRecordService, taskDispatchService, auditLogRepository,
                configHistoryRetentionService, purgeHistoryRetention, notificationMaintenance);
    }
}
