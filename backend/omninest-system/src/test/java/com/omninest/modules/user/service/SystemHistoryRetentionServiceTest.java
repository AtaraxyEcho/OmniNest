package com.omninest.modules.user.service;

import com.omninest.modules.configcenter.service.ConfigHistoryRetentionService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.user.config.SystemHistoryRetentionProperties;
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
 * 系统任务与审计日志保留清理测试。
 *
 * @author OmniNest
 */
class SystemHistoryRetentionServiceTest {
    private final TaskRecordService taskRecordService = Mockito.mock(TaskRecordService.class);
    private final AuditLogRetentionRepository auditLogRepository = Mockito.mock(AuditLogRetentionRepository.class);
    private final ConfigHistoryRetentionService configHistoryRetentionService =
            Mockito.mock(ConfigHistoryRetentionService.class);
    private final SystemHistoryRetentionProperties properties = new SystemHistoryRetentionProperties();
    private final SystemHistoryRetentionService service = new SystemHistoryRetentionService(
            taskRecordService,
            auditLogRepository,
            configHistoryRetentionService,
            properties
    );

    @BeforeEach
    void setUp() {
        properties.setEnabled(true);
        properties.setTaskMaximumAge(Duration.ofDays(30));
        properties.setAuditMaximumAge(Duration.ofDays(365));
        properties.setConfigMaximumAge(Duration.ofDays(365));
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

        Mockito.verifyNoInteractions(taskRecordService, auditLogRepository, configHistoryRetentionService);
    }
}
