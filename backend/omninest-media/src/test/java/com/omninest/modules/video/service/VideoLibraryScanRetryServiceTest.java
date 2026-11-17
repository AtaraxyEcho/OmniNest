package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.event.LocalVideoLibraryScanRequestedEvent;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 本地影视库扫描重试策略测试。
 *
 * @author OmniNest
 */
class VideoLibraryScanRetryServiceTest {
    private static final UUID TASK_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OWNER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID RUN_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");

    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final VideoLibraryScanRetryService service = new VideoLibraryScanRetryService(
            taskRecordService,
            taskDispatchService
    );
    private final LocalVideoLibraryScanRequestedEvent event = new LocalVideoLibraryScanRequestedEvent(
            TASK_ID,
            OWNER_ID,
            SOURCE_ID,
            RUN_ID
    );

    @Test
    void dependencyFailureSchedulesFirstRetryAfterOneMinute() {
        when(taskRecordService.retryCount(TASK_ID)).thenReturn(0);
        when(taskRecordService.markRetryWait(eq(TASK_ID), eq("DEPENDENCY_UNAVAILABLE"), any()))
                .thenReturn(1);
        ArgumentCaptor<Instant> retryAt = ArgumentCaptor.forClass(Instant.class);
        Instant before = Instant.now();

        service.handleFailure(
                event,
                new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "存储位置暂不可用")
        );

        verify(taskDispatchService).enqueueAt(
                eq(TASK_ID),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY),
                eq(event),
                retryAt.capture()
        );
        assertThat(retryAt.getValue()).isBetween(before.plusSeconds(59), before.plusSeconds(62));
    }

    @Test
    void invalidPathFailsWithoutRetry() {
        service.handleFailure(
                event,
                new BusinessException(ErrorCode.FILE_PATH_INVALID, "路径无效")
        );

        verify(taskRecordService).markFailed(eq(TASK_ID), eq("FILE_PATH_INVALID"), any());
    }
}
