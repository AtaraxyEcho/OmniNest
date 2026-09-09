package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.download.OfflineDownloadSourceResolver;
import com.omninest.common.download.OfflineDownloadSourceResolver.ResolvedSource;
import com.omninest.common.download.OfflineDownloadSourceResolver.SourceKind;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.file.domain.DownloadOfflineTask;
import com.omninest.modules.file.dto.CreateOfflineDownloadRequest;
import com.omninest.modules.file.event.OfflineDownloadRequestedEvent;
import com.omninest.modules.file.repository.DownloadOfflineTaskRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.net.URI;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 离线下载请求服务单元测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class OfflineDownloadRequestServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TASK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    @Mock
    private DownloadOfflineTaskRepository offlineTaskRepository;
    @Mock
    private FileNodeRepository fileNodeRepository;
    @Mock
    private OfflineDownloadSourceResolver sourceResolver;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private TaskDispatchService taskDispatchService;

    @InjectMocks
    private OfflineDownloadRequestService service;

    @BeforeEach
    void setUp() {
        when(offlineTaskRepository.save(any(DownloadOfflineTask.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    void createTaskPublishesDownloadRequest() {
        String sourceUri = "https://example.com/movie.mp4";
        when(sourceResolver.resolve(sourceUri))
                .thenReturn(new ResolvedSource(SourceKind.HTTP, URI.create(sourceUri)));

        var result = service.createTask(OWNER_ID, new CreateOfflineDownloadRequest(sourceUri, null));

        assertThat(result.id()).isNotNull();
        assertThat(result.taskId()).isEqualTo(result.id());
        assertThat(result.status()).isEqualTo("QUEUED");
        verify(taskRecordService).createQueuedTask(
                eq(result.taskId()),
                eq(OWNER_ID),
                eq("OFFLINE_DOWNLOAD"),
                eq(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY),
                any()
        );
        ArgumentCaptor<OfflineDownloadRequestedEvent> eventCaptor =
                ArgumentCaptor.forClass(OfflineDownloadRequestedEvent.class);
        verify(taskDispatchService).enqueue(
                eq(result.taskId()),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY),
                eventCaptor.capture()
        );
        assertThat(eventCaptor.getValue().taskId()).isEqualTo(result.id());
    }

    @Test
    void createTaskEnqueuesDispatchInsideActiveTransactionSynchronization() {
        String sourceUri = "https://example.com/movie.mp4";
        when(sourceResolver.resolve(sourceUri))
                .thenReturn(new ResolvedSource(SourceKind.HTTP, URI.create(sourceUri)));
        TransactionSynchronizationManager.initSynchronization();
        try {
            var result = service.createTask(OWNER_ID, new CreateOfflineDownloadRequest(sourceUri, null));

            // Outbox 行在事务内同步写入，不再延迟到事务提交后直发消息。
            ArgumentCaptor<OfflineDownloadRequestedEvent> eventCaptor =
                    ArgumentCaptor.forClass(OfflineDownloadRequestedEvent.class);
            verify(taskDispatchService).enqueue(
                    eq(result.taskId()),
                    eq(QueueNames.TASK_EXCHANGE),
                    eq(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY),
                    eventCaptor.capture()
            );
            assertThat(eventCaptor.getValue().taskId()).isEqualTo(result.id());
        } finally {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    @Test
    void cancelTaskMarksTaskCancelled() {
        DownloadOfflineTask task = new DownloadOfflineTask();
        task.setId(TASK_ID);
        task.setOwnerUserId(OWNER_ID);
        task.setStatus("RUNNING");
        when(offlineTaskRepository.findByIdAndOwnerUserId(TASK_ID, OWNER_ID))
                .thenReturn(Optional.of(task));

        service.cancelTask(OWNER_ID, TASK_ID);

        assertThat(task.getStatus()).isEqualTo("CANCELLED");
        verify(offlineTaskRepository).save(task);
        verify(taskRecordService).markCancelled(TASK_ID);
    }
}
