package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.modules.video.domain.MediaScanRun;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.dto.MediaScanDtos.ApplySelectionRequest;
import com.omninest.modules.video.repository.MediaScanCandidateRepository;
import com.omninest.modules.video.repository.MediaScanRunRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class MediaLibraryReviewServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID RUN_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    @Mock
    private MediaScanRunRepository runRepository;
    @Mock
    private MediaScanCandidateRepository candidateRepository;
    @Mock
    private VideoLibrarySourceRepository sourceRepository;
    @Mock
    private MediaVideoItemRepository videoItemRepository;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private TaskDispatchService taskDispatchService;
    @Mock
    private MediaLibraryAccessService accessService;

    private MediaLibraryReviewService service;
    private MediaScanRun run;
    private VideoLibrarySource source;

    @BeforeEach
    void setUp() {
        service = new MediaLibraryReviewService(
                runRepository,
                candidateRepository,
                sourceRepository,
                videoItemRepository,
                taskRecordService,
                taskDispatchService,
                accessService
        );
        run = new MediaScanRun();
        run.setId(RUN_ID);
        run.setOwnerUserId(OWNER_ID);
        run.setLibrarySourceId(SOURCE_ID);
        run.setStatus("READY");
        run.setPhase("DISCOVERY");
        run.setSelectionRevision(4);
        source = new VideoLibrarySource();
        source.setId(SOURCE_ID);
        source.setOwnerUserId(OWNER_ID);
        source.setScanStatus("READY");
        when(runRepository.findById(RUN_ID)).thenReturn(Optional.of(run));
        when(accessService.requireManage(OWNER_ID, SOURCE_ID)).thenReturn(source);
    }

    @Test
    void applyLocksSelectionBeforeDispatchingTask() {
        when(candidateRepository.countByOwnerUserIdAndScanRunIdAndSelectedTrue(OWNER_ID, RUN_ID)).thenReturn(3L);
        var result = service.apply(OWNER_ID, RUN_ID, new ApplySelectionRequest(4L));

        assertThat(result.status()).isEqualTo("QUEUED");
        assertThat(run.getStatus()).isEqualTo("QUEUED");
        assertThat(run.getPhase()).isEqualTo("APPLY");
        assertThat(run.getApplyTaskId()).isEqualTo(result.taskId());
        assertThat(source.getScanStatus()).isEqualTo("QUEUED");
        verify(taskRecordService).createQueuedTask(
                eq(result.taskId()),
                eq(OWNER_ID),
                eq("LOCAL_VIDEO_LIBRARY_APPLY"),
                any(),
                eq("QUEUED"),
                eq("MEDIA_SCAN_RUN"),
                eq(RUN_ID),
                any()
        );
        verify(taskDispatchService).enqueue(eq(result.taskId()), any(), any(), any());
    }

    @Test
    void applyRejectsStaleSelectionRevisionBeforeCreatingTask() {
        assertThatThrownBy(() -> service.apply(OWNER_ID, RUN_ID, new ApplySelectionRequest(3L)))
                .isInstanceOfSatisfying(BusinessException.class, exception ->
                        assertThat(exception.errorCode()).isEqualTo(ErrorCode.CONFLICT));

        verify(taskRecordService, never()).createQueuedTask(any(), any(), any(), any(), any(), any(), any(), any());
        verify(taskDispatchService, never()).enqueue(any(), any(), any(), any());
    }
}
