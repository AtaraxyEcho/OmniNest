package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 视频转码生命周期并发测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class TranscodeExecutionServiceTest {
    @Mock
    private MediaVideoItemRepository videoItemRepository;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private VideoTranscodeService videoTranscodeService;
    @Mock
    private DerivedAssetStorageService derivedAssetStorageService;
    @Mock
    private TransactionTemplate transactionTemplate;
    @Mock
    private NotificationPublisher notificationService;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private FileLifecycleGuard fileLifecycleGuard;
    @InjectMocks
    private TranscodeExecutionService service;

    @BeforeEach
    void setUpTaskClaim() {
        Mockito.when(taskRecordService.claimForExecution(Mockito.any(UUID.class), Mockito.any(String.class)))
                .thenReturn(true);
    }

    @Test
    void executeCancelsBeforeTranscodeWhenSourceIsPurging() {
        UUID taskId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        UUID videoItemId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        MediaVideoItem item = new MediaVideoItem();
        item.setId(videoItemId);
        item.setOwnerUserId(ownerUserId);
        item.setFileNodeId(fileNodeId);
        Mockito.when(videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId))
                .thenReturn(Optional.of(item));
        Mockito.doThrow(new BusinessException(ErrorCode.FILE_LIFECYCLE_CONFLICT, "文件正在永久删除"))
                .when(fileLifecycleGuard).requireOwnedWritable(ownerUserId, fileNodeId);

        service.execute(taskId, videoItemId, ownerUserId);

        Mockito.verify(taskRecordService).markCancelled(taskId);
        Mockito.verifyNoInteractions(videoTranscodeService);
    }
}
